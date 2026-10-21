import 'package:chessever2/config/app_environment.dart';
import 'package:chessever2/config/gamebase_environment.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Production requests carry only the public project key and the caller's
/// session. The proxy owns the upstream Gamebase credential.
class GamebaseConnection {
  GamebaseConnection({String? baseUrl, String? apiKey})
    : baseUrl = baseUrl ?? GamebaseEnvironment.baseUrl,
      _developerKey = kDebugMode || AppEnvironment.isTest
          ? (apiKey ??
                    (AppEnvironment.isTest
                        ? GamebaseEnvironment.testApiKey
                        : ''))
                .trim()
          : '';

  final String baseUrl;
  final String _developerKey;

  String get _publicKey {
    if (AppEnvironment.isTest) return '';
    const compiled = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (compiled.isNotEmpty) return compiled;
    if (kDebugMode && !AppEnvironment.isTest && dotenv.isInitialized) {
      return dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';
    }
    return '';
  }

  bool get isConfigured =>
      baseUrl.isNotEmpty && (_developerKey.isNotEmpty || _publicKey.isNotEmpty);

  Map<String, String> get headers {
    if (baseUrl.isEmpty) {
      throw StateError(
        'Set GAMEBASE_TEST_BASE_URL to the isolated test service.',
      );
    }
    String? accessToken;
    try {
      accessToken = Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      // Configuration tests and signed-out clients have no session.
    }
    final publicKey = _publicKey;
    if (_developerKey.isEmpty && publicKey.isEmpty) {
      throw StateError('Missing SUPABASE_ANON_KEY for the Gamebase proxy.');
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (_developerKey.isNotEmpty) 'X-API-Key': _developerKey,
      if (_developerKey.isEmpty) 'apikey': publicKey,
      if (accessToken != null || _developerKey.isEmpty)
        'Authorization': 'Bearer ${accessToken ?? publicKey}',
      ...RewardedSession.instance.headers,
    };
  }
}
