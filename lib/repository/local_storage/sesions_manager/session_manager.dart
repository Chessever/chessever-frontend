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
    final session = auth.currentSession;
    final user = auth.currentUser;

    // Presence of a session = authenticated. The access token may currently be
    // expired with a refresh pending or temporarily failing (e.g. no network /
    // DNS). The Supabase SDK keeps the session on transient/retryable failures
    // and refreshes once connectivity returns; it only drops the session and
    // emits `signedOut` when the refresh token is DEFINITIVELY invalid
    // (revoked) — see gotrue _callRefreshToken: an AuthRetryableFetchException
    // does NOT remove the session. So we must NOT gate on token expiry here:
    // doing so dumps an authenticated user on the login screen the moment a
    // refresh hiccups (observed: cold start with a DNS blip →
    // AuthRetryableFetchException → bounced to /auth_screen).
    //
    // We also never initiate our own refresh or recoverSession() — the SDK is
    // the single refresh authority. A competing refresh can replay an
    // already-rotated token and trip GoTrue reuse-detection, which revokes the
    // whole session family and causes a *real* signedOut (the daily-logout bug).
    return session != null && user != null;
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
