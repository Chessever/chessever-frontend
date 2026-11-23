// Renders the Premium chooser (Upgrade / Watch ad / Not now) open over a
// busy page of live boards, light and dark, at a phone (393x852) and a
// tablet (834x1194) view, 3x, for review:
//
//   flutter test --no-pub test/rewarded_access_popup_preview_test.dart \
//     --dart-define=PREMIUM_POPUP_DIR=/tmp/premium_popup/after
//
// Only public entry points that exist before and after the redesign are
// used (showRewardedAccessChoice, the button labels), so the same file
// renders the "before" set from HEAD. Without PREMIUM_POPUP_DIR the scenes
// still run as a smoke test and write nothing.
//
// It also checks every button label against the pixels it is drawn on: at
// least 4.5:1, in both themes, at rest and while an action runs; and, by
// the ink on screen (not the widget boxes), that both choices' marks are
// one size, one gap from their labels and centred with them on the plate,
// and that Upgrade's mark visibly closes under a held finger and bursts
// apart as the tap lands. The stage and the pixel readings are shared with
// the intro's preview (test/support/premium_popup_harness.dart).
import 'dart:async';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/rewarded_access_ui.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'dialogs_harness.dart';
import 'support/premium_popup_harness.dart';

const _outDir = String.fromEnvironment('PREMIUM_POPUP_DIR');

const _phone = premiumPopupPhone;
const _tablet = premiumPopupTablet;

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription()
    : super(SubscriptionState(isSubscribed: false, isLoading: false));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Reward extends RewardedAccessNotifier {
  _Reward({bool pending = false}) {
    // An ad was watched; the server has not confirmed the reward yet.
    if (pending) state = const RewardedAccessState(pending: true);
  }
  final completion = Completer<bool>();

  @override
  Future<bool> unlock(BuildContext context) => completion.future;
}

/// Pumps the busy page in the app's theme at [screen] and returns the
/// context the popup opens from.
Future<BuildContext> _host(
  WidgetTester tester, {
  required bool light,
  required Size screen,
  required _Reward reward,
}) => pumpPremiumPopupHost(
  tester,
  light: light,
  screen: screen,
  overrides: [
    subscriptionProvider.overrideWith((ref) => _Subscription()),
    rewardedAccessProvider.overrideWith((ref) => reward),
  ],
);

Future<void> _open(
  WidgetTester tester,
  BuildContext context, {
  bool expired = false,
  Completer<bool>? checkout,
}) async {
  debugResetRewardedAccessChoice();
  unawaited(
    showRewardedAccessChoice(
      context,
      expired: expired,
      upgrade: (_) => (checkout ?? Completer<bool>()).future,
    ),
  );
  await tester.pump();
  await settleDialogs(tester);
}

Future<void> _shot(WidgetTester tester, String name) =>
    premiumPopupShot(tester, _outDir, name);

const _labelContrast = premiumPopupLabelContrast;
const _ink = premiumPopupInk;

