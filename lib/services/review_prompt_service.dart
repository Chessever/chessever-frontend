import 'dart:io';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/widgets/review_prompt/review_prompt_dialogs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ReviewPromptTrigger { session, premium, favoriteEvent, sidebar }

class ReviewPromptService {
  ReviewPromptService._();

  static final ReviewPromptService instance = ReviewPromptService._();

  static const Duration _sessionGap = Duration(hours: 6);
  static const Duration _minTimeSinceInstall = Duration(days: 2);
  static const Duration _cooldown = Duration(days: 45);
  static const int _minSessions = 3;

  static const String _keyInstallAt = 'review_prompt_install_at_ms';
  static const String _keyLastSessionAt = 'review_prompt_last_session_at_ms';
  static const String _keySessionCount = 'review_prompt_session_count';
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

  Future<void> maybePrompt({
    required BuildContext context,
    required ReviewPromptTrigger trigger,
    bool force = false,
  }) async {
    if (_promptActive) return;
    if (!context.mounted) return;
    if (!force && !await _shouldPrompt(trigger)) return;

    _promptActive = true;
    try {
      final rating = await showAppRatingDialog(context);
      if (!context.mounted) return;
      await _recordPromptShown();

      if (rating == null) return;

      await _prefs.setInt(_keyLastRating, rating);

      if (rating >= 4) {
        await _requestNativeReview();
        await _prefs.setBool(_keyHasRatedHigh, true);
        return;
      }

      final feedback = await showAppFeedbackDialog(context, rating: rating);
      if (!context.mounted) return;
      if (feedback == null || feedback.trim().isEmpty) return;

      await _submitFeedback(
        rating: rating,
        feedback: feedback.trim(),
        trigger: trigger,
      );
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

    return true;
  }

  Future<void> _requestNativeReview() async {
    if (!_isMobilePlatform) return;

    try {
      final available = await _inAppReview.isAvailable();
      if (available) {
        await _inAppReview.requestReview();
      } else if (Platform.isAndroid) {
        await _inAppReview.openStoreListing();
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
    } catch (_) {
      // Ignore feedback submission errors.
    }
  }

  static bool get _isMobilePlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }
}
