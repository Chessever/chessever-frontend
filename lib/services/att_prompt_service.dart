import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:chessever2/e2e/e2e_config.dart';
import 'package:chessever2/services/appsflyer_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Centralised gate for Apple's App Tracking Transparency prompt.
///
/// Why this exists: Apple review (Guideline 2.1) requires the system ATT
/// dialog to appear before any data is collected that could be used to track
/// the user. Previously the prompt was only reachable after completing the
/// onboarding flow, and even then a "Not now" button on the pre-prompt let
/// callers skip Apple's system dialog entirely. Reviewers who signed in
/// directly from the welcome step, or who dismissed the pre-prompt, never saw
/// the system dialog and the build was rejected.
///
/// Contract: [ensurePrompted] is safe to call from any post-launch entry
/// point. On the first call where the user's ATT status is `notDetermined`,
/// it shows a short explainer sheet and then unconditionally triggers Apple's
/// system dialog. The explainer cannot suppress the system dialog — it is
/// purely informational. Subsequent calls within the same app session are
/// no-ops.
class AttPromptService {
  AttPromptService._();
  static final AttPromptService instance = AttPromptService._();

  bool _inFlight = false;
  bool _done = false;

  /// Ensure Apple's ATT system dialog has been shown exactly once per app
  /// launch. Always fires `startSdkIfNotYetStarted` afterwards so AppsFlyer's
  /// install event carries the correct ATT/IDFA state.
  Future<void> ensurePrompted(
    BuildContext context, {
    bool showExplainer = true,
  }) async {
    if (!Platform.isIOS) return;
    if (E2eConfig.suppressInterruptivePrompts) return;
    if (_done || _inFlight) return;
    _inFlight = true;
    try {
      final current =
          await AppTrackingTransparency.trackingAuthorizationStatus;
      if (current != TrackingStatus.notDetermined) {
        _done = true;
        return;
      }

      if (showExplainer && context.mounted) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: 0.6),
          builder: (_) => const _AttExplainerSheet(),
        );
      }

      // Always trigger Apple's system dialog after the explainer dismisses,
      // regardless of how the sheet was closed. Apple's reviewer needs to
      // actually see this dialog; gating it behind a pre-prompt button is
      // what got us rejected.
      await AppsflyerService.instance.requestAtt();
      _done = true;
    } catch (e) {
      if (kDebugMode) debugPrint('AttPromptService: $e');
    } finally {
      _inFlight = false;
      AppsflyerService.instance.startSdkIfNotYetStarted();
    }
  }
}

class _AttExplainerSheet extends StatelessWidget {
  const _AttExplainerSheet();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: kPrimaryColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: kPrimaryColor,
              size: 28,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Help us know what\'s working',
            style: AppTypography.textLgMedium.copyWith(
              color: context.colors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'On the next screen, iOS will ask if ChessEver can track activity '
            'across other apps and websites. We use this for one thing only: '
            'to credit the creator or marketing campaign that brought you '
            'here, so we know what\'s working. We don\'t sell your data and '
            'don\'t use it for anything else. You can change this any time in '
            'iOS Settings.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.78),
              height: 1.5,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52.h,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: kBlackColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: AppTypography.textMdMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}
