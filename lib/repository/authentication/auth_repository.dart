import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:chessever2/providers/error_logger_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/authentication/model/exceptions.dart';
import 'package:chessever2/repository/local_storage/sesions_manager/session_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Compile-time environment values injected via `--dart-define`.
const Map<String, String> _releaseEnvValues = {
  'GOOGLE_ANDROID_CLIENT_ID': String.fromEnvironment(
    'GOOGLE_ANDROID_CLIENT_ID',
    defaultValue: '',
  ),
  'GOOGLE_WEB_CLIENT_ID': String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  ),
  'GOOGLE_IOS_CLIENT_ID': String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  ),
  'APPLE_SERVICE_ID': String.fromEnvironment(
    'APPLE_SERVICE_ID',
    defaultValue: '',
  ),
  'APPLE_REDIRECT_URI': String.fromEnvironment(
    'APPLE_REDIRECT_URI',
    defaultValue: '',
  ),
};

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref);
});

class AuthRepository {
  AuthRepository(this.ref) {
    _supabase = Supabase.instance.client;
    _googleInitialization = _initializeGoogleSignIn();
  }

  static const List<String> _googleScopes = ['email', 'profile'];

  late final SupabaseClient _supabase;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  Future<void>? _googleInitialization;
  final Ref ref;

