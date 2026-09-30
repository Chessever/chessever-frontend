import 'package:chessever2/config/gamebase_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'test Gamebase configuration rejects production and malformed targets',
    () {
      for (final value in [
        '',
        'https://service.chessever.com',
        'https://service.chessever.com.',
        'https://www.chessever.com',
        'https://oelbsuggrzyqwzmvidju.supabase.co.',
        'https://another-project.supabase.co',
        'https://chessever.com',
        'https://oelbsuggrzyqwzmvidju.supabase.co',
        'http://public.test',
        'https://user:password@example.test',
        'https://example.test?token=secret',
        'ftp://example.test',
      ]) {
        expect(GamebaseEnvironment.validateTestBase(value), isEmpty);
      }
      expect(
        GamebaseEnvironment.validateTestBase('http://127.0.0.1:8080/'),
        'http://127.0.0.1:8080',
      );
      expect(
        GamebaseEnvironment.validateTestBase('https://gamebase.test.example/'),
        'https://gamebase.test.example',
      );
    },
  );
}
