import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Helper function to get environment variables
/// In debug mode: reads from .env file via dotenv
/// In production: reads from CodeMagic environment variables
String _getEnv(String key) {
  if (kDebugMode) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw Exception('Missing env variable in .env file: $key');
    }
    return value;
  } else {
    // In production, CodeMagic injects environment variables
    return String.fromEnvironment(key);
  }
}

final supabaseProvider = Provider<SupabaseClient>((ref) {
  return SupabaseClient(_getEnv('SUPABASE_URL'), _getEnv('SUPABASE_ANON_KEY'));
});