  // Read and trim env safely to avoid trailing spaces causing Apple failures.
  String _env(String key, {bool required = true}) {
    String? value;
    if (kDebugMode) {
      value = dotenv.env[key]?.trim();
    } else {
      // In production, CodeMagic injects environment variables via --dart-define
      // We must look them up from the compile-time const map
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

  Future<void> _initializeGoogleSignIn() async {
    try {
      String? clientId;
      if (Platform.isIOS) {
        clientId = _env('GOOGLE_IOS_CLIENT_ID');
      } else if (Platform.isAndroid) {
        final androidClientId = _env(
          'GOOGLE_ANDROID_CLIENT_ID',
          required: true,
        );
        clientId = androidClientId.isEmpty ? null : androidClientId;
        if (clientId == null) {
          if (kDebugMode) {
            debugPrint(
              '⚠️ GOOGLE_ANDROID_CLIENT_ID not provided; proceeding without explicit Android client ID.',
            );
          } else {
            await ref
                .read(errorLoggerProvider)
                .logError(
                  Exception('Missing GOOGLE_ANDROID_CLIENT_ID'),
                  StackTrace.current,
                );
          }
        }
      }

      await _googleSignIn.initialize(
        clientId: clientId,
        serverClientId: _env('GOOGLE_WEB_CLIENT_ID'),
      );

      // Disabled automatic sign-in to prevent unwanted Google OAuth popups
      // final future = _googleSignIn.attemptLightweightAuthentication();
      // future?.catchError((_, __) => null);
    } catch (e, st) {
      await ref.read(errorLoggerProvider).logError(e, st);
      rethrow;
    }
  }

  Future<void> _ensureGoogleInitialized() async {
    _googleInitialization ??= _initializeGoogleSignIn();
    await _googleInitialization;
  }

  // Create a bypass user for Android (production workaround for OAuth issues)
  AppUser get _androidBypassUser {
    return AppUser(
      id: 'android-bypass-user',
      email: 'android.user@chessever.com',
      displayName: 'Android User',
      createdAt: DateTime.now(),
      isAnonymous: false,
    );
  }

  // Current user stream
  Stream<AppUser?> get authStateChanges {
    // Bypass authentication for Android users due to production OAuth issues
    if (Platform.isAndroid) {
      return Stream.value(_androidBypassUser);
    }

    return _supabase.auth.onAuthStateChange.map((data) {
      final user = data.session?.user;
      return user != null ? AppUser.fromSupabaseUser(user) : null;
    });
  }

  // Get current user
  AppUser? get currentUser {
    // Bypass authentication for Android users due to production OAuth issues
    if (Platform.isAndroid) {
      return _androidBypassUser;
    }

    final user = _supabase.auth.currentUser;
    return user != null ? AppUser.fromSupabaseUser(user) : null;
  }

  // Google Sign In
  Future<AppUser> signInWithGoogle() async {
    final sessionManager = ref.read(sessionManagerProvider);

    await _ensureGoogleInitialized();

    try {
      final account = await _googleSignIn.authenticate(
        scopeHint: _googleScopes,
      );
      final idToken = account.authentication.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw Exception('Failed to get Google ID token');
      }

      final GoogleSignInClientAuthorization authorization =
          await account.authorizationClient.authorizationForScopes(
            _googleScopes,
          ) ??
          await account.authorizationClient.authorizeScopes(_googleScopes);

      final accessToken = authorization.accessToken;

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      final user = response.user;
      final session = response.session;

      if (user == null || session == null) {
        throw Exception('Failed to authenticate with Supabase');
      }

      await sessionManager.saveSession(session, user);

      return AppUser.fromSupabaseUser(user);
    } on GoogleSignInException catch (e, st) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const CancelledSignInException();
      }
      await ref.read(errorLoggerProvider).logError(e, st);
      throw _mapGoogleSignInException(e);
    } catch (e, st) {
      await ref.read(errorLoggerProvider).logError(e, st);
      rethrow;
    }
  }

  // Apple Sign In
  Future<AppUser> signInWithApple() async {
    final sessionManager = ref.read(sessionManagerProvider);

    try {
      // Ensure Apple Sign In is actually available (e.g., user signed into iCloud).
      if (Platform.isIOS) {
        final available = await SignInWithApple.isAvailable();
        if (!available) {
          throw Exception(
            'Apple Sign In not available on this device. Sign into iCloud and try again.',
          );
        }
      }

      // Generate nonce for security
      final rawNonce = _generateNonce();
      final hashedNonce = _sha256ofString(rawNonce);

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        // Apple expects the SHA256(nonce)
        nonce: hashedNonce,
        // On Android the plugin uses the web flow; you must provide Service ID + Redirect URI
        webAuthenticationOptions:
            Platform.isAndroid
                ? WebAuthenticationOptions(
                  clientId: _env(
                    'APPLE_SERVICE_ID',
                  ), // Service ID from Apple Developer
                  redirectUri: Uri.parse(_env('APPLE_REDIRECT_URI')),
                )
                : null,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw Exception('Failed to get Apple ID token');
      }

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        // Supabase expects the original raw nonce
        nonce: rawNonce,
      );

      final user = response.user;
      final session = response.session;
      if (user == null || session == null) {
        throw Exception('Failed to authenticate with Supabase');
      }

      // Persist session the same way as Google
      await sessionManager.saveSession(session, user);

      // Update optional metadata if Apple returned name/email (only on first consent)
      final fullName =
          '${credential.givenName ?? ''} ${credential.familyName ?? ''}'.trim();
      final data = <String, dynamic>{};
      if (fullName.isNotEmpty) data['full_name'] = fullName;
      if (credential.email != null) data['email'] = credential.email;
      if (data.isNotEmpty) {
        await _supabase.auth.updateUser(UserAttributes(data: data));
      }

      return AppUser.fromSupabaseUser(user);
    } on SignInWithAppleAuthorizationException catch (e) {
      // Map common Apple errors to actionable messages
      debugPrint('Apple auth exception: code=${e.code}, message=${e.message}');
      switch (e.code) {
        case AuthorizationErrorCode.canceled:
          throw const CancelledSignInException();
        case AuthorizationErrorCode.notHandled:
          throw Exception('Apple sign in not handled');
        case AuthorizationErrorCode.failed:
        case AuthorizationErrorCode.invalidResponse:
        case AuthorizationErrorCode.unknown:
        default:
          throw Exception(
            'Apple sign in failed. Check capability, iCloud login, and time settings.',
          );
      }
    } catch (e, st) {
      await ref.read(errorLoggerProvider).logError(e, st);
      rethrow;
    }
  }

  // Anonymous Sign In (Fallback)
  Future<AppUser> signInAnonymously() async {
    debugPrint('🔵 [REPO] signInAnonymously() called');
    final sessionManager = ref.read(sessionManagerProvider);

    try {
      debugPrint('🔵 [REPO] Calling Supabase auth.signInAnonymously()...');
      final response = await _supabase.auth.signInAnonymously();
      debugPrint('🔵 [REPO] Supabase response received');

      final user = response.user;
      final session = response.session;

      debugPrint('🔵 [REPO] User: ${user?.id}, Session: ${session != null}');

      if (user == null || session == null) {
        debugPrint('❌ [REPO] User or session is null!');
        throw Exception('Failed to sign in anonymously');
      }

      debugPrint('🔵 [REPO] Saving session...');
      await sessionManager.saveSession(session, user);
      debugPrint('✅ [REPO] Session saved successfully');

      final appUser = AppUser.fromSupabaseUser(user);
      debugPrint('✅ [REPO] AppUser created: ${appUser.id}');
      return appUser;
    } catch (e, st) {
      debugPrint('❌ [REPO] Exception in signInAnonymously!');
      debugPrint('   Error: $e');
      debugPrint('   Type: ${e.runtimeType}');
      await ref.read(errorLoggerProvider).logError(e, st);
      rethrow;
    }
  }

  Exception _mapGoogleSignInException(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return Exception('Google sign in was cancelled');
      case GoogleSignInExceptionCode.interrupted:
      case GoogleSignInExceptionCode.uiUnavailable:
        return Exception('Google sign in was interrupted. Please try again.');
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return Exception(
          e.description ??
              'Google Sign-In configuration error. Verify iOS bundle ID, client IDs, and URL schemes.',
        );
      case GoogleSignInExceptionCode.userMismatch:
        return Exception('Google sign in failed due to account mismatch.');
      default:
        return Exception(
          e.description ?? 'Google sign in failed. Please try again.',
        );
    }
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      await _ensureGoogleInitialized();
      await _googleSignIn.signOut();

      await _supabase.auth.signOut();
    } catch (e, st) {
      await ref.read(errorLoggerProvider).logError(e, st);
      rethrow;
    }
  }

  // Helper methods for Apple Sign In
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
