import 'dart:convert';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final sessionManagerProvider = Provider<SessionManager>((ref) {
  return SessionManager();
});

class SessionManager {
  static const _keyPersistSession = 'supabase_session';
  static const _keyPersistUser = 'supabase_user';

  /// Save the session as JSON string
  Future<void> saveSession(Session session, User user) async {
    print('Saving session: ${session.toJson()}');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPersistSession, jsonEncode(session.toJson()));
    await prefs.setString(_keyPersistUser, jsonEncode(user.toJson()));

    print('Session saved: ${session.toJson()}');
  }

  /// Clear session from storage and Supabase
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPersistSession);
    await prefs.remove(_keyPersistUser);

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

  Future<String?> getUserInitials() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString(_keyPersistUser);
    if (userStr == null) return null;

    final json = jsonDecode(userStr);
    final fullName = json['user_metadata']?['full_name'] ?? json['fullName'];
    if (fullName == null) return null;

    final parts = fullName.trim().split(' ');
    if (parts.isEmpty) return null;
    if (parts.length == 1) return parts.first[0].toUpperCase();

    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
