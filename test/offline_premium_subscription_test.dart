import 'dart:async';

import 'package:chessever2/revenue_cat_service/offline_premium_cache.dart';
import 'package:chessever2/revenue_cat_service/revenue_cat_service.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show CustomerInfo;

import 'support/offline_premium_fakes.dart';

void main() {
  test(
    'lifetime does not renew and expired payment failures are not grace',
    () {
      expect(
        BackendEntitlementSnapshot.fromJson({
          'is_premium': true,
          'interval': 'lifetime',
        }).willRenew,
        isFalse,
      );
      expect(
        BackendEntitlementSnapshot.fromJson({
          'is_premium': false,
          'status': 'past_due',
        }).inBillingGracePeriod,
        isFalse,
      );
    },
  );
  final now = DateTime.now();
  final paid = OfflinePremiumSnapshot(
    verifiedAt: now.subtract(const Duration(days: 2)),
    expiresAt: now.add(const Duration(days: 20)),
    provider: 'revenuecat',
  );

  ({ProviderContainer container, OfflineRevenueCat revenueCat}) launch({
    required MemoryPremiumCache cache,
    Future<BackendEntitlementSnapshot?> Function()? backend,
    String? userId = 'reader',
    String? Function()? currentAccount,
    CustomerInfo? customerInfo,
  }) {
    final revenueCat = OfflineRevenueCat(backend ?? () async => null)
      ..customerInfo = customerInfo;
    final container = ProviderContainer(
      overrides: [
        subscriptionProvider.overrideWith(
          (ref) => SubscriptionNotifier(
            revenueCat: revenueCat,
            offlineCache: cache,
            currentUserId: currentAccount ?? () => userId,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, revenueCat: revenueCat);
  }

  test('a stale SDK callback cannot resurrect an online revocation', () async {
    final cache = MemoryPremiumCache({});
    final app = launch(
      cache: cache,
      customerInfo: premiumCustomerInfo(
        expiresAt: now.add(const Duration(days: 20)),
      ),
      backend: () async => const BackendEntitlementSnapshot(isActive: false),
    );
    app.container.read(subscriptionProvider);
    await pumpEventQueue();
    app.revenueCat.customerInfoListener!(app.revenueCat.customerInfo!);
    await pumpEventQueue();
    expect(app.container.read(premiumAccessProvider), isFalse);
    expect(cache.snapshots, isEmpty);
  });

  test(
    'lifetime replaces an expiring plan without borrowing its expiry',
    () async {
      final expiry = now.add(const Duration(days: 20));
      BackendEntitlementSnapshot answer = BackendEntitlementSnapshot(
        isActive: true,
        provider: 'apple',
        expiresAt: expiry,
      );
      final cache = MemoryPremiumCache({});
      final app = launch(
        cache: cache,
        customerInfo: premiumCustomerInfo(expiresAt: expiry),
        backend: () async => answer,
      );
      app.container.read(subscriptionProvider);
      await pumpEventQueue();
      expect(app.container.read(subscriptionProvider).expirationDate, expiry);
      answer = const BackendEntitlementSnapshot(
        isActive: true,
        provider: 'stripe',
      );
      await app.container
          .read(subscriptionProvider.notifier)
          .refresh(force: false);
      expect(app.container.read(subscriptionProvider).expirationDate, isNull);
      expect(cache.snapshots['reader']?.expiresAt, isNull);
    },
  );

  test(
    'late entitlement responses cannot grant Premium to another account',
    () async {
      String? account = 'a';
      final late = Completer<BackendEntitlementSnapshot?>();
      final cache = MemoryPremiumCache({});
      final app = launch(
        cache: cache,
        currentAccount: () => account,
        backend: () => account == 'a'
            ? late.future
            : Future.value(const BackendEntitlementSnapshot(isActive: false)),
      );
      app.container.read(subscriptionProvider);
      await pumpEventQueue();
      account = 'b';
      await app.container
          .read(subscriptionProvider.notifier)
          .refresh(force: false);
      late.complete(
        const BackendEntitlementSnapshot(isActive: true, provider: 'stripe'),
      );
      await pumpEventQueue();
      expect(app.container.read(premiumAccessProvider), isFalse);
      expect(cache.snapshots.containsKey('b'), isFalse);
    },
  );

  test(
    'restoring an empty app store cannot revoke an existing web purchase',
    () async {
      final app = launch(
        cache: MemoryPremiumCache({}),
        backend: () async => const BackendEntitlementSnapshot(
          isActive: true,
          provider: 'stripe',
        ),
      );
      app.container.read(subscriptionProvider);
      await pumpEventQueue();
      expect(
        await app.container
            .read(subscriptionProvider.notifier)
            .restorePurchases(),
        isTrue,
      );
      expect(app.container.read(subscriptionProvider).provider, 'stripe');
    },
  );

  test('payment recovery clears the old grace warning and timestamp', () async {
    BackendEntitlementSnapshot answer = BackendEntitlementSnapshot(
      isActive: true,
      provider: 'apple',
      inBillingGracePeriod: true,
      billingIssueDetectedAt: now,
    );
    final app = launch(
      cache: MemoryPremiumCache({}),
      backend: () async => answer,
    );
    app.container.read(subscriptionProvider);
    await pumpEventQueue();
    expect(
      app.container.read(subscriptionProvider).inBillingGracePeriod,
      isTrue,
    );
    answer = const BackendEntitlementSnapshot(
      isActive: true,
      provider: 'apple',
    );
    await app.container
        .read(subscriptionProvider.notifier)
        .refresh(force: false);
    expect(
      app.container.read(subscriptionProvider).inBillingGracePeriod,
      isFalse,
    );
    expect(
      app.container.read(subscriptionProvider).billingIssueDetectedAt,
      isNull,
    );
  });

  test('an offline launch keeps a remembered subscriber Premium', () async {
    final cache = MemoryPremiumCache({'reader': paid});
    final app = launch(cache: cache);

    app.container.read(subscriptionProvider);
    await pumpEventQueue();

    final state = app.container.read(subscriptionProvider);
    expect(state.isSubscribed, isTrue);
    expect(state.isLoading, isFalse);
    expect(app.container.read(premiumAccessProvider), isTrue);
    expect(cache.snapshots['reader'], same(paid));
  });

  test('Premium stands before the offline checks give up', () async {
    final never = Completer<BackendEntitlementSnapshot?>();
    final app = launch(
      cache: MemoryPremiumCache({'reader': paid}),
      backend: () => never.future,
    );

    app.container.read(subscriptionProvider);
    await pumpEventQueue();

    final state = app.container.read(subscriptionProvider);
    expect(state.isLoading, isTrue, reason: 'the live checks are still out');
    expect(app.container.read(premiumAccessProvider), isTrue);
  });

  test('offline, nobody is granted what was never confirmed', () async {
    final expired = OfflinePremiumSnapshot(
      verifiedAt: now.subtract(const Duration(days: 40)),
      expiresAt: now.subtract(const Duration(days: 1)),
      willRenew: false,
    );
    for (final (label, cache, userId) in [
      ('no snapshot', MemoryPremiumCache({}), 'reader'),
      ('an ended plan', MemoryPremiumCache({'reader': expired}), 'reader'),
      ('another account', MemoryPremiumCache({'other': paid}), 'reader'),
      ('signed out', MemoryPremiumCache({'reader': paid}), null),
    ]) {
      final app = launch(cache: cache, userId: userId);
      app.container.read(subscriptionProvider);
      await pumpEventQueue();
      expect(app.container.read(premiumAccessProvider), isFalse, reason: label);
    }
  });

  test('a reachable entitlement that says no ends it and forgets it', () async {
    final cache = MemoryPremiumCache({'reader': paid});
    final app = launch(
      cache: cache,
      backend: () async => const BackendEntitlementSnapshot(isActive: false),
    );

    app.container.read(subscriptionProvider);
    await pumpEventQueue();

    expect(app.container.read(premiumAccessProvider), isFalse);
    expect(cache.snapshots, isEmpty);
  });

  test(
    'coming back online with a lapsed plan revokes the offline Premium',
    () async {
      final cache = MemoryPremiumCache({'reader': paid});
      BackendEntitlementSnapshot? answer;
      final app = launch(cache: cache, backend: () async => answer);
      app.container.read(subscriptionProvider);
      await pumpEventQueue();
      expect(app.container.read(premiumAccessProvider), isTrue);

      answer = const BackendEntitlementSnapshot(isActive: false);
      await app.container.read(subscriptionProvider.notifier).syncAndRefresh();
      await pumpEventQueue();

      expect(app.container.read(premiumAccessProvider), isFalse);
      expect(cache.snapshots, isEmpty);
    },
  );

  test('RevenueCat\'s cached Premium holds offline while it is still being '
      'saved', () async {
    final cache = MemoryPremiumCache({})
      ..writesWaitOn = Completer<void>().future;
    final backend = Completer<BackendEntitlementSnapshot?>();
    final app = launch(cache: cache, backend: () => backend.future);
    app.container.read(subscriptionProvider);
    await pumpEventQueue();
    expect(app.container.read(premiumAccessProvider), isFalse);

    // The SDK hands its cached customer info to the listener at configure,
    // then the entitlement function fails for want of a connection.
    app.revenueCat.customerInfoListener!(
      premiumCustomerInfo(expiresAt: now.add(const Duration(days: 20))),
    );
    backend.complete(null);
    await pumpEventQueue();

    expect(app.container.read(premiumAccessProvider), isTrue);
    expect(app.container.read(subscriptionProvider).isLoading, isFalse);
  });

  test('an online confirmation is what the next offline launch uses', () async {
    final cache = MemoryPremiumCache({});
    final expiresAt = now.add(const Duration(days: 30));
    final online = launch(
      cache: cache,
      backend: () async => BackendEntitlementSnapshot(
        isActive: true,
        provider: 'stripe',
        expiresAt: expiresAt,
        willRenew: true,
      ),
    );
    online.container.read(subscriptionProvider);
    await pumpEventQueue();
    expect(online.container.read(premiumAccessProvider), isTrue);
    expect(cache.snapshots['reader']?.expiresAt, expiresAt);
    expect(cache.snapshots['reader']?.provider, 'stripe');

    final offline = launch(cache: cache);
    offline.container.read(subscriptionProvider);
    await pumpEventQueue();
    expect(offline.container.read(premiumAccessProvider), isTrue);
  });
}
