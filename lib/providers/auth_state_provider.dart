import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Global auth state provider that listens to Supabase auth changes
/// This is the single source of truth for authentication state
final authStateProvider = StreamProvider<AppAuthState>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);

  return authRepository.authStateChanges.map((user) {
    if (user != null) {
      return AppAuthState.authenticated(user);
    } else {
      return const AppAuthState.unauthenticated();
    }
  }).handleError((error, stackTrace) {
    return AppAuthState.error(error.toString());
  });
});

/// Convenience provider to get current user
final currentUserProvider = Provider<AppUser?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.maybeWhen(
    data: (state) => state.user,
    orElse: () => null,
  );
});

/// Convenience provider to check if user is authenticated
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.maybeWhen(
    data: (state) => state.isAuthenticated,
    orElse: () => false,
  );
});
