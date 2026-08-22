import 'dart:async';
import 'dart:convert';

import 'package:chessever2/revenue_cat_service/revenue_cat_service.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'offerings reach state while backend entitlement request is hanging',
    () async {
      SharedPreferences.setMockInitialValues({});
      final entitlementRequestStarted = Completer<void>();
      final hangingResponse = Completer<http.Response>();
      await Supabase.initialize(
        url: 'https://placeholder.supabase.co',
        publishableKey: 'placeholder-publishable-key',
        httpClient: MockClient((request) {
          if (!entitlementRequestStarted.isCompleted) {
            entitlementRequestStarted.complete();
          }
          return hangingResponse.future;
        }),
      );
      final session = Session(
        accessToken: 'test-access-token',
        refreshToken: 'test-refresh-token',
        tokenType: 'bearer',
        expiresIn: 3600,
        user: const User(
          id: 'test-user',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-08-22T00:00:00Z',
        ),
      );
      await Supabase.instance.client.auth.recoverSession(
        jsonEncode(session.toJson()),
      );

      var getOfferingsCalls = 0;
      const channel = MethodChannel('purchases_flutter');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getOfferings':
            getOfferingsCalls++;
            final offering = _offeringJson();
            return <String, Object?>{
              'all': <String, Object?>{'current': offering},
              'current': offering,
            };
          case 'getCustomerInfo':
            throw PlatformException(code: 'not_needed_for_this_test');
          default:
            return null;
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      RevenueCatService().markSdkReady();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(subscriptionProvider);

      await entitlementRequestStarted.future.timeout(
        const Duration(seconds: 2),
      );
      for (
        var i = 0;
        i < 10 && container.read(subscriptionProvider).products.isEmpty;
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(getOfferingsCalls, 1);
      expect(
        container.read(subscriptionProvider).products,
        hasLength(1),
        reason:
            'RevenueCat prices must not wait for the unrelated entitlement call',
      );
      expect(
        container.read(subscriptionProvider).productsError,
        isNotNull,
        reason:
            'a partial catalog must terminate in an actionable state, not shimmer forever',
      );
      expect(
        container.read(subscriptionProvider).isLoading,
        isTrue,
        reason: 'the test proves the entitlement request is still unresolved',
      );
    },
  );
}

Map<String, Object?> _offeringJson() {
  final package = <String, Object?>{
    'identifier': r'$rc_annual',
    'packageType': 'ANNUAL',
    'product': <String, Object?>{
      'identifier': 'rc_chessever_annual',
      'description': 'ChessEver annual subscription',
      'title': 'ChessEver Annual',
      'price': 119.99,
      'priceString': r'$119.99',
      'currencyCode': 'USD',
      'introPrice': null,
      'discounts': null,
      'productCategory': null,
      'defaultOption': null,
      'subscriptionOptions': null,
      'presentedOfferingContext': null,
      'subscriptionPeriod': 'P1Y',
    },
    'presentedOfferingContext': <String, Object?>{
      'offeringIdentifier': 'rc_chessever_premium',
      'placementIdentifier': null,
      'targetingContext': null,
    },
  };
  return <String, Object?>{
    'identifier': 'rc_chessever_premium',
    'serverDescription': 'ChessEver Premium',
    'metadata': <String, Object?>{},
    'availablePackages': <Object?>[package],
    'lifetime': null,
    'annual': package,
    'sixMonth': null,
    'threeMonth': null,
    'twoMonth': null,
    'monthly': null,
    'weekly': null,
    'webCheckoutUrl': null,
  };
}
