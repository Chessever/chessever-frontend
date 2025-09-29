import 'dart:convert';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/screens/authentication/auth_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final sessionManagerProvider = Provider<_SessionManager>((ref) {
  return _SessionManager(ref);
});

class _SessionManager {
  _SessionManager(this.ref);

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

  /// Clear session from storage and Supabase
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPersistSession);
    await prefs.remove(_keyPersistUser);
    ref.read(authRepositoryProvider).signOut();
    ref.invalidate(authScreenProvider);
    await ref.read(countryDropdownProvider.notifier).clearSelection();
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

      final user = response.user;
      if (user != null && response.session != null) {
        await saveSession(response.session!, user);
      }

      return user != null && response.session != null;
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
