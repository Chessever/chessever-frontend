import 'dart:convert';
import 'dart:io';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/inbox/inbox_message.dart';
import 'package:chessever2/screens/inbox/inbox_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'inbox_fakes.dart';

// File-backed AppDatabase contract double, NOT a native SQLite/device test.
class _FileDatabase implements AppDatabase {
  _FileDatabase(this.directory);
  final Directory directory;
  File file(String key, String? owner) =>
      File('${directory.path}/$key-$owner.json');
  @override
  Future<void> setCache({
    required String key,
    required String value,
    String? userId,
  }) => file(key, userId).writeAsString(value).then((_) {});
  @override
  Future<CacheEntry?> getCache({
    required String key,
    String? userId,
    Duration? maxAge,
  }) async {
    final path = file(key, userId);
    return await path.exists()
        ? CacheEntry(
            value: await path.readAsString(),
            cachedAt: DateTime.utc(2026),
          )
        : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _signIn(SupabaseClient client, String owner) async {
  await client.auth.recoverSession(
    jsonEncode(
      Session(
        accessToken: 'LOCAL-FIXTURE-TOKEN-$owner',
        refreshToken: 'LOCAL-FIXTURE-REFRESH',
        tokenType: 'bearer',
        expiresIn: 3600,
        user: User(
          id: owner,
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '2026-09-30T00:00:00Z',
          isAnonymous: true,
        ),
      ).toJson(),
    ),
  );
}

SupabaseClient _client(Future<http.Response> Function(http.Request) handle) =>
    SupabaseClient(
      'http://127.0.0.1:54321',
      'LOCAL-FIXTURE-ANON-KEY',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final response = await handle(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('plain message JSON round-trip preserves dates, body and exact ID', () {
    final message = inboxFixture(inboxIdA, readAt: inboxReadTime);
    final copy = InboxMessage.fromJson(
      jsonDecode(jsonEncode(message.toJson())),
    );
    expect(copy.toJson(), message.toJson());
    expect(copy.body, contains('<script>'));
  });
  test('rejects malformed and oversized content', () {
    final valid = inboxFixture(inboxIdA).toJson();
    for (final override in [
      {'id': 'broken'},
      {'title': ''},
      {'title': 'title\nsecond line'},
      {'title': 'a' * 201},
      {'body': 'a' * 20001},
      {'published_at': null},
      {'published_at': 'not-date'},
      {'read_at': 'not-date'},
    ]) {
      expect(
        () => InboxMessage.fromJson({...valid, ...override}),
        throwsA(anything),
      );
    }
  });
  test(
    'real Supabase adapter paginates every row with exact cursor and owner JWT',
    () async {
      final all = [
        for (var i = 1; i <= 205; i++)
          InboxMessage(
            id: '30000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
            title: 'LOCAL FIXTURE $i',
            body: 'LOCAL FIXTURE ONLY',
            publishedAt: DateTime.utc(
              2026,
              9,
              30,
            ).subtract(Duration(seconds: i)),
          ),
      ];
      var page = 0;
      final requests = <Map<String, dynamic>>[];
      final client = _client((request) async {
        expect(request.url.path, '/rest/v1/rpc/list_editorial_inbox');
        expect(
          request.headers['authorization'],
          'Bearer LOCAL-FIXTURE-TOKEN-$inboxOwnerA',
        );
        final params = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(params);
        final offset = page++ * 100;
        return http.Response(
          jsonEncode(
            all.skip(offset).take(100).map((m) => m.toJson()).toList(),
          ),
          200,
        );
      });
      addTearDown(client.dispose);
      await _signIn(client, inboxOwnerA);
      final messages = await SupabaseInboxSource(
        () => client,
      ).fetch(inboxOwnerA);
      expect(messages, hasLength(205));
      expect(requests, hasLength(3));
      expect(requests[0], {
        'p_limit': 100,
        'p_before_id': null,
        'p_before_published_at': null,
      });
      expect(requests[1]['p_before_id'], all[99].id);
      expect(
        requests[1]['p_before_published_at'],
        all[99].publishedAt.toIso8601String(),
      );
      expect(requests[2]['p_before_id'], all[199].id);
    },
  );
  test(
    'pagination error fails full snapshot, never returns partial unread result',
    () async {
      var calls = 0;
      final client = _client((_) async {
        if (calls++ > 0) {
          return http.Response('{"message":"LOCAL FIXTURE offline"}', 400);
        }
        return http.Response(
          jsonEncode([
            for (var i = 1; i <= 100; i++)
              {
                ...inboxFixture(inboxIdA).toJson(),
                'id':
                    '30000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
              },
          ]),
          200,
        );
      });
      addTearDown(client.dispose);
      await _signIn(client, inboxOwnerA);
      await expectLater(
        SupabaseInboxSource(() => client).fetch(inboxOwnerA),
        throwsA(isA<PostgrestException>()),
      );
      expect(calls, 2);
    },
  );
  test(
    'duplicate page is rejected, not an infinite fetch or false count',
    () async {
      final client = _client(
        (_) async => http.Response(
          jsonEncode([
            for (var i = 0; i < 100; i++) inboxFixture(inboxIdA).toJson(),
          ]),
          200,
        ),
      );
      addTearDown(client.dispose);
      await _signIn(client, inboxOwnerA);
      await expectLater(
        SupabaseInboxSource(() => client).fetch(inboxOwnerA),
        throwsFormatException,
      );
    },
  );
  test('mark adapter sends only exact message ID, reads valid ack', () async {
    final client = _client((request) async {
      expect(request.url.path, '/rest/v1/rpc/mark_editorial_inbox_read');
      expect(jsonDecode(request.body), {'p_message_id': inboxIdA});
      expect(
        request.headers['authorization'],
        'Bearer LOCAL-FIXTURE-TOKEN-$inboxOwnerA',
      );
      return http.Response(jsonEncode(inboxReadTime.toIso8601String()), 200);
    });
    addTearDown(client.dispose);
    await _signIn(client, inboxOwnerA);
    expect(
      await SupabaseInboxSource(() => client).markRead(inboxOwnerA, inboxIdA),
      inboxReadTime,
    );
  });
  test('null mark acknowledgement is a failure', () async {
    final client = _client((_) async => http.Response('null', 200));
    addTearDown(client.dispose);
    await _signIn(client, inboxOwnerA);
    await expectLater(
      SupabaseInboxSource(() => client).markRead(inboxOwnerA, inboxIdA),
      throwsA(anything),
    );
  });
  test(
    'no session and wrong account are rejected before any request',
    () async {
      var requests = 0;
      final client = _client((_) async {
        requests++;
        return http.Response('[]', 200);
      });
      addTearDown(client.dispose);
      final source = SupabaseInboxSource(() => client);
      await expectLater(source.fetch(inboxOwnerA), throwsStateError);
      await _signIn(client, inboxOwnerB);
      await expectLater(source.fetch(inboxOwnerA), throwsStateError);
      await expectLater(
        source.markRead(inboxOwnerA, inboxIdA),
        throwsStateError,
      );
      expect(requests, 0);
    },
  );
  test(
    'account switch during in-flight mark retains A JWT, rejects result',
    () async {
      late SupabaseClient client;
      final headers = <String?>[];
      client = _client((request) async {
        headers.add(request.headers['authorization']);
        await _signIn(client, inboxOwnerB);
        return http.Response(jsonEncode(inboxReadTime.toIso8601String()), 200);
      });
      addTearDown(client.dispose);
      await _signIn(client, inboxOwnerA);
      await expectLater(
        SupabaseInboxSource(() => client).markRead(inboxOwnerA, inboxIdA),
        throwsStateError,
      );
      expect(headers, ['Bearer LOCAL-FIXTURE-TOKEN-$inboxOwnerA']);
      expect(client.auth.currentUser!.id, inboxOwnerB);
    },
  );
  test(
    'cache adapter serializes durable owner-scoped snapshots; tamper rejected',
    () async {
      final parent = Directory(
        '${Directory.current.path}/.dart_tool/inbox-fixtures',
      );
      await parent.create(recursive: true);
      final directory = await parent.createTemp('cache-');
      addTearDown(() => directory.delete(recursive: true));
      final db = _FileDatabase(directory);
      final cache = SqliteInboxCache(db);
      await cache.save(inboxOwnerA, [
        inboxFixture(inboxIdA, readAt: inboxReadTime),
      ]);
      await cache.save(inboxOwnerB, [inboxFixture(inboxIdB)]);
      final restarted = SqliteInboxCache(_FileDatabase(directory));
      expect((await restarted.load(inboxOwnerA))!.single.readAt, inboxReadTime);
      expect((await restarted.load(inboxOwnerB))!.single.isUnread, true);
      final files = await directory
          .list()
          .where((f) => f.path.endsWith('$inboxOwnerA.json'))
          .toList();
      final file = files.single as File;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      await file.writeAsString(jsonEncode({...json, 'owner': inboxOwnerB}));
      await expectLater(restarted.load(inboxOwnerA), throwsFormatException);
    },
  );
}