/// A running choice keeps its mark and label for a beat before it shows a
/// spinner; this waits past it, then settles. The tap's own frame comes
/// first: the beat starts in it.
Future<void> _pastBeat(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await settleDialogs(tester);
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
    for (final (device, screen) in [('phone', _phone), ('tablet', _tablet)]) {
      testWidgets('choice, $theme, $device', (tester) async {
        debugDisableShadows = false;
        try {
          muteDialogsPlatform(tester);
          final reward = _Reward();
          final context = await _host(
            tester,
            light: light,
            screen: screen,
            reward: reward,
          );
          await _open(tester, context);
          expect(find.text('Upgrade'), findsOneWidget);
          await _shot(tester, 'choice_${theme}_$device');
          await tester.pumpWidget(const SizedBox());
        } finally {
          debugDisableShadows = true;
        }
      });
    }

    for (final state in ['expired', 'pending', 'loading_ad', 'opening']) {
      testWidgets('$state, $theme, phone', (tester) async {
        debugDisableShadows = false;
        try {
          muteDialogsPlatform(tester);
          final reward = _Reward(pending: state == 'pending');
          final checkout = Completer<bool>();
          final context = await _host(
            tester,
            light: light,
            screen: _phone,
            reward: reward,
          );
          await _open(
            tester,
            context,
            expired: state == 'expired',
            checkout: checkout,
          );
          if (state == 'loading_ad') {
            await tester.tap(find.text('Watch ad'));
            await _pastBeat(tester);
          } else if (state == 'opening') {
            await tester.tap(find.text('Upgrade'));
            await _pastBeat(tester);
          }
          if (state == 'loading_ad' || state == 'opening') {
            // The spinner's arc grows and shrinks as it turns: caught where
            // it is long, so the render shows a spinner, not a speck.
            await tester.pump(const Duration(milliseconds: 500));
          }
          if (state == 'loading_ad') {
            expect(find.text('Loading ad…'), findsOneWidget);
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
          } else if (state == 'opening') {
            expect(find.text('Opening…'), findsOneWidget);
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
          }
          await _shot(tester, '${state}_${theme}_phone');
          await tester.pumpWidget(const SizedBox());
        } finally {
          debugDisableShadows = true;
        }
      });
    }

    // The motion, caught in the act: three frames into the open (the mark's
    // corner squares still closing in round the king); Upgrade held under
    // a finger (the plate given, its mark's squares drawn in), measured
    // against the mark at rest; and the burst as that tap lands (the
    // squares a point past rest, ten frames after the finger lifts).
    for (final moment in ['assembling', 'upgrade_held']) {
      testWidgets('$moment, $theme, phone', (tester) async {
        debugDisableShadows = false;
        try {
          muteDialogsPlatform(tester);
          final reward = _Reward();
          final context = await _host(
            tester,
            light: light,
            screen: _phone,
            reward: reward,
          );
          debugResetRewardedAccessChoice();
          unawaited(
            showRewardedAccessChoice(
              context,
              upgrade: (_) => Completer<bool>().future,
            ),
          );
          await tester.pump();
          if (moment == 'assembling') {
            for (var i = 0; i < 3; i++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            await _shot(tester, '${moment}_${theme}_phone');
          } else {
            await settleDialogs(tester);
            final atRest = await _ink(tester, 'Upgrade');
            final rest = atRest.mark;
            // Where the mark's centre belongs on a plate pressed to its
            // size now (the press scales the plate about its centre).
            double centred(Rect plate) =>
                plate.center.dx +
                (rest.center.dx - atRest.plate.center.dx) *
                    plate.width /
                    atRest.plate.width;
            final finger = await tester.startGesture(
              tester.getCenter(find.text('Upgrade')),
            );
            // The press spring takes some eight frames to reach full.
            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            final heldInk = await _ink(tester, 'Upgrade');
            final held = heldInk.mark;
            await _shot(tester, '${moment}_${theme}_phone');
            await finger.up();
            await tester.pump();
            var burst = heldInk;
            for (var i = 0; i < 14; i++) {
              await tester.pump(const Duration(milliseconds: 16));
              final ink = await _ink(tester, 'Upgrade');
              if (ink.mark.width > burst.mark.width) {
                burst = ink;
                await _shot(tester, 'upgrade_burst_${theme}_phone');
              }
            }
            // ignore: avoid_print
            print(
              'UPGRADE MARK $theme: rest ${rest.width.toStringAsFixed(2)} '
              'held ${held.width.toStringAsFixed(2)} '
              'burst ${burst.mark.width.toStringAsFixed(2)} pt wide',
            );
            // Squeezed 2.4 pt a side, in a plate pressed to 97%.
            expect(held.width, lessThan(rest.width - 4), reason: 'held');
            expect(held.center.dx, closeTo(centred(heldInk.plate), 0.5));
            // Then out past rest: a point a side.
            expect(
              burst.mark.width,
              greaterThan(rest.width + 1.6),
              reason: 'burst',
            );
            expect(burst.mark.center.dx, closeTo(centred(burst.plate), 0.5));
            // Still the mark, not a spinner: it holds for a beat.
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(find.text('Upgrade'), findsOneWidget);
            await _pastBeat(tester);
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
            expect(find.text('Opening…'), findsOneWidget);
          }
          await tester.pumpWidget(const SizedBox());
        } finally {
          debugDisableShadows = true;
        }
      });
    }

    // The two marks match by what is drawn: both 16 pt tall (the mark
    // 16 wide, the play triangle 14), each 9 pt of air from its label's
    // ink, and each pair of mark and label centred on its plate.
    testWidgets('marks match and centre by ink, $theme', (tester) async {
      debugDisableShadows = false;
      try {
        muteDialogsPlatform(tester);
        final context = await _host(
          tester,
          light: light,
          screen: _phone,
          reward: _Reward(),
        );
        await _open(tester, context);
        final report = <String>[];
        final gaps = <double>[];
        for (final (label, width) in [('Upgrade', 16.0), ('Watch ad', 14.0)]) {
          final ink = await _ink(tester, label);
          final gap = ink.label.left - ink.mark.right;
          final group = (ink.mark.left + ink.label.right) / 2;
          gaps.add(gap);
          report.add(
            '$label mark ${ink.mark.width.toStringAsFixed(2)}x'
            '${ink.mark.height.toStringAsFixed(2)} gap '
            '${gap.toStringAsFixed(2)} off-centre '
            '${(group - ink.plate.center.dx).toStringAsFixed(2)} '
            'mark dy ${(ink.mark.center.dy - ink.plate.center.dy).toStringAsFixed(2)}',
          );
          expect(ink.mark.height, closeTo(16, 0.5), reason: '$label height');
          expect(ink.mark.width, closeTo(width, 0.5), reason: '$label width');
          expect(gap, closeTo(9, 0.7), reason: '$label gap');
          expect(
            group,
            closeTo(ink.plate.center.dx, 0.5),
            reason: '$label centring',
          );
          expect(
            ink.mark.center.dy,
            closeTo(ink.plate.center.dy, 0.5),
            reason: '$label mark height',
          );
        }
        expect(gaps.first, closeTo(gaps.last, 0.5), reason: 'equal gaps');
        // ignore: avoid_print
        print('INK $theme: ${report.join(' | ')}');
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDisableShadows = true;
      }
    });

    testWidgets('button labels clear 4.5:1 on what they sit on, $theme', (
      tester,
    ) async {
      debugDisableShadows = false;
      try {
        muteDialogsPlatform(tester);
        final reward = _Reward();
        final checkout = Completer<bool>();
        final context = await _host(
          tester,
          light: light,
          screen: _phone,
          reward: reward,
        );
        await _open(tester, context, checkout: checkout);
        final report = <String>[];
        for (final label in ['Upgrade', 'Watch ad', 'Not now']) {
          final ratio = await _labelContrast(tester, label);
          report.add('$label ${ratio.toStringAsFixed(2)}:1');
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$theme $label');
        }
        // While checkout opens, Upgrade keeps its full strength.
        await tester.tap(find.text('Upgrade'));
        await _pastBeat(tester);
        final opening = await _labelContrast(tester, 'Opening…');
        report.add('Opening… ${opening.toStringAsFixed(2)}:1');
        expect(opening, greaterThanOrEqualTo(4.5), reason: '$theme Opening…');
        // ignore: avoid_print
        print('LABEL CONTRAST $theme: ${report.join(' | ')}');
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
