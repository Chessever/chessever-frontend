import 'dart:async';
import 'dart:convert';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MemoryCache implements AppDatabase {
  final values = <String, String>{};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _signIn(SupabaseClient client, String userId) => client.auth
    .recoverSession(
      jsonEncode(
        Session(
          accessToken: 'test-token',
          refreshToken: 'test-refresh',
          tokenType: 'bearer',
          expiresIn: 3600,
          user: User(
            id: userId,
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: '2026-09-08T00:00:00Z',
          ),
        ).toJson(),
      ),
    )
    .then((_) {});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'raw PGN saves in order to the profile, reloads, and isolates accounts',
    () async {
      final rows = <String, Map<String, dynamic>>{};
      Map<String, dynamic> row(String userId) => rows.putIfAbsent(
        userId,
        () => {
          'id': 'settings-$userId',
          'user_id': userId,
          'raw_pgn_mode': false,
          'created_at': '2026-09-08T00:00:00Z',
          'updated_at': '2026-09-08T00:00:00Z',
        },
      );
      final writes = <Map<String, dynamic>>[];
      final firstWriteStarted = Completer<void>();
      final releaseFirstWrite = Completer<void>();
      var offline = false;
      final client = SupabaseClient(
        'https://placeholder.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/user_engine_settings');
          if (offline) {
            return http.Response(
              '{"message":"offline"}',
              400,
              request: request,
            );
          }
          if (request.method == 'GET') {
            final userId = request.url.queryParameters['user_id']!.replaceFirst(
              'eq.',
              '',
            );
            return http.Response(
              jsonEncode([row(userId)]),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          expect(request.method, 'POST');
          expect(request.url.queryParameters['on_conflict'], 'user_id');
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          writes.add(payload);
          if (writes.length == 1) {
            firstWriteStarted.complete();
            await releaseFirstWrite.future;
          }
          row(payload['user_id'] as String).addAll(payload);
          return http.Response('', 201, request: request);
        }),
      );
      addTearDown(client.dispose);
      await _signIn(client, 'user-a');
      final cache = _MemoryCache();
      final container = ProviderContainer(
        overrides: [
          boardSettingsClientProvider.overrideWithValue(client),
          boardSettingsCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);
      await container.read(boardSettingsProviderNew.future);
      final notifier = container.read(boardSettingsProviderNew.notifier);
      var firstCompleted = false;
      final on = notifier
          .toggleRawPgnMode(true)
          .then((_) => firstCompleted = true);
      await firstWriteStarted.future;
      final off = notifier.toggleRawPgnMode(false);
      expect(
        firstCompleted,
        isFalse,
        reason: 'Future must await the remote write',
      );
      expect(writes, hasLength(1));
      releaseFirstWrite.complete();
      await Future.wait([on, off]);
      expect(writes.map((p) => p['raw_pgn_mode']), [true, false]);
      expect(writes.every((p) => p['user_id'] == 'user-a'), isTrue);
      await notifier.toggleRawPgnMode(true);
      await notifier.refresh();
      expect(
        container.read(boardSettingsProviderNew).requireValue.rawPgnMode,
        isTrue,
      );
      expect(
        jsonDecode(cache.values['cached_board_settings:user-a']!)['rawPgnMode'],
        isTrue,
      );

      // An account switch reloads that account's profile instead of leaking A's ON.
      await _signIn(client, 'user-b');
      await container.pump();
      await container.read(boardSettingsProviderNew.future);
      expect(
        container.read(boardSettingsProviderNew).requireValue.rawPgnMode,
        isFalse,
      );
      expect(cache.values.containsKey('cached_board_settings:user-b'), isTrue);
      offline = true;
      await container.read(boardSettingsProviderNew.notifier).refresh();
      expect(
        container.read(boardSettingsProviderNew).requireValue.rawPgnMode,
        isFalse,
      );
      expect(row('user-a')['raw_pgn_mode'], isTrue);
    },
  );
}
