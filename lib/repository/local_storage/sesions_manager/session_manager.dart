import 'dart:convert';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/screens/authentication/auth_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final sessionManagerProvider = Provider<SessionManager>((ref) {
  return SessionManager(ref);
});

class SessionManager {
  SessionManager(this.ref);

  final Ref ref;

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

  /// Clear only local storage without calling signOut
  /// Used when responding to auth state changes to avoid infinite loops
  Future<void> clearLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPersistSession);
    await prefs.remove(_keyPersistUser);
    // Keep the auth notifier alive but reset its state when clearing storage
    ref.read(authScreenProvider.notifier).reset();
    await ref.read(countryDropdownProvider.notifier).clearSelection();
  }

  /// Check current login state and recover session if valid
  /// Note: The auth state stream (authStateProvider) is the primary source of truth
  /// This method is only used for initial checks in splash screen
  Future<bool> isLoggedIn() async {
    // First check if Supabase already has an active session
    final currentSession = Supabase.instance.client.auth.currentSession;
    if (currentSession != null) {
      return true;
    }

    // If no current session, try to recover from local storage
    final prefs = await SharedPreferences.getInstance();
    final sessionStr = prefs.getString(_keyPersistSession);

    if (sessionStr == null) return false;

    try {
      final response = await Supabase.instance.client.auth.recoverSession(
        sessionStr,
      );

      final user = response.user;
      if (user != null && response.session != null) {
        // Session recovered successfully - save updated session
        await saveSession(response.session!, user);
        return true;
      }

      // Session invalid - clear local storage
      await clearLocalStorage();
      return false;
    } catch (e) {
      // Session recovery failed - clear local storage
      await clearLocalStorage();
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
