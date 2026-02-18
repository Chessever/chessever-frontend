import 'dart:convert';
import 'dart:async';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/authentication/auth_screen_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final sessionManagerProvider = Provider<SessionManager>((ref) {
  return SessionManager(ref);
});

class SessionManager {
  SessionManager(this.ref);

  final Ref ref;
  Completer<bool>? _loginCheckCompleter;

  static const _keyPersistSession = 'supabase_session';
  static const _keyPersistUser = 'supabase_user';

  /// Save the session as JSON string
  Future<void> saveSession(Session session, User user) async {
    final prefs = await SharedPreferencesService.instance.ensureInitialized();
    if (prefs == null) {
      debugPrint('⚠️ Cannot save session: SharedPreferences unavailable');
      return;
    }

    await prefs.setString(_keyPersistSession, jsonEncode(session.toJson()));
    await prefs.setString(_keyPersistUser, jsonEncode(user.toJson()));
  }

  /// Clear only local storage without calling signOut
  /// Used when responding to auth state changes to avoid infinite loops
  Future<void> clearLocalStorage() async {
    final prefs = await SharedPreferencesService.instance.ensureInitialized();
    if (prefs != null) {
      await prefs.remove(_keyPersistSession);
      await prefs.remove(_keyPersistUser);
    }
    // Keep the auth notifier alive but reset its state when clearing storage
    ref.read(authScreenProvider.notifier).reset();
    // Clear local country cache only - Supabase data persists for next login
    ref.read(countryDropdownProvider.notifier).clearLocalOnly();
  }

  /// Clear ALL user data from SharedPreferences
  /// Used when account is deleted - wipes everything for a clean slate
  Future<void> clearAllUserData() async {
    final prefs = await SharedPreferencesService.instance.ensureInitialized();
    if (prefs != null) {
      // Clear everything - account deletion means complete data wipe
      // This ensures no data leaks between accounts and fresh start for new users
      await prefs.clear();
    }

    // Reset provider states
    ref.read(authScreenProvider.notifier).reset();
    ref.read(countryDropdownProvider.notifier).clearLocalOnly();
  }

  /// Check current login state and recover session if valid
  /// Note: The auth state stream (authStateProvider) is the primary source of truth
  /// This method is only used for initial checks in splash screen
  Future<bool> isLoggedIn() async {
    final inFlight = _loginCheckCompleter;
    if (inFlight != null) {
      return inFlight.future;
    }

    final completer = Completer<bool>();
    _loginCheckCompleter = completer;

    () async {
      try {
        final result = await _isLoggedInInternal();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        if (identical(_loginCheckCompleter, completer)) {
          _loginCheckCompleter = null;
        }
      }
    }();

    return completer.future;
  }

  Future<bool> _isLoggedInInternal() async {
    final auth = Supabase.instance.client.auth;

    // First check if Supabase already has an active, non-expired session.
    final currentSession = auth.currentSession;
    if (currentSession != null) {
      if (!currentSession.isExpired) {
        return true;
      }

      // Expired session found in memory. Try refresh before declaring unauthenticated.
      try {
        final refreshed = await auth.refreshSession(
          currentSession.refreshToken,
        );
        final refreshedUser = refreshed.user;
        final refreshedSession = refreshed.session;
        if (refreshedUser != null &&
            refreshedSession != null &&
            !refreshedSession.isExpired) {
          await saveSession(refreshedSession, refreshedUser);
          return true;
        }
      } catch (_) {
        // Ignore and fall through to local recovery/cleanup.
      }

      // Ensure stale token is removed so app requests don't send expired JWTs.
      await _clearStaleSession();
      return false;
    }

    // If no current session, try to recover from local storage
    final prefs = await SharedPreferencesService.instance.ensureInitialized();
    if (prefs == null) return false;

    final sessionStr = prefs.getString(_keyPersistSession);

    if (sessionStr == null) return false;

    try {
      final response = await auth.recoverSession(sessionStr);

      var user = response.user;
      var session = response.session;

      if (user != null && session != null && session.isExpired) {
        // Recovered session exists but access token is already expired. Refresh it.
        final refreshed = await auth.refreshSession(session.refreshToken);
        user = refreshed.user;
        session = refreshed.session;
      }

      if (user != null && session != null && !session.isExpired) {
        await saveSession(session, user);
        return true;
      }

      // Session invalid - clear local storage
      await _clearStaleSession();
      return false;
    } catch (e) {
      // Session recovery failed - clear local storage
      await _clearStaleSession();
      return false;
    }
  }

  Future<void> _clearStaleSession() async {
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Best effort. Local storage cleanup below is the critical step.
    }
    await clearLocalStorage();
  }

  Future<String?> getUserInitials() async {
    final prefs = await SharedPreferencesService.instance.ensureInitialized();
    if (prefs == null) return null;

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
