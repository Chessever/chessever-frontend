// auth_screen_state.dart
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/authentication/model/exceptions.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'auth_screen_state.dart';

// Provider definition
final authScreenProvider =
    StateNotifierProvider<AuthScreenNotifier, AuthScreenState>((ref) {
      return AuthScreenNotifier(ref);
    });

class AuthScreenNotifier extends StateNotifier<AuthScreenState> {
  AuthScreenNotifier(this.ref) : super(const AuthScreenState());

  final Ref ref;

  Future<void> signInWithGoogle() async {
    await _performSignIn(
      () => ref.read(authStateProvider.notifier).signInWithGoogle(),
    );
  }

  Future<void> signInWithApple() async {
    await _performSignIn(
      () => ref.read(authStateProvider.notifier).signInWithApple(),
    );
  }

  Future<void> signInAsGuest() async {
    await _performSignIn(
      () => ref.read(authStateProvider.notifier).signInAnonymously(),
    );
  }

  Future<void> _performSignIn(Future<AppUser> Function() signInMethod) async {
    debugPrint('🔵 [AUTH] Starting sign-in flow...');
    state = state.copyWith(isLoading: true, errorMessage: null);

    debugPrint('🔵 [AUTH] Attempting OAuth sign-in...');
    try {
      final user = await signInMethod();
      debugPrint('✅ [AUTH] OAuth sign-in succeeded!');
      debugPrint('   User ID: ${user.id}');
      if (!mounted) {
        debugPrint('⚪ [AUTH] Notifier disposed before completing OAuth success handling');
        return;
      }
      state = state.copyWith(
        isLoading: false,
        user: user,
        showCountrySelection: true,
      );
    } on CancelledSignInException {
      // User cancelled - don't fall back to anonymous
      debugPrint('⚠️ [AUTH] User cancelled sign-in');
      state = state.copyWith(isLoading: false);
    } catch (e) {
      debugPrint('❌ [AUTH] OAuth sign-in FAILED!');
      debugPrint('   Error: $e');
      debugPrint('   Error type: ${e.runtimeType}');
      final errorMessage = _getErrorMessage(e.toString());
      if (!mounted) {
        debugPrint('⚪ [AUTH] Notifier disposed before propagating error');
        return;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: errorMessage,
      );
      debugPrint('🔴 [AUTH] Showing error to user: $errorMessage');
    }
  }

  void clearError() {
    state = AuthScreenState();
  }

  void hideCountrySelection() {
    state = state.copyWith(showCountrySelection: false);
  }

  void reset() {
    state = const AuthScreenState();
  }

  String _getErrorMessage(String error) {
    final lower = error.toLowerCase();

    if (lower.contains('cancelled')) {
      return 'Sign in was cancelled';
    } else if (lower.contains('play services') || lower.contains('configuration')) {
      return 'Google Sign-In is unavailable on this device. Please check Google Play Services or try again later.';
    } else if (lower.contains('network')) {
      return 'Network error. Please check your connection';
    } else if (lower.contains('tokens')) {
      return 'Authentication failed. Please try again';
    } else {
      return 'Sign in failed. Please try again';
    }
  }
}
