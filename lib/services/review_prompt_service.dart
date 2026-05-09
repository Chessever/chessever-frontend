import 'dart:async';
import 'dart:io';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/services/telegram_notification_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/review_prompt/review_prompt_dialogs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ReviewPromptTrigger {
  session,
  premium,
  favoriteEvent,
  favoritePlayer,
  sidebar,
}

class ReviewPromptService {
  ReviewPromptService._();

  static final ReviewPromptService instance = ReviewPromptService._();

  // Cooldown between prompts
  static const Duration _cooldown = Duration(days: 30);

  // Longer cooldown after a high rating. Replaces the previous "permanent
  // block" behavior — the OS may have suppressed the native dialog (debug
  // build, quota, user-disabled), so we allow a re-prompt after this window
  // rather than locking the user out forever.
  static const Duration _highRatedCooldown = Duration(days: 180);

  static const String _keyLastPromptAt = 'review_prompt_last_prompt_at_ms';
  static const String _keyLastPromptVersion = 'review_prompt_last_version';
  static const String _keyHasRatedHigh = 'review_prompt_has_rated_high';
  static const String _keyLastRating = 'review_prompt_last_rating';
  static const String _keySessionCount = 'review_prompt_session_count';

  /// Number of app opens required before showing the session-based prompt.
  static const int _minSessionCount = 3;

  static bool _promptActive = false;

  final InAppReview _inAppReview = InAppReview.instance;

  AppDatabase get _db => AppDatabase.instance;

  /// Increments the session (app-open) counter.
  /// Call once per app launch from the home screen.
  Future<void> incrementSessionCount() async {
    final current = await _db.getInt(_keySessionCount) ?? 0;
    await _db.setInt(_keySessionCount, current + 1);
  }

  /// Shows the review/feedback flow.
  ///
  /// Flow for HIGH ratings (4-5 stars):
  /// 1. Show rating dialog
  /// 2. Show feature survey dialog (captures what users would pay for)
  /// 3. Trigger native app store review
  /// 4. Mark as rated high (won't prompt again)
  ///
  /// Flow for LOW ratings (1-3 stars):
  /// 1. Show rating dialog
  /// 2. Show feedback dialog (captures complaints/improvement suggestions)
  /// 3. No native review triggered
  ///
  /// [skipSurveyForHighRating] - If true, skips the survey for high raters
  /// and goes directly to native review. Default is false (always show survey).
  Future<void> maybePrompt({
    required BuildContext context,
    required ReviewPromptTrigger trigger,
    bool force = false,
    bool skipSurveyForHighRating = false,
  }) async {
    debugPrint(
      '[Feedback] maybePrompt called - trigger: $trigger, force: $force',
    );
    if (_promptActive) {
      debugPrint('[Feedback] BLOCKED: prompt already active');
      return;
    }
    if (!context.mounted) {
      debugPrint('[Feedback] BLOCKED: context not mounted (1)');
      return;
    }
    if (!force && !await _shouldPrompt(trigger)) {
      debugPrint('[Feedback] BLOCKED: _shouldPrompt returned false');
      return;
    }
    if (!context.mounted) {
      debugPrint('[Feedback] BLOCKED: context not mounted (2)');
      return;
    }

    debugPrint('[Feedback] Showing dialog...');
    _promptActive = true;
    try {
      // Step 1: Show the unified review flow dialog
      final result = await showReviewFlowDialog(
        context,
        skipSurveyForHighRating: skipSurveyForHighRating,
      );

      debugPrint(
        '[Feedback] Dialog result: rating=${result?.rating}, feedback=${result?.feedback}, featureRequest=${result?.featureRequest}',
      );

      await _recordPromptShown();

      if (result == null) {
        debugPrint('[Feedback] BLOCKED: result is null (user cancelled)');
        return;
      }

      await _db.setInt(_keyLastRating, result.rating);

      // Combine feedback and feature request
      final parts = <String>[];
      if (result.feedback != null && result.feedback!.trim().isNotEmpty) {
        parts.add('Feedback: ${result.feedback!.trim()}');
      }
      if (result.featureRequest != null &&
          result.featureRequest!.trim().isNotEmpty) {
        parts.add('Feature Request: ${result.featureRequest!.trim()}');
      }

      final combinedFeedback = parts.join('\n\n');
      debugPrint('[Feedback] combinedFeedback: "$combinedFeedback"');

      // For high ratings, fire the native OS review prompt FIRST — before any
      // network calls. SKStoreReviewController / Play ReviewManager are
      // sensitive to the app being foregrounded and recently interactive, so
      // delaying behind Supabase + Telegram round-trips can cause the OS to
      // skip showing the dialog.
      if (result.rating >= 4) {
        await _requestNativeReview();
        await _db.setBool(_keyHasRatedHigh, true);
      }

      // Submit feedback in the background — don't block the UI thread or the
      // native review prompt on Supabase/Telegram network latency.
      if (combinedFeedback.isNotEmpty) {
        debugPrint('[Feedback] Submitting feedback in background...');
        unawaited(
          _submitFeedback(
            rating: result.rating,
            feedback: combinedFeedback,
            trigger: trigger,
          ),
        );
      } else {
        debugPrint('[Feedback] SKIPPED: combinedFeedback is empty');
      }

      // Skip the in-app thank-you toast when the OS dialog handled the
      // acknowledgment (high raters). Low raters still get the toast as
      // confirmation that their feedback was received.
      if (result.rating < 4 && context.mounted) {
        _showThanksSnackBar(context);
      }
    } finally {
      _promptActive = false;
    }
  }

