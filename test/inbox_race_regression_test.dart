// Synthetic local SDK/storage races; never contacts a hosted backend.
import 'dart:async';
import 'dart:convert';

import 'package:chessever2/config/app_environment.dart';
import 'package:chessever2/providers/app_resume_signal_provider.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/inbox/inbox_message.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/inbox/inbox_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'inbox_fakes.dart';

Map<String, dynamic> _session(
  String owner, {
  bool expired = false,
  String label = 'token',
}) {
  final expiry =
      DateTime.now().millisecondsSinceEpoch ~/ 1000 + (expired ? -60 : 3600);
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {
    'access_token':
        '${encode({'alg': 'none', 'typ': 'JWT'})}.${encode({'sub': owner, 'exp': expiry, 'fixture': label})}.LOCAL-FIXTURE-SIGNATURE',
    'refresh_token': 'LOCAL-FIXTURE-REFRESH-$owner',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': expiry,
    'user': User(
      id: owner,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-09-30T00:00:00Z',
      isAnonymous: true,
    ).toJson(),
  };
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

class _Database implements AppDatabase {
  final values = <String, String>{};
  Future<void> Function(String)? beforeWrite;
  int reads = 0;
  @override
  Future<void> setCache({
    required String key,
    required String value,
    String? userId,
  }) async {
    expect(key, 'test_editorial_inbox_v1');
    await beforeWrite?.call(userId!);
    values['$key/$userId'] = value;
  }

  @override
  Future<CacheEntry?> getCache({
    required String key,
    String? userId,
    Duration? maxAge,
  }) async {
    expect(key, 'test_editorial_inbox_v1');
    reads++;
    final value = values['$key/$userId'];
    return value == null
        ? null
        : CacheEntry(value: value, cachedAt: DateTime.utc(2026));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache extends FakeInboxCache {
  Future<List<InboxMessage>?> Function(String)? loadOverride;
  int loads = 0;
  @override
  Future<List<InboxMessage>?> load(String ownerId) {
    loads++;
    return loadOverride?.call(ownerId) ?? super.load(ownerId);
  }
}

class _Source extends FakeInboxSource {
  String owner = inboxOwnerA;
  @override
  bool hasSession(String ownerId) => owner == ownerId;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppEnvironment.configure(AppFlavor.test);

  test(
    'test-flavor recovery cannot read or overwrite the production owner snapshot',
    () async {
      final db = _Database();
      final productionKey = 'production_editorial_inbox_v1/$inboxOwnerA';
      final productionSnapshot = jsonEncode({
        'owner': inboxOwnerA,
        'version': 1,
        'messages': [inboxFixture(inboxIdA).toJson()],
      });
      db.values[productionKey] = productionSnapshot;
      final cache = SqliteInboxCache(db);
      expect(await cache.load(inboxOwnerA), isNull);
      await cache.save(inboxOwnerA, [inboxFixture(inboxIdB)]);
      expect((await cache.load(inboxOwnerA))!.single.id, inboxIdB);
      expect(db.values[productionKey], productionSnapshot);
    },
  );

  for (final marking in [false, true]) {
    test(
      '${marking ? 'mark' : 'fetch'} rechecks identity after the freshness helper await before dispatch',
      () async {
        var requests = 0;
        final events = <String>[];
        late SupabaseClient client;
        client = _client((_) async {
          events.add('HTTP owner=${client.auth.currentUser!.id}');
          requests++;
          return http.Response('[]', 200);
        });
        addTearDown(client.dispose);
        await client.auth.setInitialSession(jsonEncode(_session(inboxOwnerA)));
        var lookups = 0;
        final source = SupabaseInboxSource(() {
          events.add(
            'lookup ${++lookups} owner=${client.auth.currentUser!.id}',
          );
          if (lookups == 3) {
            // _freshSession's final check has already captured A. This SDK
            // restore updates currentSession synchronously, so B is installed
            // before the helper returns and the caller resumes. A queued
            // microtask instead runs AFTER the caller's dispatch check.
            unawaited(
              client.auth.setInitialSession(jsonEncode(_session(inboxOwnerB))),
            );
            expect(client.auth.currentUser!.id, inboxOwnerB);
            events.add('B installed before helper returns');
          }
          return client;
        });
        await expectLater(
          marking
              ? source.markRead(inboxOwnerA, inboxIdA)
              : source.fetch(inboxOwnerA),
          throwsStateError,
        );
        expect(requests, 0, reason: events.join('\n'));
        expect(client.auth.currentUser!.id, inboxOwnerB);
        expect(events, [
          'lookup 1 owner=$inboxOwnerA',
          'lookup 2 owner=$inboxOwnerA',
          'lookup 3 owner=$inboxOwnerA',
          'B installed before helper returns',
          'lookup 4 owner=$inboxOwnerB',
        ]);
      },
    );

    test(
      '${marking ? 'mark' : 'fetch'} pins A when a queued switch runs after the caller dispatch check, rejects the response',
      () async {
        final a = _session(inboxOwnerA);
        final events = <String>[];
        var requests = 0;
        late SupabaseClient client;
        client = _client((request) async {
          requests++;
          events.add('HTTP owner=${client.auth.currentUser!.id}');
          expect(
            request.headers['authorization'],
            'Bearer ${a['access_token']}',
          );
          return http.Response(
            marking ? jsonEncode(inboxReadTime.toIso8601String()) : '[]',
            200,
          );
        });
        addTearDown(client.dispose);
        await client.auth.setInitialSession(jsonEncode(a));
        var lookups = 0;
        final source = SupabaseInboxSource(() {
          events.add(
            'lookup ${++lookups} owner=${client.auth.currentUser!.id}',
          );
          if (lookups == 3) {
            scheduleMicrotask(() {
              events.add('switch microtask');
              unawaited(
                client.auth.setInitialSession(
                  jsonEncode(_session(inboxOwnerB)),
                ),
              );
            });
          }
          return client;
        });
        await expectLater(
          marking
              ? source.markRead(inboxOwnerA, inboxIdA)
              : source.fetch(inboxOwnerA),
          throwsStateError,
        );
        expect(requests, 1);
        expect(client.auth.currentUser!.id, inboxOwnerB);
        expect(events, [
          'lookup 1 owner=$inboxOwnerA',
          'lookup 2 owner=$inboxOwnerA',
          'lookup 3 owner=$inboxOwnerA',
          'lookup 4 owner=$inboxOwnerA',
          'switch microtask',
          'HTTP owner=$inboxOwnerB',
          'lookup 5 owner=$inboxOwnerB',
        ]);
      },
    );
  }

  test(
    'concurrent fetch and mark join the SDK refresh, pin the refreshed owner token',
    () async {
      final refreshStarted = Completer<void>();
      final release = Completer<void>();
      final refreshed = _session(inboxOwnerA, label: 'fresh');
      var refreshes = 0;
      final headers = <String?>[];
      final client = _client((request) async {
        if (request.url.path == '/auth/v1/token') {
          refreshes++;
          refreshStarted.complete();
          await release.future;
          return http.Response(jsonEncode(refreshed), 200);
        }
        headers.add(request.headers['authorization']);
        return http.Response(
          request.url.path.endsWith('mark_editorial_inbox_read')
              ? jsonEncode(inboxReadTime.toIso8601String())
              : '[]',
          200,
        );
      });
      addTearDown(client.dispose);
      await client.auth.setInitialSession(
        jsonEncode(_session(inboxOwnerA, expired: true)),
      );
      final source = SupabaseInboxSource(() => client);
      final fetch = source.fetch(inboxOwnerA);
      final mark = source.markRead(inboxOwnerA, inboxIdA);
      await refreshStarted.future;
      expect(refreshes, 1);
      expect(headers, isEmpty);
      release.complete();
      expect(await fetch, isEmpty);
      expect(await mark, inboxReadTime);
      expect(refreshes, 1);
      expect(headers, [
        'Bearer ${refreshed['access_token']}',
        'Bearer ${refreshed['access_token']}',
      ]);
    },
  );

  for (final marking in [false, true]) {
    test(
      '${marking ? 'mark' : 'fetch'} rejects A-to-B switch while SDK freshness is pending, with no RPC',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        var rpcs = 0;
        final client = _client((request) async {
          if (request.url.path == '/auth/v1/token') {
            started.complete();
            await release.future;
            return http.Response(
              jsonEncode(_session(inboxOwnerA, label: 'fresh')),
              200,
            );
          }
          rpcs++;
          return http.Response('[]', 200);
        });
        addTearDown(client.dispose);
        await client.auth.setInitialSession(
          jsonEncode(_session(inboxOwnerA, expired: true)),
        );
        final source = SupabaseInboxSource(() => client);
        final Future<Object> pending = marking
            ? source.markRead(inboxOwnerA, inboxIdA)
            : source.fetch(inboxOwnerA);
        final rejected = expectLater(pending, throwsStateError);
        await started.future;
        await client.auth.setInitialSession(jsonEncode(_session(inboxOwnerB)));
        release.complete();
        await rejected;
        expect(rpcs, 0);
        expect(client.auth.currentUser!.id, inboxOwnerB);
      },
    );
  }

  test(
    'each pagination dispatch refreshes the same-owner token instead of retaining page one JWT',
    () async {
      final firstSession = _session(inboxOwnerA, label: 'first');
      final refreshed = _session(inboxOwnerA, label: 'fresh');
      late SupabaseClient client;
      var pages = 0;
      var refreshes = 0;
      client = _client((request) async {
        if (request.url.path == '/auth/v1/token') {
          refreshes++;
          return http.Response(jsonEncode(refreshed), 200);
        }
        pages++;
        expect(
          request.headers['authorization'],
          'Bearer ${(pages == 1 ? firstSession : refreshed)['access_token']}',
        );
        if (pages == 1) {
          await client.auth.setInitialSession(
            jsonEncode(_session(inboxOwnerA, expired: true)),
          );
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
        }
        return http.Response('[]', 200);
      });
      addTearDown(client.dispose);
      await client.auth.setInitialSession(jsonEncode(firstSession));
      expect(
        await SupabaseInboxSource(() => client).fetch(inboxOwnerA),
        hasLength(100),
      );
      expect(pages, 2);
      expect(refreshes, 1);
    },
  );

  test(
    'fetch pins A at dispatch and rejects response after switching to B',
    () async {
      final a = _session(inboxOwnerA);
      late SupabaseClient client;
      var requests = 0;
      client = _client((request) async {
        requests++;
        expect(request.headers['authorization'], 'Bearer ${a['access_token']}');
        await client.auth.setInitialSession(jsonEncode(_session(inboxOwnerB)));
        return http.Response(
          jsonEncode([inboxFixture(inboxIdA).toJson()]),
          200,
        );
      });
      addTearDown(client.dispose);
      await client.auth.setInitialSession(jsonEncode(a));
      await expectLater(
        SupabaseInboxSource(() => client).fetch(inboxOwnerA),
        throwsStateError,
      );
      expect(requests, 1);
    },
  );

  test(
    'load waits for a pending failed save, then reads last-good data',
    () async {
      final db = _Database();
      final cache = SqliteInboxCache(db);
      await cache.save(inboxOwnerA, [inboxFixture(inboxIdA)]);
      final gate = Completer<void>();
      db.beforeWrite = (_) => gate.future;
      final failed = expectLater(cache.save(inboxOwnerA, []), throwsStateError);
      var loaded = false;
      final load = cache.load(inboxOwnerA).then((rows) {
        loaded = true;
        return rows;
      });
      await Future<void>.delayed(Duration.zero);
      expect(loaded, false);
      expect(db.reads, 0);
      gate.completeError(StateError('LOCAL FIXTURE failed pending write'));
      await failed;
      expect((await load)!.single.id, inboxIdA);
      expect(db.reads, 1);
    },
  );

  test(
    'failed write preserves serialization of later saves and does not block another owner',
    () async {
      final db = _Database();
      final cache = SqliteInboxCache(db);
      await cache.save(inboxOwnerA, [inboxFixture(inboxIdA)]);
      final first = Completer<void>();
      final second = Completer<void>();
      var aWrites = 0;
      db.beforeWrite = (owner) {
        if (owner != inboxOwnerA) return Future.value();
        aWrites++;
        return aWrites == 1 ? first.future : second.future;
      };
      final failed = expectLater(cache.save(inboxOwnerA, []), throwsStateError);
      final saved = cache.save(inboxOwnerA, [
        inboxFixture(inboxIdA, readAt: inboxReadTime),
      ]);
      final loaded = cache.load(inboxOwnerA);
      await cache.save(inboxOwnerB, [inboxFixture(inboxIdB)]);
      expect((await cache.load(inboxOwnerB))!.single.id, inboxIdB);
      expect(aWrites, 1);
      first.completeError(StateError('LOCAL FIXTURE first write fails'));
      await failed;
      await Future<void>.delayed(Duration.zero);
      expect(aWrites, 2);
      second.complete();
      await saved;
      expect((await loaded)!.single.readAt, inboxReadTime);
      expect(db.reads, 2);
    },
  );

  test(
    'delayed cache recovery preserves newer server rows and a concurrently confirmed read',
    () async {
      final cache = _Cache()
        ..failLoad = true
        ..failSave = true;
      final source = FakeInboxSource();
      final controller = InboxController(
        ownerId: inboxOwnerA,
        source: source,
        cache: cache,
      );
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.state.messages, hasLength(2));
      final readGate = Completer<DateTime>();
      source.markOverride = (_, _) => readGate.future;
      final marking = controller.markOpened(inboxIdA);
      final loadGate = Completer<List<InboxMessage>?>();
      cache.loadOverride = (_) => loadGate.future;
      source.failFetch = true;
      final retry = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      readGate.complete(inboxReadTime);
      expect(await marking, true);
      loadGate.complete([
        inboxFixture(
          inboxIdA,
          readAt: inboxReadTime.subtract(const Duration(hours: 1)),
        ),
      ]);
      await retry;
      expect(cache.loads, 2);
      expect(controller.state.message(inboxIdA)!.readAt, inboxReadTime);
      expect(controller.state.message(inboxIdB)!.isUnread, true);
      expect(controller.state.messages, hasLength(2));
      // A recovered read does not prove the newer receipt was durably saved.
      expect(controller.state.cacheError, isNotNull);
      expect(controller.state.syncError, isNotNull);
    },
  );

  test(
    'cache recovery rejects a stale owner while controller disposal is still pending',
    () async {
      final cache = _Cache()..failLoad = true;
      final source = _Source()..failFetch = true;
      final controller = InboxController(
        ownerId: inboxOwnerA,
        source: source,
        cache: cache,
      );
      addTearDown(controller.dispose);
      await controller.start();
      final gate = Completer<List<InboxMessage>?>();
      cache.loadOverride = (_) => gate.future;
      final retry = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      source.owner = inboxOwnerB;
      gate.complete([inboxFixture(inboxIdA)]);
      await retry;
      expect(controller.state.messages, isEmpty);
      expect(source.fetches, [inboxOwnerA]);
      expect(cache.encoded, isEmpty);
    },
  );

  test(
    'Retry restores offline cache after same-owner auth restoration',
    () async {
      final cache = _Cache();
      await cache.save(inboxOwnerA, [inboxFixture(inboxIdA)]);
      final source = _Source()
        ..owner = inboxOwnerB
        ..failFetch = true;
      final controller = InboxController(
        ownerId: inboxOwnerA,
        source: source,
        cache: cache,
      );
      addTearDown(controller.dispose);
      await controller.start();
      expect(cache.loads, 0);
      source.owner = inboxOwnerA;
      await controller.refresh();
      expect(cache.loads, 1);
      expect(controller.state.message(inboxIdA), isNotNull);
      expect(source.marks, isEmpty);
    },
  );

  test(
    'recovered cache persists the newer confirmed in-memory snapshot while fetch is offline',
    () async {
      final cache = _Cache()
        ..failLoad = true
        ..failSave = true;
      final source = FakeInboxSource();
      final controller = InboxController(
        ownerId: inboxOwnerA,
        source: source,
        cache: cache,
      );
      addTearDown(controller.dispose);
      await controller.start();
      await controller.markOpened(inboxIdA);
      cache.failSave = false;
      cache.loadOverride = (_) async => [inboxFixture(inboxIdA)];
      source.failFetch = true;
      await controller.refresh();
      expect(controller.state.messages, hasLength(2));
      expect(controller.state.message(inboxIdA)!.readAt, inboxReadTime);
      expect(controller.state.cacheError, isNull);
      cache.loadOverride = null;
      cache.failLoad = false;
      final durable = (await cache.load(inboxOwnerA))!;
      expect(durable, hasLength(2));
      expect(durable.first.readAt, inboxReadTime);
      expect(durable.last.isUnread, true);
    },
  );

  test(
    'resume coalesces Retry and reloads recovered owner cache while offline',
    () async {
      final cache = _Cache();
      await cache.save(inboxOwnerA, [inboxFixture(inboxIdA)]);
      cache.failLoad = true;
      final source = FakeInboxSource()..failFetch = true;
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(
            AppUser(
              id: inboxOwnerA,
              createdAt: DateTime.utc(2026),
              isAnonymous: true,
            ),
          ),
          inboxSourceProvider.overrideWithValue(source),
          inboxCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(inboxProvider.notifier);
      await controller.start();
      expect(cache.loads, 1);
      cache.failLoad = false;
      container.read(appResumedSignalProvider.notifier).state++;
      await controller.refresh();
      expect(cache.loads, 2);
      expect(controller.state.message(inboxIdA), isNotNull);
      expect(controller.state.hasUnread, true);
      expect(controller.state.cacheError, isNull);
      expect(source.marks, isEmpty);
    },
  );
}
