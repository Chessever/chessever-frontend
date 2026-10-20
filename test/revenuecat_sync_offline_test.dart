import 'package:chessever2/revenue_cat_service/revenue_cat_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('purchases_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  List<String> answer({required bool online}) {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (!online && call.method == 'syncPurchases') {
        throw PlatformException(code: '10', message: 'Network error');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    RevenueCatService().markSdkReady();
    return calls;
  }

  test('an offline sync leaves the cached customer info in place', () async {
    final calls = answer(online: false);

    expect(await RevenueCatService().syncPurchases(), isNull);
    expect(calls, ['syncPurchases']);
  });

  test('an online sync refetches past the cache', () async {
    final calls = answer(online: true);

    await RevenueCatService().syncPurchases();
    expect(calls, [
      'syncPurchases',
      'invalidateCustomerInfoCache',
      'getCustomerInfo',
    ]);
  });
}
