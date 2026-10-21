import 'dart:async';

import 'package:chessever2/revenue_cat_service/billing_account_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an identity change waits for the pending purchase to finish', () async {
    String? account = 'a';
    final queue = BillingAccountQueue(() => account);
    final purchase = Completer<void>();
    final calls = <String>[];
    final first = queue.run('a', () async {
      calls.add('purchase');
      await purchase.future;
    });
    await pumpEventQueue();
    final login = queue.run('a', () async => calls.add('login'));
    expect(calls, ['purchase']);
    purchase.complete();
    await first;
    await login;
    expect(calls, ['purchase', 'login']);
  });

  test('a late paid result cannot grant access to the next account', () async {
    String? account = 'a';
    final queue = BillingAccountQueue(() => account);
    final paid = Completer<bool>();
    final result = queue.run('a', () => paid.future);
    final rejected = expectLater(result, throwsStateError);
    await pumpEventQueue();
    account = 'b';
    paid.complete(true);
    await rejected;
    expect(await queue.run('b', () async => 'current'), 'current');
  });

  test('a stale queued operation never reaches the store', () async {
    String? account = 'a';
    final queue = BillingAccountQueue(() => account);
    final pending = Completer<void>();
    final first = queue.run('a', () => pending.future);
    final firstRejected = expectLater(first, throwsStateError);
    await pumpEventQueue();
    var enteredStore = false;
    final stale = queue.run('a', () async => enteredStore = true);
    final staleRejected = expectLater(stale, throwsStateError);
    account = 'b';
    pending.complete();
    await firstRejected;
    await staleRejected;
    expect(enteredStore, isFalse);
  });
}
