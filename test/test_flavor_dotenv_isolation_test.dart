import 'package:chessever2/config/app_environment.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/services/cloudflare_gif_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => AppEnvironment.configure(AppFlavor.test));

  test('test Gamebase works without initializing the shared dotenv file', () {
    final dio = Dio();
    addTearDown(dio.close);
    expect(GamebaseRepository(dio).hasApiKey, isFalse);
  });

  test('test Gamebase ignores a key left in the shared dotenv map', () {
    dotenv.testLoad(fileInput: 'GAMEBASE_API_KEY=shared-placeholder-key');
    addTearDown(dotenv.clean);
    final dio = Dio();
    addTearDown(dio.close);
    expect(GamebaseRepository(dio).hasApiKey, isFalse);
  });

  test(
    'an unconfigured test Gamebase request never reaches transport',
    () async {
      dotenv.testLoad(fileInput: 'GAMEBASE_API_KEY=shared-placeholder-key');
      addTearDown(dotenv.clean);
      var requests = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests++;
              handler.reject(DioException(requestOptions: options));
            },
          ),
        );
      addTearDown(dio.close);
      await expectLater(
        GamebaseRepository(dio).getMiniatures(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'configuration failure',
            contains('GAMEBASE_TEST_BASE_URL'),
          ),
        ),
      );
      expect(requests, 0);
    },
  );

  test('test GIF export ignores a shared dotenv service URL', () {
    dotenv.testLoad(
      fileInput: 'CHESSEVER_CLOUDFLARE_API_BASE=https://shared.example.invalid',
    );
    addTearDown(dotenv.clean);
    expect(
      CloudflareGifService.fromEnvironment,
      throwsA(isA<CloudflareGifException>()),
    );
  });
}
