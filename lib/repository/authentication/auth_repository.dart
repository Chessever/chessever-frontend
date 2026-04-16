import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform;

import 'package:chessever2/providers/error_logger_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/repository/authentication/model/exceptions.dart';
import 'package:chessever2/repository/local_storage/sesions_manager/session_manager.dart';
import 'package:chessever2/repository/migration/settings_migration_service.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chessever2/e2e/e2e_config.dart';

/// Compile-time environment values injected via `--dart-define`.
const Map<String, String> _releaseEnvValues = {
  'GOOGLE_WEB_CLIENT_ID': String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  ),
  'GOOGLE_IOS_CLIENT_ID': String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  ),
};

final authStateProvider =
    AutoDisposeAsyncNotifierProvider<AuthController, AppAuthState>(
      AuthController.new,
    );

const kAuthRestoreTimeout = Duration(seconds: 8);

class AuthController extends AutoDisposeAsyncNotifier<AppAuthState> {
  AuthController();

  static const List<String> _scopes = ['email', 'profile'];
  static Completer<void>? _googleInitCompleter;

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  late final SupabaseClient _supabase;
  late final SessionManager _sessionManager;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  FutureOr<AppAuthState> build() async {
    _supabase = Supabase.instance.client;
    _sessionManager = ref.read(sessionManagerProvider);

    _startAuthListener();

    // Quick path: SDK already has a valid session from Supabase.initialize().
    final earlySession = _supabase.auth.currentSession;
    final earlyUser = _supabase.auth.currentUser;
    if (earlySession != null && earlyUser != null && !earlySession.isExpired) {
      return AppAuthState.authenticated(AppUser.fromSupabaseUser(earlyUser));
    }

    // Session may be expired or absent — let isLoggedIn() attempt a refresh.
    // The SessionManager no longer calls signOut on failure, so this is safe.
    final loggedIn = await _sessionManager.isLoggedIn().timeout(
      kAuthRestoreTimeout,
      onTimeout: () => false,
    );

    // Re-check the SDK's current state. The onAuthStateChange stream or the
    // refresh inside isLoggedIn() may have updated the session since we started.
    final currentUser = _supabase.auth.currentUser;
    final currentSession = _supabase.auth.currentSession;
    if (loggedIn &&
        currentUser != null &&
        currentSession != null &&
        !currentSession.isExpired) {
      return AppAuthState.authenticated(AppUser.fromSupabaseUser(currentUser));
    }

    // Even if isLoggedIn() returned false, the SDK's auto-refresh may still
    // complete later. The onAuthStateChange listener will update state
    // reactively when that happens (tokenRefreshed / signedIn events).
    return const AppAuthState.unauthenticated();
  }

  void _startAuthListener() {
    _authSubscription?.cancel();
    _authSubscription = _supabase.auth.onAuthStateChange.listen(
      (data) {
        unawaited(_handleAuthStateChange(data));
      },
      onError: (error, stackTrace) async {
        await ref.read(errorLoggerProvider).logError(error, stackTrace);
        state = AsyncValue.data(AppAuthState.error(error.toString()));
      },
    );

    ref.onDispose(() async {
      await _authSubscription?.cancel();
      _authSubscription = null;
    });
  }

  Future<void> _handleAuthStateChange(AuthState data) async {
    final session = data.session;
    final supabaseUser = session?.user;
    switch (data.event) {
      case AuthChangeEvent.initialSession:
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.userUpdated:
        if (supabaseUser != null && session != null) {
          final appUser = AppUser.fromSupabaseUser(supabaseUser);
          await _sessionManager.saveSession(session, supabaseUser);
          state = AsyncValue.data(AppAuthState.authenticated(appUser));

          // Trigger migration/sync of local settings to Supabase
          // This runs in the background and doesn't block the auth flow
          // Runs on all auth state changes to ensure settings stay synced
          unawaited(
            ref
                .read(settingsMigrationServiceProvider)
                .migrateSettingsToSupabase(),
          );
        }
        break;
      case AuthChangeEvent.signedOut:
      case AuthChangeEvent.passwordRecovery:
      // ignore: deprecated_member_use
      case AuthChangeEvent.userDeleted:
        await _sessionManager.clearLocalStorage();
        state = const AsyncValue.data(AppAuthState.unauthenticated());
        break;
      default:
        break;
    }
  }

