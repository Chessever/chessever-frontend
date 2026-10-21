import 'package:chessever2/revenue_cat_service/revenue_cat_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('purchases_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  ({List<String> calls, RevenueCatService service}) answer({
    required bool online,
    String? account = 'reader',
  }) {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'getAppUserID') return 'reader';
      if (!online && call.method == 'getCustomerInfo') {
        throw PlatformException(code: '10', message: 'Network error');
      }
      if (call.method == 'getCustomerInfo') {
        return {
          'entitlements': {'all': {}, 'active': {}},
          'allPurchaseDates': {},
          'activeSubscriptions': [],
          'allPurchasedProductIdentifiers': [],
          'nonSubscriptionTransactions': [],
          'firstSeen': '2026-10-20T00:00:00Z',
          'originalAppUserId': 'reader',
          'allExpirationDates': {},
          'requestDate': '2026-10-20T00:00:00Z',
        };
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final service = RevenueCatService.forTesting(() => account)..markSdkReady();
    return (calls: calls, service: service);
  }

  test('an offline sync leaves the cached customer info in place', () async {
    final app = answer(online: false);

    expect(await app.service.syncPurchases(), isNull);
    expect(app.calls, ['getAppUserID', 'getCustomerInfo']);
  });

  test(
    'a routine refresh reads status without restoring device receipts',
    () async {
      final app = answer(online: true);

      final info = await app.service.syncPurchases();
      expect(info?.originalAppUserId, 'reader');
      expect(app.calls, ['getAppUserID', 'getCustomerInfo']);
    },
  );

  test(
    'a signed-out caller cannot sync purchases into an anonymous SDK user',
    () async {
      final app = answer(online: true, account: null);
      expect(await app.service.syncPurchases(), isNull);
      expect(app.calls, isEmpty);
    },
  );

  test('cached SDK access from another account is ignored', () async {
    final app = answer(online: true, account: 'different-reader');
    expect(await app.service.getCustomerInfo(), isNull);
    expect(app.calls, ['getAppUserID']);
  });
}