  Future<void> _recordPromptShown() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.setInt(_keyLastPromptAt, now);

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      await _db.setString(_keyLastPromptVersion, packageInfo.version);
    } catch (_) {
      // Ignore package info failures.
    }
  }

  Future<bool> _shouldPrompt(ReviewPromptTrigger trigger) async {
    if (!_isMobilePlatform) return false;

    // For session-based triggers, require at least N app opens.
    if (trigger == ReviewPromptTrigger.session) {
      final sessionCount = await _db.getInt(_keySessionCount) ?? 0;
      if (sessionCount < _minSessionCount) return false;
    }

    final hasRatedHigh = await _db.getBool(_keyHasRatedHigh) ?? false;
    final activeCooldown = hasRatedHigh ? _highRatedCooldown : _cooldown;

    final lastPromptAtMs = await _db.getInt(_keyLastPromptAt);
    if (lastPromptAtMs != null) {
      final lastPromptAt = DateTime.fromMillisecondsSinceEpoch(lastPromptAtMs);
      if (DateTime.now().difference(lastPromptAt) < activeCooldown) {
        return false;
      }
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final lastPromptVersion = await _db.getString(_keyLastPromptVersion);
      if (lastPromptVersion == packageInfo.version) return false;
    } catch (_) {
      // If version lookup fails, skip version gating.
    }

    return true;
  }

  Future<void> _requestNativeReview() async {
    if (!_isMobilePlatform) {
      debugPrint('[Feedback] Native review SKIPPED: not a mobile platform');
      return;
    }

    try {
      final available = await _inAppReview.isAvailable();
      debugPrint('[Feedback] InAppReview.isAvailable() = $available');
      if (!available) {
        // On iOS this means StoreKit unavailable; on Android it usually means
        // the app wasn't installed via Play Store (e.g. debug `flutter run`
        // build). The native dialog will not appear in either case.
        debugPrint(
          '[Feedback] Native review NOT shown: store API reported unavailable. '
          'On Android this is expected for non-Play installs (debug builds, '
          'sideloads). On iOS this is rare but can happen if StoreKit is off.',
        );
        return;
      }
      debugPrint('[Feedback] Calling InAppReview.requestReview()...');
      await _inAppReview.requestReview();
      debugPrint(
        '[Feedback] requestReview() returned. Note: the OS may still suppress '
        'the dialog (per-app quota, recent prompt, debug build), and there is '
        'no callback indicating whether the dialog was actually displayed.',
      );
    } catch (e, stack) {
      debugPrint('[Feedback] Native review ERROR: $e\n$stack');
    }
  }

  Future<void> _submitFeedback({
    required int rating,
    required String feedback,
    required ReviewPromptTrigger trigger,
  }) async {
    debugPrint(
      '[Feedback] _submitFeedback called - rating: $rating, trigger: $trigger',
    );
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    debugPrint('[Feedback] userId: $userId');
    if (userId == null) {
      debugPrint('[Feedback] BLOCKED: userId is null (not logged in)');
      return;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    debugPrint('[Feedback] Inserting to Supabase...');
    try {
      await supabase.from('app_feedback').insert({
        'user_id': userId,
        'rating': rating,
        'feedback': feedback,
        'source': trigger.name,
        'app_version': packageInfo.version,
        'build_number': packageInfo.buildNumber,
        'platform': Platform.operatingSystem,
      });
      debugPrint('[Feedback] Supabase insert SUCCESS');

      // Send Telegram notification for immediate alert
      debugPrint('[Feedback] Sending Telegram notification...');
      await TelegramNotificationService.instance.sendFeedbackNotification(
        rating: rating,
        feedback: feedback,
        source: trigger.name,
        userId: userId,
        appVersion: '${packageInfo.version} (${packageInfo.buildNumber})',
        platform: Platform.operatingSystem,
      );
      debugPrint('[Feedback] Telegram notification sent');
    } catch (e) {
      debugPrint('[Feedback] ERROR: $e');
    }
  }

  static bool get _isMobilePlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  void _showThanksSnackBar(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'ChessEver grows and improves with your feedback. Thank you!',
          style: AppTypography.textSmMedium.copyWith(color: context.colors.textPrimary),
        ),
        backgroundColor: context.colors.surface.withValues(alpha: 0.95),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
