import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Helper function to get environment variables.
/// Prefer --dart-define/--dart-define-from-file values in every build mode.
/// Local debug can fall back to dotenv only when a private workflow loads it.
String _getEnv(String key) {
  final releaseValue = String.fromEnvironment(key);
  if (releaseValue.isNotEmpty) {
    return releaseValue;
  }

  if (kDebugMode) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw Exception('Missing env variable in .env file: $key');
    }
    return value;
  } else {
    // In production, CodeMagic injects environment variables
    return releaseValue;
  }
}

final supabaseProvider = Provider<SupabaseClient>((ref) {
  return SupabaseClient(_getEnv('SUPABASE_URL'), _getEnv('SUPABASE_ANON_KEY'));
});
