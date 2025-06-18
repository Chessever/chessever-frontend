import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Supabase client provider
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

// Auth repository provider
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return AuthRepository(supabase: supabase);
});

// Auth state stream provider
final authStateStreamProvider = StreamProvider<AppUser?>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return repository.authStateChanges;
});

// Auth state notifier
final authStateProvider = StateNotifierProvider<AuthNotifier, AppAuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthNotifier(repository);
});

// Current user provider
final currentUserProvider = Provider<AppUser?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.user;
});

// Authentication status provider
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.isAuthenticated;
});

class AuthNotifier extends StateNotifier<AppAuthState> {
  final AuthRepository _repository;

  AuthNotifier(this._repository) : super(const AppAuthState.initial()) {
    _init();
  }

  void _init() {
    // Initialize with current user if exists
    final currentUser = _repository.currentUser;
    if (currentUser != null) {
      state = AppAuthState.authenticated(currentUser);
    } else {
      state = const AppAuthState.unauthenticated();
    }

    // Listen to auth changes
    _repository.authStateChanges.listen(
          (user) {
        if (user != null) {
          state = AppAuthState.authenticated(user);
        } else {
          state = const AppAuthState.unauthenticated();
        }
      },
      onError: (error) {
        state = AppAuthState.error(error.toString());
      },
    );
  }

  Future<void> signInWithGoogle() async {
    state = const AppAuthState.loading();
    try {
      final user = await _repository.signInWithGoogle();
      state = AppAuthState.authenticated(user);
    } catch (e) {
      state = AppAuthState.error(e.toString());
    }
  }

  Future<void> signInWithApple() async {
    state = const AppAuthState.loading();
    try {
      final user = await _repository.signInWithApple();
      state = AppAuthState.authenticated(user);
    } catch (e) {
      state = AppAuthState.error(e.toString());
    }
  }

  Future<void> signOut() async {
    state = const AppAuthState.loading();
    try {
      await _repository.signOut();
      state = const AppAuthState.unauthenticated();
    } catch (e) {
      state = AppAuthState.error(e.toString());
    }
  }

  Future<void> deleteAccount() async {
    state = const AppAuthState.loading();
    try {
      await _repository.deleteAccount();
      state = const AppAuthState.unauthenticated();
    } catch (e) {
      state = AppAuthState.error(e.toString());
    }
  }

  void clearError() {
    if (state.hasError) {
      state = const AppAuthState.unauthenticated();
    }
  }
}