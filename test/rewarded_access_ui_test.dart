import 'dart:async';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_theme.dart' show kPrimaryColor;
import 'package:chessever2/widgets/paywall/rewarded_premium/rewarded_access_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription()
    : super(SubscriptionState(isSubscribed: false, isLoading: false));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Reward extends RewardedAccessNotifier {
  int calls = 0;
  Completer<bool>? completion;
  @override
  Future<bool> unlock(BuildContext context) async {
    calls++;
    return completion == null ? true : completion!.future;
  }

  /// An ad was watched but the server has not confirmed the reward yet.
  void markPending() => state = const RewardedAccessState(pending: true);
}

void main() {
  // A test that fails with the popup open would otherwise block every
  // later test's popup.
  setUp(debugResetRewardedAccessChoice);

  Future<void> host(
    WidgetTester tester,
    _Reward reward, {
    bool expired = false,
    void Function(bool)? answer,
    double textScale = 1,
    PremiumUpgrade? upgrade,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionProvider.overrideWith((ref) => _Subscription()),
          rewardedAccessProvider.overrideWith((ref) => reward),
        ],
        child: MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
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
  }

  for (final dismiss in ['Close', 'Not now']) {
    testWidgets('$dismiss dismisses without unlocking access', (tester) async {
      final reward = _Reward();
      bool? answer;
      await host(tester, reward, answer: (value) => answer = value);
      await tester.tap(
        dismiss == 'Close' ? find.byTooltip(dismiss) : find.text(dismiss),
      );
      await tester.pumpAndSettle();
      expect(answer, false);
      expect(reward.calls, 0);
    });
  }

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

  testWidgets('completed reward closes chooser once with access', (
    tester,
  ) async {
    final reward = _Reward();
    bool? answer;
    await host(tester, reward, answer: (value) => answer = value);
    expect(find.text('Upgrade'), findsOneWidget);
    // The body names both ways in before either button.
    expect(
      find.text(
        'Upgrade for unlimited access, or watch a short ad for 10 minutes of '
        'Premium.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Watch ad'));
    await tester.pumpAndSettle();
    expect(answer, true);
    expect(reward.calls, 1);
    expect(find.text('Unlock Premium'), findsNothing);
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
    expect(find.text('Watch ad again'), findsOneWidget);
    expect(
      find.text(
        'Watch another ad for 10 more minutes, or upgrade for unlimited '
        'access.',
      ),
      findsOneWidget,
    );
    expect(find.text('Upgrade'), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.text('Your Premium access has ended'), findsOneWidget);
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(answer, false);
    expect(reward.calls, 0);
  });
  testWidgets('in-flight ad disables additional presentation and upgrade', (
    tester,
  ) async {
    final reward = _Reward()..completion = Completer<bool>();
    await host(tester, reward);
    await tester.tap(find.text('Watch ad'));
    await tester.pump();
    expect(reward.calls, 1);
    expect(find.text('Loading ad…'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    expect(tester.widget<FilledButton>(upgradeButton()).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(watchButton()).onPressed, isNull);
    reward.completion!.complete(true);
    await tester.pumpAndSettle();
  });

  // Trello #1416: Upgrade comes first and is the blue action; Watch ad is the
  // outlined alternative under it.
  for (final expired in [false, true]) {
    testWidgets(
      'Upgrade leads in brand blue above Watch ad (expired: $expired)',
      (tester) async {
        final reward = _Reward();
        await host(tester, reward, expired: expired);
        final watchLabel = expired ? 'Watch ad again' : 'Watch ad';
        expect(
          tester.getTopLeft(find.text('Upgrade')).dy,
          lessThan(tester.getTopLeft(find.text(watchLabel)).dy),
        );
        final upgrade = tester.widget<FilledButton>(upgradeButton());
        expect(
          upgrade.style!.backgroundColor!.resolve(const <WidgetState>{}),
          kPrimaryColor,
        );
        expect(
          find.ancestor(
            of: find.text(watchLabel),
            matching: find.byType(OutlinedButton),
          ),
          findsOneWidget,
        );
        expect(
          find.ancestor(
            of: find.text(watchLabel),
            matching: find.byType(FilledButton),
          ),
          findsNothing,
        );
        // Blue belongs to Upgrade alone: Watch ad's ink and border are not.
        final watch = tester.widget<OutlinedButton>(watchButton()).style!;
        expect(
          watch.foregroundColor!.resolve(const <WidgetState>{}),
          isNot(kPrimaryColor),
        );
        expect(
          watch.side!.resolve(const <WidgetState>{})!.color,
          isNot(kPrimaryColor),
        );
        await tester.tap(find.text(expired ? 'Go back' : 'Not now'));
        await tester.pumpAndSettle();
      },
    );
  }

  // kMaxAppTextScale is 1.5. shrinkWrap is the desktop tap-target default,
  // which would shrink the close button to 44 px without the padded pin.
  for (final (textScale, tapTarget) in [
    (1.0, MaterialTapTargetSize.padded),
    (1.5, MaterialTapTargetSize.padded),
    (1.0, MaterialTapTargetSize.shrinkWrap),
  ]) {
    testWidgets('close button centres on the title line '
        '(scale $textScale, ${tapTarget.name})', (tester) async {
      final reward = _Reward();
      await host(
        tester,
        reward,
        textScale: textScale,
        theme: ThemeData(materialTapTargetSize: tapTarget),
      );
      final title = tester.getRect(find.text('Unlock Premium'));
      final close = tester.getCenter(find.byIcon(Icons.close));
      final firstLine = title.top + 24 * textScale * 1.25 / 2;
      expect(close.dy, closeTo(firstLine, 0.5));
      // The title keeps the popup's 20 px top padding, as it does in the
      // expired popup that has no close button.
      expect(title.top - cardTop(tester), closeTo(20, 0.5));
      await tester.ensureVisible(find.text('Not now'));
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('expired title sits on the same 20 px top padding', (
    tester,
  ) async {
    final reward = _Reward();
    await host(tester, reward, expired: true);
    final title = tester.getRect(find.text('Your Premium access has ended'));
    expect(title.top - cardTop(tester), closeTo(20, 0.5));
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
  });

  testWidgets('pending reward keeps Upgrade first, retry in the outline', (
    tester,
  ) async {
    final reward = _Reward()..markPending();
    await host(tester, reward);
    expect(find.text('Confirming your reward…'), findsOneWidget);
    expect(tester.widget<FilledButton>(upgradeButton()).onPressed, isNotNull);
    expect(
      find.ancestor(
        of: find.text('Retry confirmation'),
        matching: find.byType(OutlinedButton),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('Upgrade')).dy,
      lessThan(tester.getTopLeft(find.text('Retry confirmation')).dy),
    );
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
  });

  testWidgets('in-flight upgrade stays blue and blocks the ad', (tester) async {
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
    expect(find.text('Opening…'), findsOneWidget);
    final upgrade = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Opening…'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(upgrade.onPressed, isNull);
    expect(
      upgrade.style!.backgroundColor!.resolve(const {WidgetState.disabled}),
      kPrimaryColor,
    );
    expect(tester.widget<OutlinedButton>(watchButton()).onPressed, isNull);
    checkout.complete(true);
    await tester.pumpAndSettle();
    expect(answer, true);
    expect(reward.calls, 0);
  });
}

Finder upgradeButton() => find.ancestor(
  of: find.text('Upgrade'),
  matching: find.byType(FilledButton),
);

/// The popup's only outlined button; its label changes while the ad runs.
Finder watchButton() => find.descendant(
  of: find.byType(Dialog),
  matching: find.byType(OutlinedButton),
);

/// Top edge of the popup's card (its scroll view fills the card).
double cardTop(WidgetTester tester) => tester
    .getRect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SingleChildScrollView),
      ),
    )
    .top;
