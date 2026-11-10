import 'dart:convert';

import 'package:chessever2/config/app_environment.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'webview_link.dart';

const webViewAuthStorageKey =
    'sb-${AppEnvironment.productionSupabaseProjectRef}-auth-token';

/// Match the web client's storage contract without sharing OAuth provider
/// credentials. Never put this payload in a URL, header, log or JS channel.
String webViewSessionScript(Uri origin, Session? session) {
  if (!canShareWebViewSession(origin)) {
    throw ArgumentError('Session handoff requires an approved HTTPS origin');
  }
  final payload = session == null
      ? null
      : <String, dynamic>{
          'access_token': session.accessToken,
          'refresh_token': session.refreshToken,
          'expires_at': session.expiresAt,
          'expires_in': session.expiresIn,
          'token_type': session.tokenType,
          'user': session.user.toJson(),
        };
  // Check location in the same JS invocation that writes storage: checking
  // currentUrl in Dart alone would race a redirect to another origin.
  return '''
(() => {
  if (window.location.origin !== ${jsonEncode(origin.origin)}) return false;
  const key = ${jsonEncode(webViewAuthStorageKey)};
  const value = ${jsonEncode(payload == null ? null : jsonEncode(payload))};
  if (value === null) window.localStorage.removeItem(key);
  else window.localStorage.setItem(key, value);
  return true;
})()
''';
}
