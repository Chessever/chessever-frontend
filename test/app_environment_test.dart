import 'package:chessever2/config/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppEnvironment Supabase isolation', () {
    test('production accepts only the production project', () {
      expect(
        () => AppEnvironment.validateSupabaseUrlForFlavor(
          'https://oelbsuggrzyqwzmvidju.supabase.co',
          AppFlavor.production,
        ),
        returnsNormally,
      );
      expect(
        () => AppEnvironment.validateSupabaseUrlForFlavor(
          'https://odmekzlfunfocvedqusl.supabase.co',
          AppFlavor.production,
        ),
        throwsStateError,
      );
    });

    test('test accepts only the writable test project', () {
      expect(
        () => AppEnvironment.validateSupabaseUrlForFlavor(
          'https://odmekzlfunfocvedqusl.supabase.co',
          AppFlavor.test,
        ),
        returnsNormally,
      );
      expect(
        () => AppEnvironment.validateSupabaseUrlForFlavor(
          'https://oelbsuggrzyqwzmvidju.supabase.co',
          AppFlavor.test,
        ),
        throwsStateError,
      );
    });

    test('rejects lookalike and insecure hosts', () {
      for (final url in <String>[
        'http://odmekzlfunfocvedqusl.supabase.co',
        'https://odmekzlfunfocvedqusl.supabase.co.example.com',
        'not-a-url',
      ]) {
        expect(
          () =>
              AppEnvironment.validateSupabaseUrlForFlavor(url, AppFlavor.test),
          throwsStateError,
        );
      }
    });
  });
}
