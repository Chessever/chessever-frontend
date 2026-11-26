import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:chessever2/e2e/e2e_config.dart';
import 'package:chessever2/services/appsflyer_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/smooth_bottom_sheet.dart';
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
/// point. The onboarding welcome step calls it first, so a fresh install sees
/// the explainer and Apple's dialog on its first screen. On the first call
/// where the user's ATT status is `notDetermined`, it shows a short explainer
/// sheet and then unconditionally triggers Apple's system dialog. The
/// explainer cannot suppress the system dialog — it is purely informational.
///
/// AppsFlyer (the only tracking SDK) starts only once the question is
/// settled. iOS silently ignores a request made while the app is not active,
/// leaving the status `notDetermined`; then the request is repeated the next
/// time the app comes to the foreground, and after [_maxAttempts] the
/// question counts as settled so the install is still reported (without
/// IDFA, as for a user who declined).
class AttPromptService {
  AttPromptService._();
  static final AttPromptService instance = AttPromptService._();

  static const int _maxAttempts = 3;

  bool _inFlight = false;
  bool _done = false;
  int _attempts = 0;
  AppLifecycleListener? _resumeRetry;

  Future<void> ensurePrompted(
    BuildContext context, {
    bool showExplainer = true,
  }) async {
    if (!Platform.isIOS) return;
    if (E2eConfig.suppressInterruptivePrompts) return;
    if (_done || _inFlight) return;
    _inFlight = true;
    try {
      final current = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (current != TrackingStatus.notDetermined) {
        _settle();
        return;
      }

      if (showExplainer && context.mounted) {
        await showAttExplainerSheet(context);
      }

      // Always trigger Apple's system dialog after the explainer dismisses,
      // regardless of how the sheet was closed. Apple's reviewer needs to
      // actually see this dialog; gating it behind a pre-prompt button is
      // what got us rejected.
      await _askSystem();
    } catch (e) {
      if (kDebugMode) debugPrint('AttPromptService: $e');
      _settle();
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _askSystem() async {
    await _untilAppActive();
    final status = await AppsflyerService.instance.requestAtt();
    _attempts++;
    if (status != TrackingStatus.notDetermined || _attempts >= _maxAttempts) {
      _settle();
      return;
    }
    if (kDebugMode) {
      debugPrint('AttPromptService: request ignored, retrying on resume');
    }
    _resumeRetry ??= AppLifecycleListener(
      onResume: () {
        _resumeRetry?.dispose();
        _resumeRetry = null;
        unawaited(_retry());
      },
    );
  }

  Future<void> _retry() async {
    if (_done || _inFlight) return;
    _inFlight = true;
    try {
      await _askSystem();
    } catch (e) {
      if (kDebugMode) debugPrint('AttPromptService: $e');
      _settle();
    } finally {
      _inFlight = false;
    }
  }

  /// Apple drops the request unless the app is active.
  Future<void> _untilAppActive() async {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) return;
    final active = Completer<void>();
    final listener = AppLifecycleListener(
      onResume: () {
        if (!active.isCompleted) active.complete();
      },
    );
    try {
      await active.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {},
      );
    } finally {
      listener.dispose();
    }
  }

  /// The question is answered (or can no longer be asked): mark it done and
  /// let AppsFlyer report the install with the resulting ATT/IDFA state.
  void _settle() {
    _done = true;
    AppsflyerService.instance.markAttSettled();
    AppsflyerService.instance.startSdkIfNotYetStarted();
  }
}

/// The explainer [AttPromptService.ensurePrompted] shows before Apple's
/// dialog: a glass sheet over the glass scrim.
@visibleForTesting
Future<void> showAttExplainerSheet(BuildContext context) =>
    showGlassModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AttExplainerSheet(),
    );

class _AttExplainerSheet extends StatelessWidget {
  const _AttExplainerSheet();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    // Glass toned to the surface it used to be painted on. Most of the
    // screen tall: solid, the glass's look without a live blur under it
    // (the frost rule, PopupGlassStyle.frostMaxScreenShare).
    return GlassSheet(
      radius: 28,
      tone: context.colors.surface,
      solid: true,
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
