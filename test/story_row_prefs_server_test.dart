import 'dart:async';
import 'dart:convert';

import 'package:chessever2/screens/stories/story_row_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/memory_story_row_store.dart';

/// Collection stories kept on the server with the reader's other settings
/// (`user_engine_settings.collection_stories`): the server's value is the
/// choice for a signed-in reader on every device, every change is written
/// there, the device's copy is the first frame's and a guest's.
void main() {
  final now = DateTime.utc(2026, 11, 22, 12);

  StoryRowPrefsNotifier start(MemoryStoryRowStore store) {
    final notifier = StoryRowPrefsNotifier(store, () => now);
    addTearDown(notifier.dispose);
    return notifier;
  }

  /// The launch load, and the writes it started.
  Future<void> loaded(StoryRowPrefsNotifier notifier) async {
    await notifier.pull();
    await notifier.settled;
  }

  group('signed in', () {
    test('the server value wins on load over the device copy', () async {
      final store = MemoryStoryRowStore(
        local: '{"m":"on","u":5,"o":"u1"}',
        id: 'u1',
        server: StoryRowMode.off,
      );
      final notifier = start(store);
      // The first frame is the device's copy, before the server answers.
      expect(notifier.state.mode, StoryRowMode.on);
      await loaded(notifier);
      expect(notifier.state.mode, StoryRowMode.off);
      expect(StoryRowPrefs.decodeLocal(store.local).mode, StoryRowMode.off);
      expect(store.serverWrites, isEmpty);
      expect(store.legacyWrites, isEmpty);
    });

    test(
      'a newer account copy (39.2) never overrides a server value',
      () async {
        final store = MemoryStoryRowStore(
          id: 'u1',
          server: StoryRowMode.on,
          legacy: {'m': 'off', 'u': 99},
        );
        final notifier = start(store);
        await loaded(notifier);
        expect(notifier.state.mode, StoryRowMode.on);
        expect(store.serverWrites, isEmpty);
      },
    );

    test('every change writes the server column, in order, and never the '
        "account's metadata", () async {
      final store = MemoryStoryRowStore(id: 'u1', server: StoryRowMode.on);
      final notifier = start(store);
      await loaded(notifier);
      await notifier.setMode(StoryRowMode.off);
      await notifier.setMode(StoryRowMode.on);
      await notifier.setMode(StoryRowMode.off);
      await notifier.settled;
      expect(store.serverWrites, [
        ('u1', StoryRowMode.off),
        ('u1', StoryRowMode.on),
        ('u1', StoryRowMode.off),
      ]);
      expect(store.server, StoryRowMode.off);
      expect(notifier.state.pending, isFalse);
      expect(StoryRowPrefs.decodeLocal(store.local).pending, isFalse);
      expect(store.legacyWrites, isEmpty);
    });

    test(
      'a change made while the load is in flight is not read back over',
      () async {
        final store = MemoryStoryRowStore(id: 'u1', server: StoryRowMode.on)
          ..readGate = Completer<void>();
        final notifier = start(store);
        final load = notifier.pull();
        await notifier.setMode(StoryRowMode.off);
        store.readGate!.complete();
        await load;
        await notifier.settled;
        expect(notifier.state.mode, StoryRowMode.off);
        expect(store.server, StoryRowMode.off);
      },
    );

    test('a read that started while a write was in flight never puts the old '
        'value back, even when it is answered after the write', () async {
      final store = MemoryStoryRowStore(id: 'u1', server: StoryRowMode.on);
      final notifier = start(store);
      await loaded(notifier);
      store
        ..writeGate = Completer<void>()
        ..readsAtStart = true
        ..readGate = Completer<void>();
      await notifier.setMode(StoryRowMode.off);
      // Today's row comes up while the write is still on its way: the
      // server answers this read with the value from before the write.
      final load = notifier.pull();
      store.writeGate!.complete();
      await notifier.settled;
      expect(notifier.state.pending, isFalse);
      store.readGate!.complete();
      await load;
      expect(notifier.state.mode, StoryRowMode.off);
      expect(store.server, StoryRowMode.off);
      // The next load reads the server as it now is.
      store
        ..readGate = null
        ..readsAtStart = false;
      await loaded(notifier);
      expect(notifier.state.mode, StoryRowMode.off);
    });

    test('a change that could not reach the server is written at the next '
        'load instead of being undone by it', () async {
      final store = MemoryStoryRowStore(id: 'u1', server: StoryRowMode.on);
      final first = start(store);
      await loaded(first);
      store.offline = true;
      await first.setMode(StoryRowMode.off);
      await first.settled;
      expect(store.server, StoryRowMode.on);
      expect(StoryRowPrefs.decodeLocal(store.local).pending, isTrue);
      // The next launch, online again.
      store.offline = false;
      final next = start(store);
      expect(next.state.mode, StoryRowMode.off);
      await loaded(next);
      expect(next.state.mode, StoryRowMode.off);
      expect(store.server, StoryRowMode.off);
      expect(next.state.pending, isFalse);
    });

    test(
      'offline at launch: the device copy stands, nothing is written',
      () async {
        final store = MemoryStoryRowStore(
          local: '{"m":"off","u":5,"o":"u1"}',
          id: 'u1',
          server: StoryRowMode.on,
          offline: true,
        );
        final notifier = start(store);
        await loaded(notifier);
        expect(notifier.state.mode, StoryRowMode.off);
        expect(store.serverWrites, isEmpty);
      },
    );

    test('sign in and an account switch load that account\'s own choice; '
        "another account's device copy is never carried", () async {
      final store = MemoryStoryRowStore(
        local: '{"m":"off","u":5,"o":"u2"}',
        id: 'u1',
      );
      final notifier = start(store);
      // u2's Off is not u1's, not even for the first frame.
      expect(notifier.state.mode, StoryRowMode.on);
      await loaded(notifier);
      expect(notifier.state.mode, StoryRowMode.on);
      // Nothing chosen anywhere: the column stays null.
      expect(store.serverWrites, isEmpty);
      store
        ..server = StoryRowMode.off
        ..signIn('u3');
      await pumpEventQueue();
      await loaded(notifier);
      expect(notifier.state.mode, StoryRowMode.off);
      expect(notifier.state.owner, 'u3');
      final reads = store.reads;
      // A token refresh (the same reader) loads nothing.
      store.signIn('u3');
      await pumpEventQueue();
      expect(store.reads, reads);
    });
  });

  group('the column is null: the choice the reader had is carried once', () {
    test("from the account's metadata", () async {
      final store = MemoryStoryRowStore(
        id: 'u1',
        legacy: {'m': 'off', 'u': 10},
      );
      final notifier = start(store);
      await loaded(notifier);
      expect(notifier.state.mode, StoryRowMode.off);
      expect(store.serverWrites, [('u1', StoryRowMode.off)]);
      // Read again (Today's row comes up): the server has it now.
      await loaded(notifier);
      expect(store.serverWrites, hasLength(1));
      expect(store.legacyWrites, isEmpty);
    });

    test("from a 39.2 pull-away on the account's metadata", () async {
      final store = MemoryStoryRowStore(
        id: 'u1',
        legacy: {
          'm': 'on',
          'd': {'t': 1763600000000, 'f': 'abc', 'g': 12},
          'u': 9,
        },
      );
      final notifier = start(store);
      await loaded(notifier);
      expect(store.serverWrites, [('u1', StoryRowMode.off)]);
    });

    test("from the device's copy when the account has none, a choice made "
        'signed out included', () async {
      final store = MemoryStoryRowStore(local: '{"m":"off","u":5}', id: 'u1');
      final notifier = start(store);
      await loaded(notifier);
      expect(notifier.state.mode, StoryRowMode.off);
      expect(notifier.state.owner, 'u1');
      expect(store.serverWrites, [('u1', StoryRowMode.off)]);
    });

    test(
      "the account's metadata first, unless the device's is newer",
      () async {
        final store = MemoryStoryRowStore(
          local: '{"m":"on","u":5,"o":"u1"}',
          id: 'u1',
          legacy: {'m': 'off', 'u': 10},
        );
        final notifier = start(store);
        await loaded(notifier);
        expect(store.serverWrites, [('u1', StoryRowMode.off)]);

        final newer = MemoryStoryRowStore(
          local: '{"m":"on","u":20,"o":"u1"}',
          id: 'u1',
          legacy: {'m': 'off', 'u': 10},
        );
        final other = start(newer);
        await loaded(other);
        expect(newer.serverWrites, [('u1', StoryRowMode.on)]);
      },
    );

    test('nothing chosen: nothing written, the row On', () async {
      final store = MemoryStoryRowStore(id: 'u1');
      final notifier = start(store);
      await loaded(notifier);
      expect(notifier.state.mode, StoryRowMode.on);
      expect(store.serverWrites, isEmpty);
    });
  });

  group('a guest', () {
    test(
      'keeps the choice on the device, never reads or writes the server',
      () async {
        final store = MemoryStoryRowStore(local: '{"m":"off","u":5}');
        final notifier = start(store);
        await loaded(notifier);
        expect(notifier.state.mode, StoryRowMode.off);
        await notifier.setMode(StoryRowMode.on);
        await notifier.settled;
        expect(StoryRowPrefs.decodeLocal(store.local).mode, StoryRowMode.on);
        expect(notifier.state.pending, isFalse);
        expect(store.reads, 0);
        expect(store.serverWrites, isEmpty);
        expect(store.legacyWrites, isEmpty);
      },
    );
  });

  group('before the migration (no column on the server)', () {
    test("falls back to 39.2: the account's metadata, the newer copy "
        'winning, and changes written there', () async {
      final store = MemoryStoryRowStore(
        local: '{"m":"on","u":5,"o":"u1"}',
        id: 'u1',
        legacy: {'m': 'off', 'u': 10},
        missingColumn: true,
      );
      final notifier = start(store);
      await loaded(notifier);
      expect(notifier.state.mode, StoryRowMode.off);
      await notifier.setMode(StoryRowMode.on);
      await notifier.settled;
      expect(notifier.state.mode, StoryRowMode.on);
      expect(notifier.state.pending, isFalse);
      expect(store.legacyWrites.single['m'], 'on');
      expect(store.serverWrites, isEmpty);
    });

    test(
      'once the column exists, the metadata kept meanwhile is carried',
      () async {
        final store = MemoryStoryRowStore(id: 'u1', missingColumn: true);
        final before = start(store);
        await loaded(before);
        await before.setMode(StoryRowMode.off);
        await before.settled;
        // The migration is applied; the next launch.
        store.missingColumn = false;
        final after = start(store);
        await loaded(after);
        expect(after.state.mode, StoryRowMode.off);
        expect(store.serverWrites, [('u1', StoryRowMode.off)]);
      },
    );
  });

  group('AppStoryRowPrefsStore on PostgREST', () {
    http.Response json(
      Object body,
      http.BaseRequest request, {
      int status = 200,
    }) => http.Response(
      jsonEncode(body),
      status,
      request: request,
      headers: {'content-type': 'application/json'},
    );

    AppStoryRowPrefsStore storeOn(
      FutureOr<http.Response> Function(http.Request request) handler,
    ) => AppStoryRowPrefsStore(
      client: SupabaseClient(
        'https://example.test',
        'placeholder',
        httpClient: MockClient((request) async => handler(request)),
      ),
    );

    test('reads its own column of the reader\'s settings row', () async {
      final requests = <http.Request>[];
      final store = storeOn((request) {
        requests.add(request);
        return json([
          {'collection_stories': 'off'},
        ], request);
      });
      final read = await store.readServer('u1');
      expect(read, isA<StoryRowServerValue>());
      expect((read as StoryRowServerValue).mode, StoryRowMode.off);
      final url = requests.single.url;
      expect(url.path, endsWith('/rest/v1/user_engine_settings'));
      expect(url.queryParameters['select'], 'collection_stories');
      expect(url.queryParameters['user_id'], 'eq.u1');
    });

    test('no row, or the column null: never chosen', () async {
      final none = await storeOn((r) => json([], r)).readServer('u1');
      expect((none as StoryRowServerValue).mode, isNull);
      final empty = await storeOn(
        (r) => json([
          {'collection_stories': null},
        ], r),
      ).readServer('u1');
      expect((empty as StoryRowServerValue).mode, isNull);
    });

    test('writes the column alone by an upsert on user_id', () async {
      final requests = <http.Request>[];
      final store = storeOn((request) {
        requests.add(request);
        return http.Response('', 201, request: request);
      });
      final result = await store.writeServer('u1', StoryRowMode.off);
      expect(result, StoryRowServerWrite.saved);
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/rest/v1/user_engine_settings'));
      expect(request.url.queryParameters['on_conflict'], 'user_id');
      expect(request.headers['Prefer'], contains('merge-duplicates'));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.keys.toSet(), {
        'user_id',
        'collection_stories',
        'updated_at',
      });
      expect(body['user_id'], 'u1');
      expect(body['collection_stories'], 'off');
    });

    test('a missing column (42703 to a read, PGRST204 to a write) is told '
        'apart from a failure, and nothing throws', () async {
      final missingRead = await storeOn(
        (r) => json(
          {
            'code': '42703',
            'details': null,
            'hint': null,
            'message':
                'column user_engine_settings.collection_stories does not exist',
          },
          r,
          status: 400,
        ),
      ).readServer('u1');
      expect(missingRead, isA<StoryRowServerMissing>());

      final missingWrite = await storeOn(
        (r) => json(
          {
            'code': 'PGRST204',
            'details': null,
            'hint': null,
            'message':
                "Could not find the 'collection_stories' column of "
                "'user_engine_settings' in the schema cache",
          },
          r,
          status: 400,
        ),
      ).writeServer('u1', StoryRowMode.off);
      expect(missingWrite, StoryRowServerWrite.missingColumn);

      final down = storeOn(
        (r) => json({'message': 'statement timeout'}, r, status: 500),
      );
      expect(await down.readServer('u1'), isA<StoryRowServerUnreachable>());
      expect(
        await down.writeServer('u1', StoryRowMode.on),
        StoryRowServerWrite.failed,
      );

      final offline = storeOn(
        (r) => throw http.ClientException('Failed host lookup', r.url),
      );
      // (An offline read is retried by the client for seconds; the 500
      // above covers a failed read.)
      expect(
        await offline.writeServer('u1', StoryRowMode.on),
        StoryRowServerWrite.failed,
      );
    });

    test('with no session the store is a guest\'s', () {
      final store = storeOn((r) => json([], r));
      expect(store.accountId(), isNull);
      expect(store.readLegacyAccount(), isNull);
    });

    test('a missing column is recognised when the client rethrows it as '
        'the HTTP status with the body as its message', () {
      expect(
        AppStoryRowPrefsStore.isMissingColumn(
          const PostgrestException(
            message:
                '{"code":"42703","details":null,"hint":null,"message":'
                '"column user_engine_settings.collection_stories does not '
                'exist"}',
            code: '400',
          ),
        ),
        isTrue,
      );
      expect(
        AppStoryRowPrefsStore.isMissingColumn(
          const PostgrestException(message: 'Bad gateway', code: '502'),
        ),
        isFalse,
      );
      expect(
        AppStoryRowPrefsStore.isMissingColumn(
          const PostgrestException(
            message: '{"code":"42501","message":"permission denied"}',
            code: '403',
          ),
        ),
        isFalse,
      );
      expect(
        AppStoryRowPrefsStore.isMissingColumn(TimeoutException('')),
        isFalse,
      );
    });
  });
}
