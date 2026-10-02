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
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionProvider.overrideWith((ref) => _Subscription()),
          rewardedAccessProvider.overrideWith((ref) => reward),
        ],
        child: MaterialApp(
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

  testWidgets('completed reward closes chooser once with access', (
    tester,
  ) async {
    final reward = _Reward();
    bool? answer;
    await host(tester, reward, answer: (value) => answer = value);
    expect(find.text('Upgrade to Premium'), findsOneWidget);
    await tester.tap(find.text('Watch ad — unlock Premium for 10 minutes'));
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
    expect(find.text('Upgrade to Premium'), findsOneWidget);
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
    await tester.tap(find.text('Watch ad — unlock Premium for 10 minutes'));
    await tester.pump();
    expect(reward.calls, 1);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    reward.completion!.complete(true);
    await tester.pumpAndSettle();
  });
}
