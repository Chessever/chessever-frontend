import 'package:chessever2/config/app_environment.dart';

/// Test builds never inherit a production Gamebase endpoint or credential.
abstract final class GamebaseEnvironment {
  static String get baseUrl => AppEnvironment.isTest
      ? validateTestBase(const String.fromEnvironment('GAMEBASE_TEST_BASE_URL'))
      : 'https://service.chessever.com';

  static String get testApiKey =>
      const String.fromEnvironment('GAMEBASE_TEST_API_KEY');

  /// Missing configuration is represented as empty until a request is made.
  /// This keeps the rest of the interface usable without contacting a service.
  static String validateTestBase(String value) {
    final uri = Uri.tryParse(value.trim());
    if (value.trim().isEmpty) return '';
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['http', 'https'].contains(uri.scheme)) {
      return '';
    }
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.+$'), '');
    final local = ['localhost', '127.0.0.1', '::1', '[::1]'].contains(host);
    if (!local && uri.scheme != 'https') return '';
    if (host == 'chessever.com' ||
        host.endsWith('.chessever.com') ||
        (host.endsWith('.supabase.co') &&
            host != '${AppEnvironment.testSupabaseProjectRef}.supabase.co')) {
      return '';
    }
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }
}
