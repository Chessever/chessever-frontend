import 'dart:async';

import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Global auth state provider that listens to Supabase auth changes.
/// Converts raw Supabase auth events into [AppAuthState] values and surfaces
/// stream errors to the UI as error states instead of throwing.
final authStateProvider = StreamProvider<AppAuthState>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);

  return Stream<AppAuthState>.multi((controller) {
    final sub = authRepository.authStateChanges.listen(
      (user) {
        if (user != null) {
          controller.add(AppAuthState.authenticated(user));
        } else {
          controller.add(const AppAuthState.unauthenticated());
        }
      },
      onError: (error, stackTrace) {
        controller.add(AppAuthState.error(error.toString()));
      },
    );

    controller.onCancel = () => sub.cancel();
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
