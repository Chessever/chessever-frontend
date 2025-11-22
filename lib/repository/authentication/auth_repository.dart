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

    await _ensureGoogleInitialized();
    _startAuthListener();

    final currentUser = _supabase.auth.currentUser;
    if (currentUser != null) {
      return AppAuthState.authenticated(AppUser.fromSupabaseUser(currentUser));
    }

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
            ref.read(settingsMigrationServiceProvider).migrateSettingsToSupabase(),
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

  Future<AppUser> signInWithGoogle() async {
    state = const AsyncValue.data(AppAuthState.loading());
    unawaited(
      AnalyticsService.instance.trackAuthEvent(
        action: 'google_sign_in_started',
        method: 'google',
      ),
    );
    await _ensureGoogleInitialized();

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

      final idToken = account.authentication.idToken;

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
        authorization = await account.authorizationClient.authorizationForScopes(_scopes);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ [GOOGLE AUTH] authorizationForScopes failed, trying authorizeScopes: $e');
        }
      }

      // If not authorized, request authorization (this will show UI)
      if (authorization == null) {
        if (kDebugMode) {
          debugPrint('🔵 [GOOGLE AUTH] Not authorized yet, requesting authorization...');
        }
        authorization = await account.authorizationClient.authorizeScopes(_scopes);
      }

      final accessToken = authorization.accessToken;

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
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'google_sign_in',
          method: 'google',
          success: false,
          reason: e.code.name,
        ),
      );

      if (kDebugMode) {
        debugPrint('❌ [GOOGLE AUTH] GoogleSignInException: ${e.code} - ${e.description}');
      }

      // Only treat as cancellation if it's truly a user action
      // But per migration guide, "canceled" can also mean config error on Android!
      if (e.code == GoogleSignInExceptionCode.canceled) {
        if (Platform.isAndroid) {
          // On Android, "canceled" often means configuration error
          debugPrint('❌ [GOOGLE AUTH] Canceled on Android - likely config error (SHA-1/client ID). Falling back to anonymous.');
          return await _fallbackToAnonymousSignIn();
        } else {
          // On iOS, canceled is more reliable
          state = const AsyncValue.data(AppAuthState.unauthenticated());
          throw const CancelledSignInException();
        }
      }

      final mapped = _mapGoogleSignInException(e);
      final message = _exceptionMessage(mapped);
      state = AsyncValue.data(AppAuthState.error(message));

      // Fallback to anonymous sign-in on any Google auth failure
      debugPrint('❌ [GOOGLE AUTH] Google sign-in failed: $message. Falling back to anonymous sign-in');
      return await _fallbackToAnonymousSignIn();
    } catch (e, st) {
      await ref.read(errorLoggerProvider).logError(e, st);
      debugPrint('❌ [GOOGLE AUTH] Exception occurred: $e. Falling back to anonymous sign-in');
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'google_sign_in',
          method: 'google',
          success: false,
          reason: e.toString(),
        ),
      );
      return await _fallbackToAnonymousSignIn();
    }
  }

  Future<AppUser> signInWithApple() async {
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
      debugPrint('❌ [APPLE AUTH] Not iOS, falling back to anonymous sign-in');
      return await _fallbackToAnonymousSignIn();
    }

    try {
      final available = await SignInWithApple.isAvailable();
      if (!available) {
        debugPrint('❌ [APPLE AUTH] Not available, falling back to anonymous sign-in');
        return await _fallbackToAnonymousSignIn();
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
          debugPrint('❌ [APPLE AUTH] Authorization failed, falling back to anonymous sign-in');
          return await _fallbackToAnonymousSignIn();
      }
    } catch (e, st) {
      await ref.read(errorLoggerProvider).logError(e, st);
      debugPrint('❌ [APPLE AUTH] Exception occurred, falling back to anonymous sign-in');
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'apple_sign_in',
          method: 'apple',
          success: false,
          reason: e.toString(),
        ),
      );
      return await _fallbackToAnonymousSignIn();
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

  /// Internal fallback method to sign in anonymously when OAuth fails
  Future<AppUser> _fallbackToAnonymousSignIn() async {
    try {
      debugPrint('🔄 [FALLBACK] Attempting anonymous sign-in...');
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
          method: 'fallback',
          success: true,
          user: appUser,
        ),
      );
      debugPrint('✅ [FALLBACK] Anonymous sign-in successful');
      return appUser;
    } catch (e, st) {
      debugPrint('❌ [FALLBACK] Anonymous sign-in failed: $e');
      await ref.read(errorLoggerProvider).logError(e, st);
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'anonymous_sign_in',
          method: 'fallback',
          success: false,
          reason: e.toString(),
        ),
      );
      state = AsyncValue.data(AppAuthState.error(_exceptionMessage(e)));
      rethrow;
    }
  }

  Future<void> signOut() async {
    state = const AsyncValue.data(AppAuthState.loading());
    await _ensureGoogleInitialized();

    try {
      try {
        await _googleSignIn.disconnect();
      } catch (_) {
        // Ignore if already disconnected.
      }

      await _supabase.auth.signOut();
      await _sessionManager.clearLocalStorage();
      state = const AsyncValue.data(AppAuthState.unauthenticated());
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'sign_out',
          method: 'manual',
          success: true,
        ),
      );
    } catch (e, st) {
      await ref.read(errorLoggerProvider).logError(e, st);
      final rawMessage = _exceptionMessage(e);
      final message = rawMessage.isEmpty
          ? 'Failed to sign out. Please try again.'
          : rawMessage;
      state = AsyncValue.data(AppAuthState.error(message));
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'sign_out',
          method: 'manual',
          success: false,
          reason: e.toString(),
        ),
      );
      rethrow;
    }
  }

  Future<void> deleteAccount() async {
    state = const AsyncValue.data(AppAuthState.loading());
    
    try {
      // Call RPC to delete user account (common pattern for Supabase)
      // This assumes a 'delete_user_account' function exists in Postgres
      await _supabase.rpc('delete_user_account');
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'delete_account',
          success: true,
        ),
      );
      
      // Sign out after deletion
      await signOut();
    } catch (e, st) {
      await ref.read(errorLoggerProvider).logError(e, st);
      unawaited(
        AnalyticsService.instance.trackAuthEvent(
          action: 'delete_account',
          success: false,
          reason: e.toString(),
        ),
      );
      
      // If RPC fails, try to at least sign out and clear local data
      // But rethrow so UI can show error
      try {
        await signOut();
      } catch (_) {}
      
      final rawMessage = _exceptionMessage(e);
      final message = rawMessage.isEmpty
          ? 'Failed to delete account. Please contact support.'
          : rawMessage;
      state = AsyncValue.data(AppAuthState.error(message));
      rethrow;
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
    if (kDebugMode) {
      value = dotenv.env[key]?.trim();
    } else {
      value = _releaseEnvValues[key];
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
