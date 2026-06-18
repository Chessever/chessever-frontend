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

  /// How long we let the SDK's own auto-refresh settle before reporting a
  /// not-logged-in result on cold start. The SDK fires an immediate refresh
  /// tick during Supabase.initialize()/on resume; this just avoids flashing the
  /// auth screen while that in-flight refresh lands.
  static const _sdkRefreshGrace = Duration(seconds: 3);
  static const _sdkRefreshPoll = Duration(milliseconds: 250);

  Future<bool> _isLoggedInInternal() async {
    final auth = Supabase.instance.client.auth;

    // Valid non-expired session — user is logged in.
    final session = auth.currentSession;
    final user = auth.currentUser;
    if (user != null && session != null && !session.isExpired) {
      return true;
    }

    // We have a session whose access token is expired. Do NOT initiate our own
    // refresh here, and do NOT replay a token from our SharedPreferences backup
    // via recoverSession(). The Supabase SDK's auto-refresh (started inside
    // Supabase.initialize() and again on app resume) is the single owner of
    // token refresh and dedupes concurrent calls through its own lock.
    //
    // Initiating a second refresh — or replaying a token from our backup store,
    // which can lag behind the SDK's latest rotation — races the SDK and may
    // present an already-rotated refresh token. GoTrue treats that as refresh
    // token reuse and REVOKES THE ENTIRE SESSION FAMILY, after which the SDK's
    // next auto-refresh fails and emits a `signedOut` event: a forced, daily
    // logout for active users. (Confirmed in production: ~1k "two refresh
    // tokens revoked for one session in the same second" events.)
    //
    // So we only OBSERVE the SDK: give its in-flight refresh a brief, bounded
    // window to complete, then report the result. We never clear storage or
    // sign out here — if the refresh lands moments later, onAuthStateChange
    // (tokenRefreshed) flips the app to authenticated reactively.
    if (session != null) {
      final deadline = _sdkRefreshGrace.inMilliseconds ~/
          _sdkRefreshPoll.inMilliseconds;
      for (var i = 0; i < deadline; i++) {
        final s = auth.currentSession;
        if (s != null && !s.isExpired) return true;
        await Future.delayed(_sdkRefreshPoll);
      }
      return auth.currentSession?.isExpired == false;
    }

    // No session in the SDK at all — a fresh login is genuinely required.
    return false;
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
