import 'dart:convert';
import 'dart:math';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/local_storage/sesions_manager/session_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_repository.g.dart';

@riverpod
AuthRepository authRepository(AuthRepositoryRef ref) {
  return AuthRepository(ref);
}

class AuthRepository {
  late final SupabaseClient _supabase;
  late final GoogleSignIn _googleSignIn;
  final Ref ref;

  AuthRepository(this.ref) {
    // Initialize Supabase client directly
    _supabase = SupabaseClient(
      dotenv.env['SUPABASE_URL']!,
      dotenv.env['SUPABASE_ANON_KEY']!,
    );

    _googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
      clientId: dotenv.env['GOOGLE_WEB_CLIENT_ID'],
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
    } catch (e) {
      debugPrint('Google sign in error: $e');
      rethrow;
    }
  }

  // Apple Sign In
  Future<AppUser> signInWithApple() async {
    try {
      // Generate nonce for security
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw Exception('Failed to get Apple ID token');
      }

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      final user = response.user;
      if (user == null) {
        throw Exception('Failed to authenticate with Supabase');
      }

      // Update user metadata with Apple info if available
      if (credential.givenName != null || credential.familyName != null) {
        final fullName =
            '${credential.givenName ?? ''} ${credential.familyName ?? ''}'
                .trim();
        if (fullName.isNotEmpty) {
          await _supabase.auth.updateUser(
            UserAttributes(data: {'full_name': fullName}),
          );
        }
      }

      return AppUser.fromSupabaseUser(user);
    } catch (e) {
      debugPrint('Apple sign in error: $e');
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
    } catch (e) {
      debugPrint('Sign out error: $e');
      rethrow;
    }
  }

  // Delete Account
  Future<void> deleteAccount() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      // Sign out from third-party providers
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }

      // Delete user from Supabase (requires RLS policy or admin rights)
      await _supabase.auth.admin.deleteUser(user.id);
    } catch (e) {
      debugPrint('Delete account error: $e');
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
