// Regressions adapted from the independent review: synthetic local fixtures only.
import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/inbox/inbox_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'inbox_fakes.dart';

class _MemoryDatabase implements AppDatabase {
  final values = <String, String>{};
  bool failWrites = false;
  int reads = 0;
  @override
  Future<void> setCache({
    required String key,
    required String value,
    String? userId,
  }) async {
    if (failWrites) throw StateError('LOCAL FIXTURE transient write failure');
    values['$key/$userId'] = value;
  }

  @override
  Future<CacheEntry?> getCache({
    required String key,
    String? userId,
    Duration? maxAge,
  }) async {
    reads++;
    final value = values['$key/$userId'];
    return value == null
        ? null
        : CacheEntry(value: value, cachedAt: DateTime.utc(2026));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _sessionJson(String token, int expiry) => {
  'access_token':
      '${base64Url.encode(utf8.encode(jsonEncode({'alg': 'none', 'typ': 'JWT'}))).replaceAll('=', '')}.${base64Url.encode(utf8.encode(jsonEncode({'sub': inboxOwnerA, 'exp': expiry, 'fixture': token}))).replaceAll('=', '')}.LOCAL-FIXTURE-SIGNATURE',
  'refresh_token': 'LOCAL-FIXTURE-REFRESH',
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': expiry,
  'user': User(
    id: inboxOwnerA,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-09-30T00:00:00Z',
    isAnonymous: true,
  ).toJson(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'last good cache remains readable after one handled save failure and offline account return',
    () async {
      final db = _MemoryDatabase();
      final cache = SqliteInboxCache(db);
      await cache.save(inboxOwnerA, [inboxFixture(inboxIdA)]);
      db.failWrites = true;
      await expectLater(
        cache.save(inboxOwnerA, [
          inboxFixture(inboxIdA),
          inboxFixture(inboxIdB),
        ]),
        throwsStateError,
      );
      db.failWrites = false;
      // Same app process: inboxCacheProvider survives A->B->A controller recreation.
      final source = FakeInboxSource()..failFetch = true;
      final controller = InboxController(
        ownerId: inboxOwnerA,
        source: source,
        cache: cache,
      );
      addTearDown(controller.dispose);
      await controller.start();
      expect(db.values, hasLength(1));
      expect(
        controller.state.message(inboxIdA),
        isNotNull,
        reason:
            'A prior failed write must not prevent reading the valid persisted snapshot.',
      );
      expect(controller.state.hasUnread, true);
      expect(db.reads, 1);
    },
  );

  test(
    'Retry reloads recovered offline storage after a transient initial load failure',
    () async {
      final cache = FakeInboxCache();
      await cache.save(inboxOwnerA, [inboxFixture(inboxIdA)]);
      cache.failLoad = true;
      final controller = InboxController(
        ownerId: inboxOwnerA,
        source: FakeInboxSource()..failFetch = true,
        cache: cache,
      );
      addTearDown(controller.dispose);
      await controller.start();
      cache.failLoad = false;
      await controller
          .refresh(); // The exact callback wired to cache-error Retry.
      expect(cache.encoded, hasLength(1));
      expect(
        controller.state.message(inboxIdA),
        isNotNull,
        reason:
            'Retry should recover the last durable snapshot when storage recovers while network remains offline.',
      );
      expect(controller.state.cacheError, isNull);
      expect(controller.state.syncError, isNotNull);
    },
  );

  for (final marking in [false, true]) {
    test(
      '${marking ? 'mark' : 'fetch'} succeeds when SDK refreshes an expired restored session for the same owner',
      () async {
        var refreshes = 0;
        var expiredRequests = 0;
        var freshRequests = 0;
        final expiredSession = _sessionJson(
          'LOCAL-FIXTURE-EXPIRED',
          DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60,
        );
        String? freshToken;
        final client = SupabaseClient(
          'http://127.0.0.1:54321',
          'LOCAL-FIXTURE-ANON-KEY',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            late http.Response response;
            if (request.url.path == '/auth/v1/token') {
              refreshes++;
              final refreshed = _sessionJson(
                'LOCAL-FIXTURE-FRESH',
                DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              );
              freshToken = refreshed['access_token'] as String;
              response = http.Response(jsonEncode(refreshed), 200);
            } else if (request.url.path.startsWith('/rest/v1/rpc/')) {
              if (request.headers['authorization'] ==
                  'Bearer ${expiredSession['access_token']}') {
                expiredRequests++;
                response = http.Response(
                  '{"message":"LOCAL FIXTURE expired token","code":"PGRST303"}',
                  401,
                );
              } else {
                freshRequests++;
                response = http.Response(
                  marking
                      ? jsonEncode(inboxReadTime.toIso8601String())
                      : jsonEncode([inboxFixture(inboxIdA).toJson()]),
                  200,
                );
              }
            } else {
              throw StateError('Unexpected LOCAL FIXTURE path');
            }
            return http.Response.bytes(
              response.bodyBytes,
              response.statusCode,
              headers: response.headers,
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        await client.auth.setInitialSession(jsonEncode(expiredSession));
        final source = SupabaseInboxSource(() => client);
        Object? failure;
        try {
          if (marking) {
            expect(await source.markRead(inboxOwnerA, inboxIdA), inboxReadTime);
          } else {
            expect(await source.fetch(inboxOwnerA), hasLength(1));
          }
        } catch (error) {
          failure = error;
        }

        expect(failure, isNull);
        expect(refreshes, 1);
        expect(expiredRequests, 0);
        expect(freshRequests, 1);
        expect(client.auth.currentSession!.accessToken, freshToken);
        // Control: resetting to the same expired fixture, the stock SDK RPC
        // refreshes and succeeds when the adapter's pre-refresh header is absent.
        await client.auth.setInitialSession(jsonEncode(expiredSession));
        final control = await client.rpc(
          marking ? 'mark_editorial_inbox_read' : 'list_editorial_inbox',
          params: marking ? {'p_message_id': inboxIdA} : {'p_limit': 100},
        );
        expect(control, isNotNull);
        expect(refreshes, 2);
        expect(freshRequests, 2);
        expect(
          failure,
          isNull,
          reason:
              'Dispatch must use the refreshed same-account credential, not the expired snapshot.',
        );
      },
    );
  }
}
