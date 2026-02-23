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

    // The Supabase SDK recovers and refreshes the persisted session during
    // Supabase.initialize(). By this point, currentSession reflects the SDK's
    // best-effort recovery. We must avoid calling refreshSession() with an
    // explicit (potentially stale) refresh token — rotating refresh tokens mean
    // the SDK may have already consumed it, and a second attempt would fail and
    // leave us in an inconsistent state.

    final currentSession = auth.currentSession;
    final currentUser = auth.currentUser;

    // Valid non-expired session — user is logged in.
    if (currentUser != null &&
        currentSession != null &&
        !currentSession.isExpired) {
      return true;
    }

    // Expired session in memory. Try ONE refresh using the SDK's latest state
    // (no explicit token — avoids race with SDK's own auto-refresh).
    if (currentSession != null && currentSession.isExpired) {
      try {
        final refreshed = await auth.refreshSession();
        final refreshedSession = refreshed.session;
        final refreshedUser = refreshed.user;
        if (refreshedUser != null &&
            refreshedSession != null &&
            !refreshedSession.isExpired) {
          await saveSession(refreshedSession, refreshedUser);
          return true;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Session refresh failed: $e');
        }
        // IMPORTANT: Do NOT call signOut here. The refresh token may have been
        // consumed by a concurrent SDK refresh. Calling signOut(local) would
        // nuke the SDK's freshly refreshed session and fire a signedOut event,
        // causing a false logout. Just clean our own backup storage silently.
        await _clearOwnStorageQuietly();
      }
    }

    // No in-memory session. The SDK either had nothing to recover or recovery
    // failed during init. Try our own SharedPreferences backup as last resort
    // (covers edge case where SafeSupabaseLocalStorage fell back to memory).
    if (currentSession == null) {
      final prefs = await SharedPreferencesService.instance.ensureInitialized();
      if (prefs != null) {
        final sessionStr = prefs.getString(_keyPersistSession);
        if (sessionStr != null) {
          try {
            final response = await auth.recoverSession(sessionStr);
            final session = response.session;
            final user = response.user;
            if (user != null && session != null && !session.isExpired) {
              await saveSession(session, user);
              return true;
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ Local session recovery failed: $e');
            }
          }
          // Recovery failed — clean our stale copy silently.
          await _clearOwnStorageQuietly();
        }
      }
    }

    return false;
  }

  /// Silently clears our own session keys without calling signOut or firing
  /// auth events. This is safe to call during session checks.
  Future<void> _clearOwnStorageQuietly() async {
    final prefs = await SharedPreferencesService.instance.ensureInitialized();
    if (prefs != null) {
      await prefs.remove(_keyPersistSession);
      await prefs.remove(_keyPersistUser);
    }
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