  Future<AppUser> signInWithGoogle({bool allowAnonymousUpgrade = true}) async {
    state = const AsyncValue.data(AppAuthState.loading());
    unawaited(
      AnalyticsService.instance.trackAuthEvent(
        action: 'google_sign_in_started',
        method: 'google',
      ),
    );

    // Pre-flight cleanup to close any stale Google auth UI/sessions
    await _signOutGoogle();

    final currentUser = _supabase.auth.currentUser;
    final isAnonymous = currentUser?.isAnonymous == true;
    if (isAnonymous && allowAnonymousUpgrade) {
      try {
        unawaited(
          AnalyticsService.instance.trackAuthEvent(
            action: 'anonymous_upgrade_google_started',
            method: 'google',
          ),
        );
        final appUser = await _linkProviderForAnonymous(
          OAuthProvider.google,
          scopes: _scopes.join(' '),
        );
        unawaited(
          AnalyticsService.instance.trackAuthEvent(
            action: 'anonymous_upgrade_google',
            method: 'google',
            success: true,
            user: appUser,
          ),
        );
        return appUser;
      } catch (e, st) {
        await ref.read(errorLoggerProvider).logError(e, st);
        // _linkProviderForAnonymous for Google now handles the switch internally via signInWithIdToken
        // If it throws, it means something else failed.
        state = AsyncValue.data(AppAuthState.error(_exceptionMessage(e)));
        unawaited(
          AnalyticsService.instance.trackAuthEvent(
            action: 'anonymous_upgrade_google',
            method: 'google',
            success: false,
            reason: e.toString(),
          ),
        );
        rethrow;
      }
    }

    try {
      await _ensureGoogleInitialized();
    } catch (e, st) {
      await ref.read(errorLoggerProvider).logError(e, st);
      final message = _exceptionMessage(e);
      state = AsyncValue.data(
        AppAuthState.error(
          message.isEmpty
              ? 'Google Sign-In is unavailable. Check Google Play Services or configuration.'
              : message,
        ),
      );
      rethrow;
    }

    try {
      if (kDebugMode) {
        debugPrint('🔵 [GOOGLE AUTH] Step 1: Authenticating...');
      }

      // Step 1: Authenticate (without authorization scopes)
      // Don't pass scopeHint here - we'll authorize separately
      final account = await _googleSignIn.authenticate();

      if (kDebugMode) {
        debugPrint('✅ [GOOGLE AUTH] Step 1 complete: Authenticated');
        debugPrint('🔵 [GOOGLE AUTH] Step 2: Getting ID token...');
      }

      final tokenData = account.authentication;
      final idToken = tokenData.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw Exception('Failed to obtain Google ID token.');
      }

      if (kDebugMode) {
        debugPrint('✅ [GOOGLE AUTH] Step 2 complete: Got ID token');
        debugPrint('🔵 [GOOGLE AUTH] Step 3: Authorizing scopes...');
      }

      // Step 2: Try to get authorization (might already be authorized)
      GoogleSignInClientAuthorization? authorization;
      try {
        authorization = await account.authorizationClient
            .authorizationForScopes(_scopes);
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ [GOOGLE AUTH] authorizationForScopes failed, trying authorizeScopes: $e',
          );
        }
      }

      // If not authorized, request authorization (this will show UI)
      if (authorization == null) {
        if (kDebugMode) {
          debugPrint(
            '🔵 [GOOGLE AUTH] Not authorized yet, requesting authorization...',
          );
        }
        authorization = await account.authorizationClient.authorizeScopes(
          _scopes,
        );
      }

      final accessToken = authorization.accessToken;
      if (accessToken.isEmpty) {
        throw Exception(
          'Failed to obtain Google access token. Please try again.',
        );
      }

      if (kDebugMode) {
        debugPrint('✅ [GOOGLE AUTH] Step 3 complete: Got access token');
        debugPrint('🔵 [GOOGLE AUTH] Step 4: Signing in to Supabase...');
      }

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      final user = response.user;
      final session = response.session;
      if (user == null || session == null) {
        throw Exception('Failed to authenticate with Supabase.');
      }

      final appUser = AppUser.fromSupabaseUser(user);
      await _sessionManager.saveSession(session, user);

      if (kDebugMode) {
        debugPrint('✅ [GOOGLE AUTH] Sign-in complete!');
      }

      state = AsyncValue.data(AppAuthState.authenticated(appUser));
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'google_sign_in',
          method: 'google',
          success: true,
          user: appUser,
        ),
      );
      return appUser;
    } on GoogleSignInException catch (e, st) {
      await ref.read(errorLoggerProvider).logError(e, st);
      await _signOutGoogle(); // Ensure any Google auth UI is closed
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'google_sign_in',
          method: 'google',
          success: false,
          reason: e.code.name,
        ),
      );

      if (kDebugMode) {
        debugPrint(
          '❌ [GOOGLE AUTH] GoogleSignInException: ${e.code} - ${e.description}',
        );
      }

      if (e.code == GoogleSignInExceptionCode.canceled) {
        state = const AsyncValue.data(AppAuthState.unauthenticated());
        throw const CancelledSignInException();
      }

      final mapped = _mapGoogleSignInException(e);
      // Do not surface error state on auth screen; reset to unauthenticated
      state = const AsyncValue.data(AppAuthState.unauthenticated());
      throw mapped;
    } catch (e, st) {
      await ref.read(errorLoggerProvider).logError(e, st);
      await _signOutGoogle(); // Ensure any Google auth UI is closed
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'google_sign_in',
          method: 'google',
          success: false,
          reason: e.toString(),
        ),
      );
      // Do not surface programmatic error on auth; reset to unauthenticated
      state = const AsyncValue.data(AppAuthState.unauthenticated());
      rethrow;
    }
  }

  Future<AppUser> signInWithApple({bool allowAnonymousUpgrade = true}) async {
    state = const AsyncValue.data(AppAuthState.loading());
    unawaited(
      AnalyticsService.instance.trackAuthEvent(
        action: 'apple_sign_in_started',
        method: 'apple',
      ),
    );

    if (!Platform.isIOS) {
      final message = 'Apple Sign-In is only available on iOS devices.';
      state = AsyncValue.data(AppAuthState.error(message));
      debugPrint('❌ [APPLE AUTH] Not iOS, aborting');
      throw Exception(message);
    }

    try {
      final currentUser = _supabase.auth.currentUser;
      final isAnonymous = currentUser?.isAnonymous == true;
      if (isAnonymous && allowAnonymousUpgrade) {
        try {
          unawaited(
            AnalyticsService.instance.trackAuthEvent(
              action: 'anonymous_upgrade_apple_started',
              method: 'apple',
            ),
          );
          final appUser = await _linkProviderForAnonymous(
            OAuthProvider.apple,
            scopes: 'name email',
          );
          unawaited(
            AnalyticsService.instance.trackAuthEvent(
              action: 'anonymous_upgrade_apple',
              method: 'apple',
              success: true,
              user: appUser,
            ),
          );
          return appUser;
        } catch (e, st) {
          await ref.read(errorLoggerProvider).logError(e, st);
          // Fallback logic for Apple if needed, or just rethrow
          // Since we removed _fallbackToExistingOauth, we just rethrow here
          // Apple usually uses native flow so stuck webview is less of an issue
          state = AsyncValue.data(AppAuthState.error(_exceptionMessage(e)));
          unawaited(
            AnalyticsService.instance.trackAuthEvent(
              action: 'anonymous_upgrade_apple',
              method: 'apple',
              success: false,
              reason: e.toString(),
            ),
          );
          rethrow;
        }
      }

      final available = await SignInWithApple.isAvailable();
      if (!available) {
        const message = 'Apple Sign-In is not available on this device.';
        debugPrint('❌ [APPLE AUTH] Not available');
        state = const AsyncValue.data(AppAuthState.error(message));
        throw Exception(message);
      }

      final rawNonce = _generateNonce();
      final hashedNonce = _sha256ofString(rawNonce);

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw Exception('Failed to get Apple ID token.');
      }

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      final user = response.user;
      final session = response.session;
      if (user == null || session == null) {
        throw Exception('Failed to authenticate with Supabase.');
      }

      await _sessionManager.saveSession(session, user);

      final fullName =
          '${credential.givenName ?? ''} ${credential.familyName ?? ''}'.trim();
      final data = <String, dynamic>{};
      if (fullName.isNotEmpty) data['full_name'] = fullName;
      if (credential.email != null) data['email'] = credential.email;
      if (data.isNotEmpty) {
        await _supabase.auth.updateUser(UserAttributes(data: data));
      }

      final appUser = AppUser.fromSupabaseUser(user);
      state = AsyncValue.data(AppAuthState.authenticated(appUser));
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'apple_sign_in',
          method: 'apple',
          success: true,
          user: appUser,
        ),
      );
      return appUser;
    } on SignInWithAppleAuthorizationException catch (e, st) {
      await ref.read(errorLoggerProvider).logError(e, st);
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'apple_sign_in',
          method: 'apple',
          success: false,
          reason: e.code.name,
        ),
      );
      switch (e.code) {
        case AuthorizationErrorCode.canceled:
          state = const AsyncValue.data(AppAuthState.unauthenticated());
          throw const CancelledSignInException();
        case AuthorizationErrorCode.notHandled:
        case AuthorizationErrorCode.failed:
        case AuthorizationErrorCode.invalidResponse:
        case AuthorizationErrorCode.unknown:
        default:
          const message = 'Apple sign in failed. Please try again.';
          state = const AsyncValue.data(AppAuthState.error(message));
          debugPrint('❌ [APPLE AUTH] Authorization failed');
          throw Exception(message);
      }
    } catch (e, st) {
      await ref.read(errorLoggerProvider).logError(e, st);
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'apple_sign_in',
          method: 'apple',
          success: false,
          reason: e.toString(),
        ),
      );
      final message = _exceptionMessage(e);
      state = AsyncValue.data(AppAuthState.error(message));
      rethrow;
    }
  }

  Future<AppUser> signInAnonymously() async {
    state = const AsyncValue.data(AppAuthState.loading());
    unawaited(
      AnalyticsService.instance.trackAuthEvent(
        action: 'anonymous_sign_in_started',
        method: 'anonymous',
      ),
    );

    try {
      final response = await _supabase.auth.signInAnonymously();

      final user = response.user;
      final session = response.session;
      if (user == null || session == null) {
        throw Exception('Failed to sign in anonymously.');
      }

      await _sessionManager.saveSession(session, user);

      final appUser = AppUser.fromSupabaseUser(user);
      state = AsyncValue.data(AppAuthState.authenticated(appUser));
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'anonymous_sign_in',
          method: 'anonymous',
          success: true,
          user: appUser,
        ),
      );
      return appUser;
    } catch (e, st) {
      await ref.read(errorLoggerProvider).logError(e, st);
      state = AsyncValue.data(AppAuthState.error(_exceptionMessage(e)));
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'anonymous_sign_in',
          method: 'anonymous',
          success: false,
          reason: e.toString(),
        ),
      );
      rethrow;
    }
  }

  Future<void> signOut() async {
    state = const AsyncValue.data(AppAuthState.loading());

    bool remoteSignOutSucceeded = false;
    String? signOutErrorReason;

    try {
      await _signOutGoogle();

      await _supabase.auth.signOut();
      remoteSignOutSucceeded = true;
    } catch (e, st) {
      signOutErrorReason = e.toString();
      await ref.read(errorLoggerProvider).logError(e, st);
      final rawMessage = _exceptionMessage(e);
      final message =
          rawMessage.isEmpty
              ? 'Failed to sign out. Please try again.'
              : rawMessage;
      // Log the error but continue with local sign-out to avoid sticky sessions.
      state = AsyncValue.data(AppAuthState.error(message));
    } finally {
      // Always clear local session to prevent silent re-auth on next launch
      try {
        await _supabase.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // Best-effort: ignore local sign-out failures
      }
      await _sessionManager.clearLocalStorage();
      state = const AsyncValue.data(AppAuthState.unauthenticated());
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'sign_out',
          method: 'manual',
          success: remoteSignOutSucceeded,
          reason: remoteSignOutSucceeded ? null : signOutErrorReason,
        ),
      );
    }
  }

  /// Best-effort Google sign out to clear cached accounts and refresh tokens.
  /// This runs even if the current session is anonymous to avoid sticky Google auth.
  Future<void> _signOutGoogle() async {
    try {
      await _ensureGoogleInitialized();
      await _googleSignIn.signOut();
      await _googleSignIn.disconnect();
    } catch (e, st) {
      // Log but don't block overall sign-out flow.
      await ref
          .read(errorLoggerProvider)
          .logError('Google sign out failed: $e', st);
    }
  }

  /// Snapshot of anonymous user's favorites captured before auth upgrade.
  /// Used by [mergeAnonymousFavorites] to carry them forward.
  List<Map<String, dynamic>>? _anonymousFavoritesSnapshot;

  /// Captures all favorite players for the given anonymous user so they can
  /// be merged into the new authenticated account after [signInWithIdToken].
  Future<List<Map<String, dynamic>>> _snapshotAnonymousFavorites(
    String anonUserId,
  ) async {
    try {
      final rows = await _supabase
          .from('user_favorite_players')
          .select()
          .eq('user_id', anonUserId);
      debugPrint(
        '[Auth] Captured ${rows.length} anonymous favorites for migration',
      );
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('[Auth] Failed to snapshot anonymous favorites: $e');
      return [];
    }
  }

  /// Merges the previously captured anonymous favorites into [newUserId].
  /// Deduplicates by fide_id first, then player_name as fallback.
  /// Clears the snapshot only after a successful merge.
  Future<void> mergeAnonymousFavorites(String newUserId) async {
    final snapshot = _anonymousFavoritesSnapshot;
    if (snapshot == null || snapshot.isEmpty) return;

    try {
      for (final row in snapshot) {
        final fideId = row['fide_id']?.toString() ?? '';
        final playerName = row['player_name']?.toString() ?? '';

        // Deduplicate by fide_id
        if (fideId.isNotEmpty) {
          final existing =
              await _supabase
                  .from('user_favorite_players')
                  .select('id')
                  .eq('user_id', newUserId)
                  .eq('fide_id', fideId)
                  .maybeSingle();
          if (existing != null) continue;
        }

        // Upsert with player_name conflict resolution as fallback
        await _supabase
            .from('user_favorite_players')
            .upsert(
              {
                'user_id': newUserId,
                'fide_id': fideId.isNotEmpty ? fideId : null,
                'player_name': playerName,
                'metadata': row['metadata'],
              },
              onConflict: 'user_id,player_name',
              ignoreDuplicates: true,
            );
      }

      debugPrint(
        '[Auth] Merged ${snapshot.length} anonymous favorites into $newUserId',
      );
      _anonymousFavoritesSnapshot = null;
    } catch (e) {
      debugPrint('[Auth] Failed to merge anonymous favorites: $e');
      // Keep the snapshot so it can be retried on next sync
    }
  }

  Future<AppUser> _linkProviderForAnonymous(
    OAuthProvider provider, {
    String? scopes,
  }) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null || currentUser.isAnonymous != true) {
      throw Exception('No anonymous session to upgrade.');
    }

    // Capture anonymous favorites before switching user —
    // signInWithIdToken may switch to a different user_id,
    // orphaning the anonymous user's data.
    _anonymousFavoritesSnapshot = await _snapshotAnonymousFavorites(
      currentUser.id,
    );

    // For Google, we use the native flow to avoid stuck webviews
    if (provider == OAuthProvider.google) {
      try {
        await _ensureGoogleInitialized();
        // 1. Get ID Token natively
        final account = await _googleSignIn.authenticate();
        final tokenData = await account?.authentication;
        final idToken = tokenData?.idToken;

        if (idToken == null) {
          throw Exception('Failed to get Google ID token.');
        }

        // 2. Attempt to link/sign-in using the ID token
        // Note: signInWithIdToken will switch the user if the account exists.
        // It does NOT link to the current anonymous user automatically in most cases,
        // but it avoids the browser flow entirely.
        final response = await _supabase.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          // accessToken is not strictly required for ID token sign-in and is no longer
          // directly available in GoogleSignInAuthentication (v7.0.0+)
        );

        final user = response.user;
        final session = response.session;
        if (user == null || session == null) {
          throw Exception('Failed to authenticate with Supabase.');
        }

        await _sessionManager.saveSession(session, user);
        final appUser = AppUser.fromSupabaseUser(user);

        state = AsyncValue.data(AppAuthState.authenticated(appUser));
        return appUser;
      } catch (e, st) {
        await ref.read(errorLoggerProvider).logError(e, st);
        // Ensure Google is signed out on error
        await _signOutGoogle();
        rethrow;
      }
    }

    // For Apple, use native flow with signInWithIdToken (same as Google)
    // This handles both new accounts AND existing accounts properly
    if (provider == OAuthProvider.apple) {
      try {
        final available = await SignInWithApple.isAvailable();
        if (!available) {
          throw Exception('Apple Sign-In is not available on this device.');
        }

        final rawNonce = _generateNonce();
        final hashedNonce = _sha256ofString(rawNonce);

        final credential = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
          nonce: hashedNonce,
        );

        final idToken = credential.identityToken;
        if (idToken == null) {
          throw Exception('Failed to get Apple ID token.');
        }

        // Use signInWithIdToken - this will sign into existing Apple account
        // or create a new one (switching from anonymous)
        final response = await _supabase.auth.signInWithIdToken(
          provider: OAuthProvider.apple,
          idToken: idToken,
          nonce: rawNonce,
        );

        final user = response.user;
        final session = response.session;
        if (user == null || session == null) {
          throw Exception('Failed to authenticate with Supabase.');
        }

        await _sessionManager.saveSession(session, user);

        // Update user metadata with Apple credential info if available
        final fullName =
            '${credential.givenName ?? ''} ${credential.familyName ?? ''}'
                .trim();
        final data = <String, dynamic>{};
        if (fullName.isNotEmpty) data['full_name'] = fullName;
        if (credential.email != null) data['email'] = credential.email;
        if (data.isNotEmpty) {
          await _supabase.auth.updateUser(UserAttributes(data: data));
        }

        final appUser = AppUser.fromSupabaseUser(user);
        state = AsyncValue.data(AppAuthState.authenticated(appUser));
        return appUser;
      } on SignInWithAppleAuthorizationException catch (e) {
        if (e.code == AuthorizationErrorCode.canceled) {
          state = const AsyncValue.data(AppAuthState.unauthenticated());
          throw const CancelledSignInException();
        }
        rethrow;
      } catch (e, st) {
        await ref.read(errorLoggerProvider).logError(e, st);
        rethrow;
      }
    }

    // For other providers, use the web-based linkIdentity flow
    final completer = Completer<AppUser>();
    StreamSubscription<AuthState>? sub;

    try {
      sub = _supabase.auth.onAuthStateChange.listen((data) async {
        final user = data.session?.user;
        final session = data.session;
        if (user != null && user.isAnonymous != true && session != null) {
          await _sessionManager.saveSession(session, user);
          final appUser = AppUser.fromSupabaseUser(user);
          if (!completer.isCompleted) {
            completer.complete(appUser);
          }
          await sub?.cancel();
        }
      });

      final launched = await _supabase.auth.linkIdentity(
        provider,
        scopes: scopes,
        redirectTo: 'com.chessever.app://login-callback',
      );

      if (!launched) {
        throw Exception('Failed to launch ${provider.name} link flow.');
      }
    } catch (e, st) {
      await sub?.cancel();
      // Force-close any Supabase web auth session
      try {
        await _supabase.auth.signOut(scope: SignOutScope.global);
      } catch (_) {}

      await ref.read(errorLoggerProvider).logError(e, st);
      state = const AsyncValue.data(
        AppAuthState.error('Unable to start sign-in. Please try again.'),
      );
      rethrow;
    }

    try {
      final user = await completer.future.timeout(const Duration(seconds: 90));
      state = AsyncValue.data(AppAuthState.authenticated(user));
      return user;
    } on TimeoutException {
      await sub?.cancel();
      state = const AsyncValue.data(
        AppAuthState.error('Sign in timed out. Please try again.'),
      );
      throw Exception('Linking timed out. Please try again.');
    } catch (e) {
      await sub?.cancel();
      rethrow;
    }
  }

  Future<void> deleteAccount() async {
    state = const AsyncValue.data(AppAuthState.loading());

    try {
      // Sign out from Google first (best effort)
      await _signOutGoogle();

      // Call RPC to delete user account from Supabase
      // This deletes from auth.users which CASCADE deletes:
      // - user_favorite_events
      // - user_favorite_players
      // - user_engine_settings
      // - user_folders
      // - user_saved_analyses
      await _supabase.rpc('delete_user_account');

      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'delete_account',
          success: true,
        ),
      );

      // Clear ALL local data (SharedPreferences) for complete wipe
      await _sessionManager.clearAllUserData();

      // Clear local Supabase session
      try {
        await _supabase.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // Best-effort: ignore local sign-out failures (user already deleted)
      }

      state = const AsyncValue.data(AppAuthState.unauthenticated());
    } catch (e, st) {
      await ref.read(errorLoggerProvider).logError(e, st);
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'delete_account',
          success: false,
          reason: e.toString(),
        ),
      );

      // If RPC fails, still clear local data to prevent stuck state
      try {
        await _sessionManager.clearAllUserData();
        await _supabase.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}

      state = const AsyncValue.data(AppAuthState.unauthenticated());

      final rawMessage = _exceptionMessage(e);
      final message =
          rawMessage.isEmpty
              ? 'Failed to delete account. Please contact support.'
              : rawMessage;
      throw Exception(message);
    }
  }

  Future<void> _ensureGoogleInitialized() {
    final existing = _googleInitCompleter;
    if (existing != null) {
      return existing.future;
    }

    final completer = Completer<void>();
    _googleInitCompleter = completer;

    () async {
      try {
        await _initializeGoogleSignIn();
        completer.complete();
      } catch (error, stackTrace) {
        await ref.read(errorLoggerProvider).logError(error, stackTrace);
        _googleInitCompleter = null;
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    }();

    return completer.future;
  }

  Future<void> _initializeGoogleSignIn() async {
    if (kDebugMode) {
      debugPrint('🔵 [GOOGLE INIT] Starting initialization...');
      debugPrint('   Platform: ${Platform.isAndroid ? "Android" : "iOS"}');
    }

    // clientId is only needed for iOS (Android auto-handles it via SHA-1/package name)
    String? clientId;
    if (Platform.isIOS) {
      clientId = _env('GOOGLE_IOS_CLIENT_ID');
    }

    // serverClientId (web client ID) is REQUIRED for server-side auth
    final serverClientId = _env('GOOGLE_WEB_CLIENT_ID');

    await _googleSignIn.initialize(
      clientId: clientId,
      serverClientId: serverClientId,
    );

    if (kDebugMode) {
      debugPrint('✅ [GOOGLE INIT] Initialization successful');
      debugPrint('   clientId: ${clientId ?? "null (Android auto-handled)"}');
      debugPrint('   serverClientId: $serverClientId');
    }
  }

  String _env(String key, {bool required = true}) {
    String? value;
    final releaseValue = _releaseEnvValues[key]?.trim();

    if (E2eConfig.isEnabled &&
        releaseValue != null &&
        releaseValue.isNotEmpty) {
      value = releaseValue;
    } else if (kDebugMode) {
      value = dotenv.env[key]?.trim();
    } else {
      value = releaseValue;
    }

    if (value == null || value.isEmpty) {
      if (required) {
        throw Exception('Missing env: $key');
      }
      return '';
    }

    return value;
  }

  Exception _mapGoogleSignInException(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return Exception('Google sign in was cancelled.');
      case GoogleSignInExceptionCode.interrupted:
      case GoogleSignInExceptionCode.uiUnavailable:
        return Exception('Google sign in was interrupted. Please try again.');
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return Exception(
          e.description ??
              'Google Sign-In configuration error. Verify bundle ID, client IDs, and URL schemes.',
        );
      case GoogleSignInExceptionCode.userMismatch:
        return Exception('Google sign in failed due to account mismatch.');
      default:
        return Exception(
          e.description ?? 'Google sign in failed. Please try again.',
        );
    }
  }

  String _exceptionMessage(Object error) {
    final message = error.toString();
    const prefix = 'Exception: ';
    if (message.startsWith(prefix)) {
      return message.substring(prefix.length);
    }
    return message;
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
