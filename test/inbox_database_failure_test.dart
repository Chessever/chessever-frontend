import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/inbox/inbox_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.tekartik.sqflite');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getDatabasesPath') return '/LOCAL-FIXTURE-ONLY';
          throw PlatformException(code: 'LOCAL-FIXTURE-DB-UNAVAILABLE');
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'real AppDatabase init failure stays handled; Inbox still fetches and marks',
    () async {
      final controller = InboxController(
        ownerId: inboxOwnerA,
        source: FakeInboxSource(),
        cache: SqliteInboxCache(AppDatabase.instance),
      );
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.state.messages, hasLength(2));
      expect(controller.state.cacheError, isNotNull);
      expect(await controller.markOpened(inboxIdA), true);
      expect(controller.state.message(inboxIdA)!.readAt, inboxReadTime);
      // Advancing microtasks exposes an unobserved shared-completer failure.
      await Future<void>.delayed(Duration.zero);
    },
  );
  test(
    'concurrent database callers both receive the handled failure',
    () async {
      final first = expectLater(
        AppDatabase.instance.database,
        throwsA(anyOf(isA<PlatformException>(), isA<MissingPluginException>())),
      );
      final second = expectLater(
        AppDatabase.instance.database,
        throwsA(anyOf(isA<PlatformException>(), isA<MissingPluginException>())),
      );
      await Future.wait([first, second]);
      await Future<void>.delayed(Duration.zero);
    },
  );
}
