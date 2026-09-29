import 'package:chessever2/services/direct_push_tap_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url =
      'https://chessever.com/broadcast/2026-titled-tuesday-blitz-september-29/mKgqPByN';
  const data = <String, dynamic>{'url': url};
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(DirectPushTapRouter.channel, null);
    DirectPushTapRouter.channel.setMethodCallHandler(null);
  });

  test(
    'launch tap without delivery ID survives and Firebase replay is ignored',
    () async {
      final received = <Map<String, dynamic>>[];
      messenger.setMockMethodCallHandler(DirectPushTapRouter.channel, (
        call,
      ) async {
        expect(call.method, 'takeInitialTap');
        return {'messageId': 'launch-id', 'data': data};
      });
      final router = DirectPushTapRouter();
      await router.initializeNative(received.add);
      router.open('launch-id', data, received.add);
      expect(received, [data]);
    },
  );

  test(
    'warm native tap and distinct notifications with same URL route once each',
    () async {
      final received = <Map<String, dynamic>>[];
      messenger.setMockMethodCallHandler(
        DirectPushTapRouter.channel,
        (_) async => null,
      );
      final router = DirectPushTapRouter();
      await router.initializeNative(received.add);
      await messenger.handlePlatformMessage(
        DirectPushTapRouter.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('notificationOpened', {
            'messageId': 'warm-id',
            'data': data,
          }),
        ),
        (_) {},
      );
      router.open('warm-id', data, received.add);
      router.open('another-id', data, received.add);
      expect(received, [data, data]);
    },
  );
}
