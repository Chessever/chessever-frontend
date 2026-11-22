// Renders the rewarded-interstitial intro ("Try another ad?") open over a
// busy page of live boards, light and dark, at a phone (393x852), a tablet
// (834x1194) and a small phone with large text (320x568 at 1.5x), 3x, and
// in the flow it really opens in: over the Unlock Premium chooser, whose
// Watch ad is loading. For review:
//
//   flutter test --no-pub test/rewarded_interstitial_intro_preview_test.dart \
//     --dart-define=TRY_ANOTHER_AD_DIR=/tmp/try_another_ad/after
//
// The "render" tests use only entry points that exist before and after the
// redesign (showRewardedInterstitialIntro, showRewardedAccessChoice, the
// labels), so `--plain-name render` renders the "before" set from HEAD.
// Without TRY_ANOTHER_AD_DIR they still run as a smoke test and write
// nothing.
//
// The "check" tests read the pixels: every label clears 4.5:1 on what it is
// drawn on, in both themes, and Watch ad's mark is the chooser's, by its
// ink: as tall, as wide, as far from its label, the pair centred on the
// plate.
import 'dart:async';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/rewarded_access_ui.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/rewarded_interstitial_intro.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'dialogs_harness.dart';
import 'support/premium_popup_harness.dart';

const _outDir = String.fromEnvironment('TRY_ANOTHER_AD_DIR');

const _title = 'Try another ad?';
const _small = Size(320, 568);

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription()
    : super(SubscriptionState(isSubscribed: false, isLoading: false));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The chooser's Watch ad as the app runs it when the first ad fails: a
/// beat of loading, then the intro over the chooser.
class _FailingFirstAd extends RewardedAccessNotifier {
  @override
  Future<bool> unlock(BuildContext context) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!context.mounted) return false;
    await showRewardedInterstitialIntro(context);
    return false;
  }
}

Future<void> _openIntro(WidgetTester tester, BuildContext context) async {
  unawaited(showRewardedInterstitialIntro(context));
  await tester.pump();
  await settleDialogs(tester);
  expect(find.text(_title), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadPremiumPopupFonts();
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
  });

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';
    for (final (device, screen, scale) in [
      ('phone', premiumPopupPhone, 1.0),
      ('tablet', premiumPopupTablet, 1.0),
      ('small_large_text', _small, 1.5),
    ]) {
      testWidgets('render intro, $theme, $device', (tester) async {
        debugDisableShadows = false;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        try {
          muteDialogsPlatform(tester);
          final context = await pumpPremiumPopupHost(
            tester,
            light: light,
            screen: screen,
          );
          await _openIntro(tester, context);
          await premiumPopupShot(tester, _outDir, 'intro_${theme}_$device');
          await tester.pumpWidget(const SizedBox());
        } finally {
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          debugDisableShadows = true;
        }
      });
    }

    testWidgets('render in flow over the chooser, $theme, phone', (
      tester,
    ) async {
      debugDisableShadows = false;
      try {
        muteDialogsPlatform(tester);
        final context = await pumpPremiumPopupHost(
          tester,
          light: light,
          screen: premiumPopupPhone,
          overrides: [
            subscriptionProvider.overrideWith((ref) => _Subscription()),
            rewardedAccessProvider.overrideWith((ref) => _FailingFirstAd()),
          ],
        );
        debugResetRewardedAccessChoice();
        unawaited(
          showRewardedAccessChoice(
            context,
            upgrade: (_) => Completer<bool>().future,
          ),
        );
        await tester.pump();
        await settleDialogs(tester);
        await tester.tap(find.text('Watch ad'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        await settleDialogs(tester);
        expect(find.text(_title), findsOneWidget);
        await premiumPopupShot(tester, _outDir, 'in_flow_${theme}_phone');
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugResetRewardedAccessChoice();
        debugDisableShadows = true;
      }
    });

    testWidgets('check labels clear 4.5:1 on what they sit on, $theme', (
      tester,
    ) async {
      debugDisableShadows = false;
      try {
        muteDialogsPlatform(tester);
        final context = await pumpPremiumPopupHost(
          tester,
          light: light,
          screen: premiumPopupPhone,
        );
        await _openIntro(tester, context);
        final body = tester
            .widget<Text>(
              find.descendant(
                of: find.byType(Dialog),
                matching: find.textContaining('10 minutes of Premium'),
              ),
            )
            .data!;
        final report = <String>[];
        for (final label in [_title, body, 'Watch ad', 'Skip']) {
          final ratio = await premiumPopupLabelContrast(tester, label);
          report.add(
            '${label == body ? 'body' : label} ${ratio.toStringAsFixed(2)}:1',
          );
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$theme $label');
        }
        // ignore: avoid_print
        print('INTRO CONTRAST $theme: ${report.join(' | ')}');
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDisableShadows = true;
      }
    });

    // The play mark on the chooser's Watch ad: 16 pt tall, 14 wide, 9 pt
    // of air from its label's ink, and the pair centred on the plate.
    testWidgets('check Watch ad wears the chooser\'s mark, by ink, $theme', (
      tester,
    ) async {
      debugDisableShadows = false;
      try {
        muteDialogsPlatform(tester);
        final context = await pumpPremiumPopupHost(
          tester,
          light: light,
          screen: premiumPopupPhone,
        );
        await _openIntro(tester, context);
        final ink = await premiumPopupInk(tester, 'Watch ad');
        final gap = ink.label.left - ink.mark.right;
        final group = (ink.mark.left + ink.label.right) / 2;
        // ignore: avoid_print
        print(
          'INTRO INK $theme: Watch ad mark '
          '${ink.mark.width.toStringAsFixed(2)}x'
          '${ink.mark.height.toStringAsFixed(2)} gap '
          '${gap.toStringAsFixed(2)} off-centre '
          '${(group - ink.plate.center.dx).toStringAsFixed(2)} mark dy '
          '${(ink.mark.center.dy - ink.plate.center.dy).toStringAsFixed(2)}',
        );
        expect(ink.mark.height, closeTo(16, 0.5));
        expect(ink.mark.width, closeTo(14, 0.5));
        expect(gap, closeTo(9, 0.7));
        expect(group, closeTo(ink.plate.center.dx, 0.5));
        expect(ink.mark.center.dy, closeTo(ink.plate.center.dy, 0.5));
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
