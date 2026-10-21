import 'dart:convert';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/repository/gamebase_repository.dart'
    as legacy;
import 'package:chessever2/services/rewarded_premium/rewarded_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    dotenv.testLoad(
      fileInput: '''
SUPABASE_ANON_KEY=public-project-key
GAMEBASE_API_KEY=must-never-leave-the-client
''',
    );
  });
  tearDown(() {
    dotenv.clean();
    RewardedSession.instance.reset();
  });

  void checkRequest(Uri uri, Map<String, dynamic> headers) {
    expect(uri.host, 'oelbsuggrzyqwzmvidju.supabase.co');
    expect(uri.path, '/functions/v1/gamebase-proxy/api/player');
    expect(headers['X-API-Key'], isNull);
    expect(headers['apikey'], 'public-project-key');
    expect(headers['Authorization'], 'Bearer public-project-key');
  }

  test(
    'Dio requests use the proxy and ignore the upstream dotenv key',
    () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              checkRequest(options.uri, options.headers);
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'data': <dynamic>[]},
                ),
              );
            },
          ),
        );
      addTearDown(dio.close);
      final repository = GamebaseRepository(dio);
      expect(repository.hasApiKey, isTrue);
      await repository.getPlayers();
    },
  );

  test('legacy HTTP requests use the same safe connection', () async {
    final client = MockClient((request) async {
      checkRequest(request.url, {
        'apikey': request.headers['apikey'],
        'Authorization': request.headers['authorization'],
        'X-API-Key': request.headers['x-api-key'],
      });
      return http.Response(jsonEncode({'data': <dynamic>[]}), 200);
    });
    addTearDown(client.close);
    await legacy.GamebaseRepository(client: client).getPlayers();
  });

  test('rewarded access is carried through the proxy request', () async {
    final now = DateTime.now();
    RewardedSession.instance.grant(
      expiresAt: now.add(const Duration(minutes: 5)),
      serverNow: now,
    );
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.headers['x-rewarded-session'], isNotEmpty);
            expect(options.headers['X-API-Key'], isNull);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'data': <dynamic>[]},
              ),
            );
          },
        ),
      );
    addTearDown(dio.close);
    await GamebaseRepository(dio).getPlayers();
  });
}
