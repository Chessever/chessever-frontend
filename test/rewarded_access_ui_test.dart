import 'dart:async';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/premium_marks.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/rewarded_access_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription()
    : super(SubscriptionState(isSubscribed: false, isLoading: false));

  /// Premium arrives from elsewhere (a purchase that completes in the
  /// store, a restore on another screen).
  void subscribe() =>
      state = SubscriptionState(isSubscribed: true, isLoading: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Reward extends RewardedAccessNotifier {
  int calls = 0;
  Completer<bool>? completion;
  Object? error;
  BuildContext? context;
  @override
  Future<bool> unlock(BuildContext context) async {
    calls++;
    this.context = context;
    if (error != null) throw error!;
    return completion == null ? true : completion!.future;
  }

  /// An ad was watched but the server has not confirmed the reward yet.
  void markPending() => state = const RewardedAccessState(pending: true);
}

void main() {
  // A test that fails with the popup open would otherwise block every
  // later test's popup.
  setUp(debugResetRewardedAccessChoice);

  late List<MethodCall> platform;

  Future<_Subscription> host(
    WidgetTester tester,
    _Reward reward, {
    bool expired = false,
    void Function(bool)? answer,
    double textScale = 1,
    PremiumUpgrade? upgrade,
    ThemeData? theme,
  }) async {
    platform = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platform.add(call);
        return null;
      },
    );
    final subscription = _Subscription();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionProvider.overrideWith((ref) => subscription),
          rewardedAccessProvider.overrideWith((ref) => reward),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.darkTheme,
          builder: (context, child) {
            // As the app does: its snacks size from the responsive helper.
            ResponsiveHelper.init(context);
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            );
          },
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final result = await showRewardedAccessChoice(
                    context,
                    expired: expired,
                    upgrade: upgrade ?? (_) async => true,
                  );
                  answer?.call(result);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return subscription;
  }

  /// Taps outside the card, on the scrim.
  Future<void> tapScrim(WidgetTester tester) async {
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
  }

  testWidgets('Not now dismisses without unlocking or upgrading', (
    tester,
  ) async {
    final reward = _Reward();
    var upgrades = 0;
    bool? answer;
    await host(
      tester,
      reward,
      answer: (value) => answer = value,
      upgrade: (_) async {
        upgrades++;
        return true;
      },
    );
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(answer, false);
    expect(reward.calls, 0);
    expect(upgrades, 0);
    expect(find.text('Unlock Premium'), findsNothing);
  });

  // The card carries no close X: Not now and the scrim dismiss it, as the
  // other popups are dismissed.
  testWidgets('an outside tap dismisses without unlocking access', (
    tester,
  ) async {
    final reward = _Reward();
    bool? answer;
    await host(tester, reward, answer: (value) => answer = value);
    expect(find.byIcon(Icons.close), findsNothing);
    await tapScrim(tester);
    expect(answer, false);
    expect(reward.calls, 0);
  });

  testWidgets('popup fits a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reward = _Reward();
    await host(tester, reward, textScale: 2);
    final dialog = tester.getRect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(dialog.width, lessThanOrEqualTo(288));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Not now'));
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(reward.calls, 0);
  });

  testWidgets('Watch ad runs the rewarded unlock once and closes with access', (
    tester,
  ) async {
    final reward = _Reward();
    bool? answer;
    await host(tester, reward, answer: (value) => answer = value);
    expect(find.text('Upgrade'), findsOneWidget);
    // The body names both ways in before either button, the duration on
    // the ad's side.
    expect(find.text('Unlimited, or 10 minutes for one ad.'), findsOneWidget);
    await tester.tap(find.text('Watch ad'));
    await tester.pumpAndSettle();
    expect(answer, true);
    expect(reward.calls, 1);
    // The popup's own context runs the ad flow, as before.
    expect(reward.context, isNotNull);
    expect(find.text('Unlock Premium'), findsNothing);
  });

  testWidgets('an ad closed early keeps the chooser open and says why', (
    tester,
  ) async {
    final reward = _Reward()..completion = (Completer<bool>()..complete(false));
    bool? answer;
    await host(tester, reward, answer: (value) => answer = value);
    await tester.tap(find.text('Watch ad'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Complete the ad to unlock 10 minutes of Premium.'),
      findsOneWidget,
    );
    expect(find.text('Unlock Premium'), findsOneWidget);
    expect(answer, isNull);
    expect(reward.calls, 1);
  });

  testWidgets('an unconfirmed reward asks for a confirmation retry', (
    tester,
  ) async {
    final completion = Completer<bool>();
    final reward = _Reward()..completion = completion;
    await host(tester, reward);
    await tester.tap(find.text('Watch ad'));
    await tester.pump();
    reward.markPending();
    completion.complete(false);
    await tester.pump();
    await tester.pump();
    expect(
      find.text(
        'Your reward is still being confirmed. Tap Retry confirmation.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry confirmation'), findsOneWidget);
  });

  for (final pending in [false, true]) {
    testWidgets('an ad that fails says so (pending: $pending)', (tester) async {
      final reward = _Reward()..error = StateError('no fill');
      if (pending) reward.markPending();
      await host(tester, reward);
      await tester.tap(find.text(pending ? 'Retry confirmation' : 'Watch ad'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          pending
              ? 'Could not confirm your reward. Retry without watching another ad.'
              : 'The ad is unavailable. Please try again later.',
        ),
        findsOneWidget,
      );
      expect(find.text('Unlock Premium'), findsOneWidget);
    });
  }

  testWidgets('Upgrade opens the upgrade flow once, from the popup', (
    tester,
  ) async {
    final reward = _Reward();
    final hosts = <BuildContext>[];
    bool? answer;
    await host(
      tester,
      reward,
      answer: (value) => answer = value,
      upgrade: (context) async {
        hosts.add(context);
        return true;
      },
    );
    await tester.tap(find.text('Upgrade'));
    await tester.pumpAndSettle();
    expect(hosts, hasLength(1));
    expect(answer, true);
    expect(reward.calls, 0);
    expect(find.text('Unlock Premium'), findsNothing);
  });

  testWidgets('a checkout that ends without Premium keeps the chooser', (
    tester,
  ) async {
    final reward = _Reward();
    var upgrades = 0;
    bool? answer;
    await host(
      tester,
      reward,
      answer: (value) => answer = value,
      upgrade: (_) async {
        upgrades++;
        return false;
      },
    );
    await tester.tap(find.text('Upgrade'));
    await tester.pumpAndSettle();
    expect(upgrades, 1);
    expect(answer, isNull);
    expect(find.text('Unlock Premium'), findsOneWidget);
    expect(find.text('Upgrade'), findsOneWidget);
  });

  testWidgets('a checkout that throws keeps the chooser and says so', (
    tester,
  ) async {
    final reward = _Reward();
    await host(tester, reward, upgrade: (_) async => throw StateError('store'));
    await tester.tap(find.text('Upgrade'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Could not open Premium checkout. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Unlock Premium'), findsOneWidget);
  });

  // The tap's answer is the mark's burst, not a spinner: a checkout that
  // opens over the popup within the beat never shows one, under it or
  // after.
  testWidgets('a checkout that opens at once never shows a spinner', (
    tester,
  ) async {
    final reward = _Reward();
    bool? answer;
    await host(
      tester,
      reward,
      answer: (value) => answer = value,
      upgrade: (context) async =>
          await showDialog<bool>(
            context: context,
            builder: (_) => const Center(child: Text('Checkout')),
          ) ??
          false,
    );
    await tester.tap(find.text('Upgrade'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Checkout'), findsOneWidget);
    expect(
      find.byType(CircularProgressIndicator, skipOffstage: false),
      findsNothing,
    );
    expect(find.text('Opening…', skipOffstage: false), findsNothing);
    // A checkout that ends without Premium hands back the chooser as it was.
    Navigator.of(tester.element(find.text('Checkout'))).pop(false);
    await tester.pumpAndSettle();
    expect(find.text('Upgrade'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(answer, isNull);
    expect(reward.calls, 0);
  });

  testWidgets('Premium arriving while it is open closes it with access', (
    tester,
  ) async {
    final reward = _Reward();
    bool? answer;
    final subscription = await host(
      tester,
      reward,
      answer: (value) => answer = value,
    );
    subscription.subscribe();
    await tester.pumpAndSettle();
    expect(answer, true);
    expect(reward.calls, 0);
  });

  testWidgets('expiry offers renewal, upgrade and explicit go back', (
    tester,
  ) async {
    final reward = _Reward();
    bool? answer;
    await host(
      tester,
      reward,
      expired: true,
      answer: (value) => answer = value,
    );
    expect(find.text('Your Premium time is up'), findsOneWidget);
    expect(find.text('Watch ad again'), findsOneWidget);
    expect(
      find.text('Unlimited, or 10 more minutes for one ad.'),
      findsOneWidget,
    );
    expect(find.text('Upgrade'), findsOneWidget);
    // Not dismissible from outside: the reader chooses.
    await tapScrim(tester);
    expect(find.text('Your Premium time is up'), findsOneWidget);
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(answer, false);
    expect(reward.calls, 0);
  });

  testWidgets('in-flight ad locks Upgrade, a second ad and every dismissal', (
    tester,
  ) async {
    final reward = _Reward()..completion = Completer<bool>();
    var upgrades = 0;
    bool? answer;
    await host(
      tester,
      reward,
      answer: (value) => answer = value,
      upgrade: (_) async {
        upgrades++;
        return true;
      },
    );
    await tester.tap(find.text('Watch ad'));
    await tester.pump();
    expect(reward.calls, 1);
    // For a beat the plate keeps its mark and label; an ad still loading
    // after it shows a spinner and says so.
    expect(find.text('Watch ad'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Loading ad…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Upgrade'), warnIfMissed: false);
    await tester.tap(find.text('Loading ad…'), warnIfMissed: false);
    await tester.tap(find.text('Not now'), warnIfMissed: false);
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(upgrades, 0);
    expect(reward.calls, 1);
    expect(answer, isNull);
    expect(find.text('Loading ad…'), findsOneWidget);
    reward.completion!.complete(true);
    await tester.pumpAndSettle();
    expect(answer, true);
  });

  testWidgets('in-flight upgrade locks the ad and every dismissal', (
    tester,
  ) async {
    final reward = _Reward();
    final checkout = Completer<bool>();
    bool? answer;
    await host(
      tester,
      reward,
      answer: (value) => answer = value,
      upgrade: (_) => checkout.future,
    );
    await tester.tap(find.text('Upgrade'));
    await tester.pump();
    expect(find.text('Upgrade'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Opening…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Watch ad'), warnIfMissed: false);
    await tester.tap(find.text('Not now'), warnIfMissed: false);
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(reward.calls, 0);
    expect(answer, isNull);
    checkout.complete(true);
    await tester.pumpAndSettle();
    expect(answer, true);
    expect(reward.calls, 0);
  });

  testWidgets('pending reward keeps Upgrade first, retry under it', (
    tester,
  ) async {
    final reward = _Reward()..markPending();
    var upgrades = 0;
    await host(
      tester,
      reward,
      upgrade: (_) async {
        upgrades++;
        return false;
      },
    );
    expect(find.text('Confirming your reward…'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Upgrade')).dy,
      lessThan(tester.getTopLeft(find.text('Retry confirmation')).dy),
    );
    // Retry wears its own turning arrow, never the play mark.
    expect(glyphOf(tester, 'Retry confirmation'), ChoiceGlyph.retry);
    await tester.tap(find.text('Upgrade'));
    await tester.pumpAndSettle();
    expect(upgrades, 1);
    await tester.tap(find.text('Retry confirmation'));
    await tester.pumpAndSettle();
    expect(reward.calls, 1);
  });

  // Trello #1416: Upgrade comes first. Both choices wear a mark from one
  // family: the premium mark on Upgrade, the play mark on Watch ad.
  for (final expired in [false, true]) {
    testWidgets('Upgrade leads with the premium mark (expired: $expired)', (
      tester,
    ) async {
      final reward = _Reward();
      await host(tester, reward, expired: expired);
      final watchLabel = expired ? 'Watch ad again' : 'Watch ad';
      expect(
        tester.getTopLeft(find.text('Upgrade')).dy,
        lessThan(tester.getTopLeft(find.text(watchLabel)).dy),
      );
      expect(glyphOf(tester, 'Upgrade'), ChoiceGlyph.premium);
      expect(glyphOf(tester, watchLabel), ChoiceGlyph.play);
      // The premium mark tops the card.
      expect(find.byType(PremiumMark), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byType(PremiumMark)).dy,
        lessThan(tester.getTopLeft(find.text('Upgrade')).dy),
      );
      await tester.tap(find.text(expired ? 'Go back' : 'Not now'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('choices are 56 pt buttons, Not now a 44 pt one', (tester) async {
    final semantics = tester.ensureSemantics();
    final reward = _Reward();
    await host(tester, reward);
    for (final label in ['Upgrade', 'Watch ad']) {
      expect(
        tester.getSemantics(find.text(label)),
        matchesSemantics(
          label: label,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      expect(plateOf(tester, label).height, greaterThanOrEqualTo(56));
    }
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Not now')).height,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('a tap on a choice answers with a light haptic', (tester) async {
    final reward = _Reward();
    await host(tester, reward, upgrade: (_) async => false);
    await tester.tap(find.text('Upgrade'));
    await tester.pumpAndSettle();
    expect(
      platform.where((call) => call.method == 'HapticFeedback.vibrate'),
      hasLength(1),
    );
  });

  // Centred means centred: the mark and title on the card's centre line,
  // and each choice's mark and label on its plate's. Across, a choice's
  // pair is centred by its ink, which only real type shows: the preview
  // test measures that on the pixels. Here, with the test font, the boxes
  // sit within the lead that answers the label's last letter.
  for (final textScale in [1.0, 1.5]) {
    testWidgets('mark, title and choices sit on their centre lines '
        '(scale $textScale)', (tester) async {
      final reward = _Reward();
      await host(tester, reward, textScale: textScale);
      final card = tester.getRect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(
        tester.getCenter(find.byType(PremiumMark)).dx,
        closeTo(card.center.dx, 0.5),
      );
      expect(
        tester.getCenter(find.text('Unlock Premium')).dx,
        closeTo(card.center.dx, 0.5),
      );
      expect(
        tester.getTopLeft(find.byType(PremiumMark)).dy - card.top,
        closeTo(28, 0.5),
      );
      for (final label in ['Upgrade', 'Watch ad']) {
        final plate = plateOf(tester, label);
        final glyph = tester.getRect(
          find.descendant(
            of: find.ancestor(of: find.text(label), matching: find.byType(Row)),
            matching: find.byType(ChoiceGlyphIcon),
          ),
        );
        final text = tester.getRect(find.text(label));
        expect(
          (glyph.left + text.right) / 2,
          closeTo(plate.center.dx, 0.75),
          reason: '$label group',
        );
        // The mark is drawn to its own ink box: 16 pt tall.
        expect(glyph.height, 16, reason: '$label mark size');
        expect(
          glyph.center.dy,
          closeTo(plate.center.dy, 0.5),
          reason: '$label mark',
        );
        expect(
          text.center.dy,
          closeTo(plate.center.dy, 0.5),
          reason: '$label text',
        );
      }
      await tester.ensureVisible(find.text('Not now'));
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
    });
  }
}

/// The mark a choice wears.
ChoiceGlyph glyphOf(WidgetTester tester, String label) => tester
    .widget<ChoiceGlyphIcon>(
      find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Row)),
        matching: find.byType(ChoiceGlyphIcon),
      ),
    )
    .glyph;

/// The plate a choice's label sits on: its ink well's box.
Rect plateOf(WidgetTester tester, String label) => tester.getRect(
  find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
);
