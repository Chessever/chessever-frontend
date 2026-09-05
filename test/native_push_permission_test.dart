import 'dart:async';

import 'package:chessever2/services/native_push_permission.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('OneSignal#notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'awaits native permission instead of treating loading as denied',
    () async {
      final reply = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) {
        expect(call.method, 'OneSignal#permission');
        return reply.future;
      });
      var completed = false;
      final read = readNativePushPermission().then((value) {
        completed = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      reply.complete(true);
      expect(await read, isTrue);
    },
  );

  test('reads again when OS permission changes', () async {
    var granted = true;
    messenger.setMockMethodCallHandler(channel, (_) async => granted);
    expect(await readNativePushPermission(), isTrue);
    granted = false;
    expect(await readNativePushPermission(), isFalse);
  });

  test('missing permission is an error, not false', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(readNativePushPermission(), throwsStateError);
  });

  test('native failure is an error, not false', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    await expectLater(
      readNativePushPermission(),
      throwsA(isA<PlatformException>()),
    );
  });
}
