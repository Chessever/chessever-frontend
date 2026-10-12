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
  test('rich fields round-trip; rows without them are plain text', () {
    final rich = InboxMessage.fromJson({
      ...inboxFixture(inboxIdA).toJson(),
      'body_format': 'markdown',
      'image_url': ' https://chessever.com/a.webp ',
      'action_label': ' Tap to see ',
      'action_url': 'https://chessever.com/feed',
    });
    expect(rich.actionLabel, 'Tap to see');
    expect(rich.actionUrl, 'https://chessever.com/feed');
    expect(rich.withReadAt(inboxReadTime).actionLabel, 'Tap to see');
    // Half a button is no button.
    expect(
      InboxMessage.fromJson({...rich.toJson(), 'action_url': null}).actionLabel,
      isNull,
    );
    expect(rich.isMarkdown, true);
    expect(rich.imageUrl, 'https://chessever.com/a.webp');
    final copy = InboxMessage.fromJson(jsonDecode(jsonEncode(rich.toJson())));
    expect(copy.toJson(), rich.toJson());
    expect(copy.withReadAt(inboxReadTime).isMarkdown, true);
    expect(copy.withReadAt(inboxReadTime).imageUrl, rich.imageUrl);

    final legacy = inboxFixture(inboxIdA).toJson()
      ..remove('body_format')
      ..remove('image_url')
      ..remove('action_label')
      ..remove('action_url');
    final plain = InboxMessage.fromJson(legacy);
    expect(plain.isMarkdown, false);
    expect(plain.imageUrl, isNull);
    expect(plain.actionLabel, isNull);
    // A format this build does not know is shown literally, never guessed at.
    expect(
      InboxMessage.fromJson({...legacy, 'body_format': 'html'}).isMarkdown,
      false,
    );
  });
  test('a Markdown body previews as running text', () {
    final message = InboxMessage(
      id: inboxIdA,
      title: 'LOCAL FIXTURE',
      body:
          '## What is new\n\n![board](https://chessever.com/b.png)\n\n'
          '- **Pin** a _player_ in [Prep](https://chessever.com/prep)\n'
          '1. `Open` it\n\n---\n\n> ~~Old~~ notes stay.',
      publishedAt: DateTime.utc(2026, 9, 30),
      isMarkdown: true,
    );
    expect(
      message.previewText,
      'What is new Pin a player in Prep Open it Old notes stay.',
    );
    // Plain text keeps its marks: they are what the author typed.
    expect(
      InboxMessage(
        id: inboxIdA,
        title: 'LOCAL FIXTURE',
        body: '**kept**\nas typed',
        publishedAt: DateTime.utc(2026, 9, 30),
      ).previewText,
      '**kept** as typed',
    );
  });
  test(
    'a database without the rich listing is asked once, then served as before',
    () async {
      final paths = <String>[];
      final client = _client((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('_v2')) {
          return http.Response(
            '{"code":"PGRST202","message":"LOCAL FIXTURE no such function"}',
            404,
          );
        }
        final row = inboxFixture(inboxIdA).toJson()
          ..remove('body_format')
          ..remove('image_url');
        return http.Response(jsonEncode([row]), 200);
      });
      addTearDown(client.dispose);
      await _signIn(client, inboxOwnerA);
      final source = SupabaseInboxSource(() => client);
      expect((await source.fetch(inboxOwnerA)).single.isMarkdown, false);
      expect(await source.fetch(inboxOwnerA), hasLength(1));
      expect(paths, [
        '/rest/v1/rpc/list_editorial_inbox_v2',
        '/rest/v1/rpc/list_editorial_inbox',
        '/rest/v1/rpc/list_editorial_inbox',
      ]);
    },
  );
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
        expect(request.url.path, '/rest/v1/rpc/list_editorial_inbox_v2');
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
