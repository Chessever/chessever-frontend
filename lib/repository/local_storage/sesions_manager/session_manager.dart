import 'dart:convert';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final sessionManagerProvider = Provider<SessionManager>((ref) {
  return SessionManager();
});

class SessionManager {
  static const _keyPersistSession = 'supabase_session';

  /// Save the session as JSON string
  Future<void> saveSession(Session session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPersistSession, jsonEncode(session.toJson()));
  }

  /// Clear session from storage and Supabase
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPersistSession);
    await Supabase.instance.client.auth.signOut();
  }

  /// Check current login state
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionStr = prefs.getString(_keyPersistSession);

    if (sessionStr == null) return false;
    try {
      final response = await Supabase.instance.client.auth.recoverSession(
        sessionStr,
      ); 
      return response.user != null;
    } catch (_) {
      return false;
    }
  }
}
