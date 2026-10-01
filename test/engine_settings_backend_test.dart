import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/engine_settings/engine_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> _signIn(SupabaseClient client, String userId) async {
  await client.auth.recoverSession(
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
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ).toJson(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'mocked PostgREST patch omits unrelated settings and local surfaces',
    () async {
      final requests = <http.Request>[];
      final row = <String, dynamic>{
        'user_id': 'account-a',
        'search_time_index': 0,
        'principal_variation_index': 1,
        'raw_pgn_mode': true,
        'updated_at': '2026-01-01T00:00:00Z',
      };
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          expect(request.url.path, '/rest/v1/user_engine_settings');
          if (request.method == 'GET') {
            expect(request.url.queryParameters['user_id'], 'eq.account-a');
            return http.Response(
              jsonEncode([row]),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          expect(request.method, 'POST');
          expect(request.url.queryParameters['on_conflict'], 'user_id');
          expect(request.headers['Prefer'], contains('missing=default'));
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload.keys.toSet(), {
            'user_id',
            'search_time_index',
            'updated_at',
          });
          expect(payload['search_time_index'], 2);
          row.addAll(payload);
          return http.Response(
            jsonEncode(row),
            201,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await _signIn(client, 'account-a');
      final backend = SupabaseEngineSettingsBackend(client);
      expect((await backend.fetch('account-a'))!.fields['searchTimeIndex'], 0);
      final saved = await backend.save('account-a', {
        'searchTimeIndex': 2,
        'showEngineGaugeOnBoard': false,
      }, DateTime.utc(2026, 2));
      expect(saved.fields['searchTimeIndex'], 2);
      expect(saved.fields['principalVariationIndex'], 1);
      expect(saved.fields, isNot(contains('showEngineGaugeOnBoard')));
      expect(row['raw_pgn_mode'], true);
      expect(saved.updatedAt, DateTime.utc(2026, 2));
      expect(requests, hasLength(2));

      await _signIn(client, 'account-b');
      await expectLater(
        backend.save('account-a', {
          'searchTimeIndex': 3,
        }, DateTime.utc(2026, 3)),
        throwsStateError,
      );
      await expectLater(backend.fetch('account-a'), throwsStateError);
      expect(
        requests,
        hasLength(2),
        reason: 'No request with a different account',
      );
    },
  );

  test(
    'account switch during fetch rejects late previous-account response',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          started.complete();
          await release.future;
          return http.Response(
            jsonEncode([
              {'search_time_index': 2, 'updated_at': '2026-01-01T00:00:00Z'},
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await _signIn(client, 'account-a');
      final fetching = SupabaseEngineSettingsBackend(client).fetch('account-a');
      await started.future;
      await _signIn(client, 'account-b');
      final assertion = expectLater(fetching, throwsStateError);
      release.complete();
      await assertion;
    },
  );
}
