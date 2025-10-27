// auth_screen_state.dart
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/exceptions.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'auth_screen_state.dart';

// Provider definition
final authScreenProvider =
    StateNotifierProvider<AuthScreenNotifier, AuthScreenState>((ref) {
      final authRepository = ref.read(authRepositoryProvider);
      return AuthScreenNotifier(authRepository);
    });

class AuthScreenNotifier extends StateNotifier<AuthScreenState> {
  final AuthRepository _authRepository;

  AuthScreenNotifier(this._authRepository) : super(const AuthScreenState());

  Future<void> signInWithGoogle() async {
    await _performSignIn(() => _authRepository.signInWithGoogle());
  }

  Future<void> signInWithApple() async {
    await _performSignIn(() => _authRepository.signInWithApple());
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
      // OAuth failed - fall back to anonymous sign-in
      debugPrint('❌ [AUTH] OAuth sign-in FAILED!');
      debugPrint('   Error: $e');
      debugPrint('   Error type: ${e.runtimeType}');
      debugPrint('🔄 [AUTH] Attempting fallback to anonymous sign-in...');

      try {
        final anonymousUser = await _authRepository.signInAnonymously();
        debugPrint('✅ [AUTH] Anonymous fallback succeeded!');
        debugPrint('   User ID: ${anonymousUser.id}');
        if (!mounted) {
          debugPrint('⚪ [AUTH] Notifier disposed before completing anonymous fallback handling');
          return;
        }
        state = state.copyWith(
          isLoading: false,
          user: anonymousUser,
          showCountrySelection: true,
        );
        debugPrint('🟢 [AUTH] State updated with anonymous user (fallback)');
      } catch (anonymousError, anonymousSt) {
        // Both OAuth and anonymous sign-in failed
        debugPrint('❌ [AUTH] Anonymous fallback ALSO FAILED!');
        debugPrint('   Error: $anonymousError');
        debugPrint('   Stack trace: $anonymousSt');
        final errorMessage = _getErrorMessage(e.toString());
        if (!mounted) {
          debugPrint('⚪ [AUTH] Notifier disposed before propagating fallback error');
          return;
        }
        state = state.copyWith(
          isLoading: false,
          errorMessage: errorMessage,
        );
        debugPrint('🔴 [AUTH] Showing error to user: $errorMessage');
      }
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
    if (error.contains('cancelled')) {
      return 'Sign in was cancelled';
    } else if (error.contains('network')) {
      return 'Network error. Please check your connection';
    } else if (error.contains('tokens')) {
      return 'Authentication failed. Please try again';
    } else {
      return 'Sign in failed. Please try again';
    }
  }
}
