import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:chessever2/providers/error_logger_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/local_storage/sesions_manager/session_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref);
});

class AuthRepository {
  late final SupabaseClient _supabase;
  late final GoogleSignIn _googleSignIn;
  final Ref ref;

  // Read and trim env safely to avoid trailing spaces causing Apple failures.
  String _env(String key) {
    final v = dotenv.env[key]?.trim();
    if (v == null || v.isEmpty) {
      throw Exception('Missing env: $key');
    }
    return v;
  }

  AuthRepository(this.ref) {
    _supabase = SupabaseClient(_env('SUPABASE_URL'), _env('SUPABASE_ANON_KEY'));

    _googleSignIn = GoogleSignIn(
      clientId: _env('GOOGLE_WEB_CLIENT_ID'),
      scopes: ['email', 'profile'],
    );
  }

  // Current user stream
  Stream<AppUser?> get authStateChanges {
    return _supabase.auth.onAuthStateChange.map((data) {
      final user = data.session?.user;
      return user != null ? AppUser.fromSupabaseUser(user) : null;
    });
  }

  // Get current user
  AppUser? get currentUser {
    final user = _supabase.auth.currentUser;
    return user != null ? AppUser.fromSupabaseUser(user) : null;
  }

  // Google Sign In
  Future<AppUser> signInWithGoogle() async {
    final sessionManager = ref.read(sessionManagerProvider);

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw Exception('Google sign in was cancelled');
      }

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null || idToken == null) {
        throw Exception('Failed to get Google tokens');
      }

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
          throw Exception('Apple sign in was cancelled');
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

  // Sign Out
  Future<void> signOut() async {
    try {
      // Sign out from Google if signed in
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }

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
