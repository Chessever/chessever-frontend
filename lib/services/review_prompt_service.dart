import 'dart:io';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/services/telegram_notification_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/review_prompt/review_prompt_dialogs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ReviewPromptTrigger { session, premium, favoriteEvent, favoritePlayer, sidebar }

class ReviewPromptService {
  ReviewPromptService._();

  static final ReviewPromptService instance = ReviewPromptService._();

  static const Duration _sessionGap = Duration(hours: 6);
  static const Duration _minTimeSinceInstall = Duration(days: 2);
  // Cooldown between prompts
  static const Duration _cooldown = Duration(days: 30);
  static const Duration _activityWindow = Duration(days: 45);
  static const int _minSessions = 3;
  static const int _minActiveDays = 7;

  static const String _keyInstallAt = 'review_prompt_install_at_ms';
  static const String _keyLastSessionAt = 'review_prompt_last_session_at_ms';
  static const String _keySessionCount = 'review_prompt_session_count';
  static const String _keyActiveDays = 'review_prompt_active_days';
  static const String _keyLastPromptAt = 'review_prompt_last_prompt_at_ms';
  static const String _keyLastPromptVersion = 'review_prompt_last_version';
  static const String _keyHasRatedHigh = 'review_prompt_has_rated_high';
  static const String _keyLastRating = 'review_prompt_last_rating';

  static bool _promptActive = false;

  final InAppReview _inAppReview = InAppReview.instance;

  SharedPreferences get _prefs => SharedPreferencesService.instance.prefs;

  Future<void> recordSession() async {
    final now = DateTime.now();
    final lastSessionAtMs = _prefs.getInt(_keyLastSessionAt);
    final installAtMs = _prefs.getInt(_keyInstallAt);

    if (installAtMs == null) {
      await _prefs.setInt(_keyInstallAt, now.millisecondsSinceEpoch);
    }

    await _recordActiveDay(now);

    if (lastSessionAtMs == null ||
        now.difference(
              DateTime.fromMillisecondsSinceEpoch(lastSessionAtMs),
            ) >=
            _sessionGap) {
      final currentCount = _prefs.getInt(_keySessionCount) ?? 0;
      await _prefs.setInt(_keySessionCount, currentCount + 1);
    }

    await _prefs.setInt(_keyLastSessionAt, now.millisecondsSinceEpoch);
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
    if (_promptActive) return;
    if (!context.mounted) return;
    if (!force && !await _shouldPrompt(trigger)) return;
    if (!context.mounted) return;

    _promptActive = true;
    try {
      // Step 1: Show the unified review flow dialog
      final result = await showReviewFlowDialog(
        context,
        skipSurveyForHighRating: skipSurveyForHighRating,
      );
      
      if (!context.mounted) return;
      await _recordPromptShown();

      if (result == null) return;

      await _prefs.setInt(_keyLastRating, result.rating);

      // Combine feedback and feature request
      final parts = <String>[];
      if (result.feedback != null && result.feedback!.trim().isNotEmpty) {
        parts.add('Feedback: ${result.feedback!.trim()}');
      }
      if (result.featureRequest != null && result.featureRequest!.trim().isNotEmpty) {
        parts.add('Feature Request: ${result.featureRequest!.trim()}');
      }

      final combinedFeedback = parts.join('\n\n');

      // Submit if there's any text
      if (combinedFeedback.isNotEmpty) {
        await _submitFeedback(
          rating: result.rating,
          feedback: combinedFeedback,
          trigger: trigger,
        );
        if (context.mounted) {
          _showThanksSnackBar(context);
        }
      }

      // If High Rating, trigger native review
      if (result.rating >= 4) {
        await _requestNativeReview();
        await _prefs.setBool(_keyHasRatedHigh, true);
      }
    } finally {
      _promptActive = false;
    }
  }

  Future<void> _recordPromptShown() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setInt(_keyLastPromptAt, now);

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      await _prefs.setString(_keyLastPromptVersion, packageInfo.version);
    } catch (_) {
      // Ignore package info failures.
    }
  }

  Future<bool> _shouldPrompt(ReviewPromptTrigger trigger) async {
    if (!_isMobilePlatform) return false;

    final hasRatedHigh = _prefs.getBool(_keyHasRatedHigh) ?? false;
    if (hasRatedHigh) return false;

    final lastPromptAtMs = _prefs.getInt(_keyLastPromptAt);
    if (lastPromptAtMs != null) {
      final lastPromptAt = DateTime.fromMillisecondsSinceEpoch(lastPromptAtMs);
      if (DateTime.now().difference(lastPromptAt) < _cooldown) return false;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final lastPromptVersion = _prefs.getString(_keyLastPromptVersion);
      if (lastPromptVersion == packageInfo.version) return false;
    } catch (_) {
      // If version lookup fails, skip version gating.
    }

    if (trigger == ReviewPromptTrigger.premium) {
      return true;
    }

    final installAtMs = _prefs.getInt(_keyInstallAt);
    if (installAtMs == null) return false;

    final installAt = DateTime.fromMillisecondsSinceEpoch(installAtMs);
    if (DateTime.now().difference(installAt) < _minTimeSinceInstall) {
      return false;
    }

    final sessions = _prefs.getInt(_keySessionCount) ?? 0;
    if (sessions < _minSessions) return false;

    if (trigger != ReviewPromptTrigger.premium) {
      final activeDays = _getActiveDaysCount(DateTime.now());
      if (activeDays < _minActiveDays) return false;
    }

    return true;
  }

  Future<void> _recordActiveDay(DateTime now) async {
    final todayKey = _dayKey(now);
    final stored = _prefs.getStringList(_keyActiveDays) ?? [];
    final days = stored.map(int.parse).toSet();

    days.add(todayKey);

    final cutoff = _dayKey(now.subtract(_activityWindow));
    days.removeWhere((day) => day < cutoff);

    await _prefs.setStringList(
      _keyActiveDays,
      days.map((day) => day.toString()).toList(),
    );
  }

  int _getActiveDaysCount(DateTime now) {
    final stored = _prefs.getStringList(_keyActiveDays) ?? [];
    if (stored.isEmpty) return 0;

    final cutoff = _dayKey(now.subtract(_activityWindow));
    final days = stored.map(int.parse).where((day) => day >= cutoff).toSet();
    return days.length;
  }

  int _dayKey(DateTime date) {
    final utc = date.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day)
        .millisecondsSinceEpoch;
  }

  Future<void> _requestNativeReview() async {
    if (!_isMobilePlatform) return;

    try {
      final available = await _inAppReview.isAvailable();
      if (available) {
        await _inAppReview.requestReview();
      }
    } catch (_) {
      // Ignore review request errors silently.
    }
  }

  Future<void> _submitFeedback({
    required int rating,
    required String feedback,
    required ReviewPromptTrigger trigger,
  }) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final packageInfo = await PackageInfo.fromPlatform();
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

      // Send Telegram notification for immediate alert
      await TelegramNotificationService.instance.sendFeedbackNotification(
        rating: rating,
        feedback: feedback,
        source: trigger.name,
        userId: userId,
        appVersion: '${packageInfo.version} (${packageInfo.buildNumber})',
        platform: Platform.operatingSystem,
      );
    } catch (_) {
      // Ignore feedback submission errors.
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
          style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
        ),
        backgroundColor: kBlack2Color.withValues(alpha: 0.95),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
