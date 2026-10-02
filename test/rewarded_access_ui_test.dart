import 'dart:async';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
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
}

void main() {
  Future<void> host(
    WidgetTester tester,
    _Reward reward, {
    bool expired = false,
    void Function(bool)? answer,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionProvider.overrideWith((ref) => _Subscription()),
          rewardedAccessProvider.overrideWith((ref) => reward),
        ],
        child: MaterialApp(
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
                    upgrade: (_) async => true,
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
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    reward.completion!.complete(true);
    await tester.pumpAndSettle();
  });
}
