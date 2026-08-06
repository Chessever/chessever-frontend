enum AppFlavor { production, test }

/// Process-wide environment boundary for the two independently installable
/// ChessEver apps.
///
/// The native build selects an entrypoint. The entrypoint configures this
/// class before any SDK is initialized, so a test binary cannot silently fall
/// back to production when a CI variable is missing.
abstract final class AppEnvironment {
  static const String productionSupabaseProjectRef = 'oelbsuggrzyqwzmvidju';
  static const String testSupabaseProjectRef = 'odmekzlfunfocvedqusl';

  static AppFlavor _flavor = AppFlavor.production;
  static bool _configured = false;

  static AppFlavor get flavor => _flavor;
  static bool get isTest => _flavor == AppFlavor.test;

  static String get authRedirectScheme =>
      isTest ? 'com.chessever.app.test' : 'com.chessever.app';

  static String get expectedSupabaseProjectRef =>
      isTest ? testSupabaseProjectRef : productionSupabaseProjectRef;

  static void configure(AppFlavor flavor) {
    if (_configured && _flavor != flavor) {
      throw StateError(
        'App environment was already configured as ${_flavor.name}; '
        'refusing to switch to ${flavor.name}.',
      );
    }
    _flavor = flavor;
    _configured = true;
  }

  static void validateSupabaseUrl(String value) {
    validateSupabaseUrlForFlavor(value, flavor);
  }

  static void validateSupabaseUrlForFlavor(String value, AppFlavor flavor) {
    final uri = Uri.tryParse(value);
    final expectedRef =
        flavor == AppFlavor.test
            ? testSupabaseProjectRef
            : productionSupabaseProjectRef;
    final expectedHost = '$expectedRef.supabase.co';
    if (uri == null || uri.scheme != 'https' || uri.host != expectedHost) {
      throw StateError(
        '${flavor.name} app requires https://$expectedHost; got $value',
      );
    }
  }
}
