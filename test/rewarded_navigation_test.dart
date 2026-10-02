import 'package:chessever2/widgets/paywall/rewarded_premium/rewarded_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('going back preserves a suspended route and guards a later return', () {
    final observer = RewardedNavigationObserver();
    final premium = MaterialPageRoute<void>(builder: (_) => const SizedBox());
    final home = MaterialPageRoute<void>(builder: (_) => const SizedBox());
    observer.didPush(premium, null);
    observer.suspendCurrent();
    expect(observer.returningToSuspended, true);
    observer.didPush(home, premium);
    expect(observer.returningToSuspended, false);
    observer.didPop(home, premium);
    expect(observer.returningToSuspended, true);
    observer.didPop(premium, null);
    expect(observer.returningToSuspended, false);
  });
}
