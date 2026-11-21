// Opening the paywall asks the store first and the backend only when the
// store has no answer, exactly as RevenueCatService.isSubscribed orders it.
// A reader the store already entitles never costs a call to the
// `entitlement` edge function on the way in.
import 'dart:convert';

import 'package:chessever2/revenue_cat_service/revenue_cat_service.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _reader = 'paywall-reader';

/// RevenueCat's customer info, with the premium entitlement [active] or not.
Map<String, Object?> _customerInfo({required bool active}) {
  const now = '2026-11-20T00:00:00Z';
  final entitlement = {
    'identifier': RevenueCatService.premiumEntitlement,
    'isActive': true,
    'willRenew': true,
    'latestPurchaseDate': now,
    'originalPurchaseDate': now,
    'productIdentifier': 'chessever_monthly',
    'isSandbox': false,
    'expirationDate': '2026-12-20T00:00:00Z',
  };
  final entitlements = active
      ? {RevenueCatService.premiumEntitlement: entitlement}
      : <String, Object?>{};
  return {
    'entitlements': {'all': entitlements, 'active': entitlements},
    'allPurchaseDates': <String, Object?>{},
    'activeSubscriptions': active ? ['chessever_monthly'] : <String>[],
    'allPurchasedProductIdentifiers': active
        ? ['chessever_monthly']
        : <String>[],
    'nonSubscriptionTransactions': <Object?>[],
    'firstSeen': now,
    'originalAppUserId': _reader,
    'allExpirationDates': <String, Object?>{},
    'requestDate': now,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Every request to the `entitlement` edge function.
  final entitlementCalls = <Uri>[];
  var backendPremium = false;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      publishableKey: 'LOCAL-FIXTURE-ANON-KEY',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/functions/v1/entitlement')) {
          entitlementCalls.add(request.url);
          return http.Response(
            jsonEncode({'is_premium': backendPremium, 'status': 'active'}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response('{}', 200, request: request);
      }),
      authOptions: const FlutterAuthClientOptions(
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );
    // A signed-in reader with a full account: the paywall skips sign-in.
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode(
        Session(
          accessToken: 'LOCAL-FIXTURE-TOKEN',
          refreshToken: 'LOCAL-FIXTURE-REFRESH',
          tokenType: 'bearer',
          expiresIn: 3600,
          user: User(
            id: _reader,
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: '2026-09-30T00:00:00Z',
            isAnonymous: false,
          ),
        ).toJson(),
      ),
    );
    RevenueCatService().markSdkReady();
  });

  /// Answers the store's channel with [active]; returns the store calls.
  List<String> store(WidgetTester tester, {required bool active}) {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('purchases_flutter'),
      (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'getAppUserID' => _reader,
          'getCustomerInfo' => _customerInfo(active: active),
          _ => null,
        };
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('purchases_flutter'),
        null,
      ),
    );
    return calls;
  }

  Future<bool> open(WidgetTester tester) async {
    late BuildContext host;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              host = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    var result = false;
    await tester.runAsync(() async {
      result = await showPremiumPaywallSheet(context: host);
    });
    return result;
  }

  testWidgets('a store-entitled reader opens without the entitlement call', (
    tester,
  ) async {
    entitlementCalls.clear();
    final calls = store(tester, active: true);
    expect(await open(tester), isTrue);
    expect(entitlementCalls, isEmpty);
    // One store read, for the account it belongs to.
    expect(calls, ['getAppUserID', 'getCustomerInfo']);
  });

  testWidgets('without a store entitlement the backend is asked, after the '
      'store', (tester) async {
    entitlementCalls.clear();
    backendPremium = true;
    addTearDown(() => backendPremium = false);
    final calls = store(tester, active: false);
    expect(await open(tester), isTrue);
    expect(entitlementCalls, hasLength(1));
    // The sync read, then isSubscribed's own store read, then the backend.
    expect(calls.where((c) => c == 'getCustomerInfo'), hasLength(2));
  });
}
