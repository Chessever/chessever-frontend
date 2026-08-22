import 'dart:async';

import 'package:chessever2/revenue_cat_service/revenue_cat_service.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-publishable-key',
    );
  });

  test(
    'offerings are fetched when SDK readiness follows provider creation',
    () async {
      var getOfferingsCalls = 0;
      const channel = MethodChannel('purchases_flutter');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getOfferings') {
          getOfferingsCalls++;
          return <String, Object?>{'all': <String, Object?>{}, 'current': null};
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(subscriptionProvider);
      expect(
        getOfferingsCalls,
        0,
        reason: 'the provider was created before SDK readiness',
      );

      // Complete configuration in the same turn, while the initial
      // not-configured fetch is still unwinding.
      RevenueCatService().markSdkReady();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        getOfferingsCalls,
        1,
        reason:
            'finishing Purchases.configure must re-run the offerings request',
      );
    },
  );

  test('a hanging offerings request becomes a retryable failure', () async {
    var getOfferingsCalls = 0;
    const channel = MethodChannel('purchases_flutter');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) {
      if (call.method == 'getOfferings') {
        getOfferingsCalls++;
        return Completer<Object?>().future;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    RevenueCatService().markSdkReady();
    final result = await RevenueCatService().fetchProducts(
      attempts: 3,
      requestTimeout: const Duration(milliseconds: 20),
    );

    expect(result.status, OfferingsFetchStatus.failure);
    expect(result.isRetryable, isTrue);
    expect(
      getOfferingsCalls,
      1,
      reason: 'a timed-out native request must not be duplicated in parallel',
    );
  });

  test(
    'an SDK configuration failure is terminal instead of loading forever',
    () async {
      final service = RevenueCatService();
      service.markSdkConfigurationFailed(StateError('configuration failed'));
      addTearDown(service.markSdkReady);

      final result = await service.fetchProducts();

      expect(result.status, OfferingsFetchStatus.failure);
      expect(result.isRetryable, isTrue);
    },
  );
}
