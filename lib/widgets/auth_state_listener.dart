import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/repository/local_storage/sesions_manager/session_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Widget that listens to auth state changes and handles navigation
/// This ensures users are redirected to appropriate screens when auth state changes
/// Uses ref.listen in build method since it's wrapping the whole app (high hierarchy)
class AuthStateListener extends ConsumerWidget {
  final Widget child;

  const AuthStateListener({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen to auth state changes - this is the proper place for high-level widgets
    // ref.listen is designed for build methods of widgets high in the hierarchy
    ref.listen<AsyncValue<AppAuthState>>(
      authStateProvider,
      (previous, next) {
        // Only handle data state changes
        next.whenData((authState) async {
          final currentRoute = ModalRoute.of(context)?.settings.name;

          if (kDebugMode) {
            print('🔐 Auth state changed: ${authState.status}');
            print('📍 Current route: $currentRoute');
          }

          // Skip navigation if we're on splash screen (initial load)
          // Splash screen handles initial navigation
          if (currentRoute == '/') {
            return;
          }

          // Handle authentication state changes AFTER splash screen
          if (authState.status == AppAuthStatus.authenticated) {
            // User just logged in
            if (currentRoute == '/auth_screen') {
              if (kDebugMode) {
                print('✅ User authenticated, navigating to home');
              }
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/home_screen',
                (route) => false,
              );
            }
          } else if (authState.status == AppAuthStatus.unauthenticated) {
            // User logged out or session expired
            if (currentRoute != '/auth_screen') {
              if (kDebugMode) {
                print('❌ User unauthenticated, navigating to auth screen');
              }

              // Clear only local storage (signOut already happened, avoid infinite loop)
              await ref.read(sessionManagerProvider).clearLocalStorage();

              // Navigate to auth screen
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/auth_screen',
                  (route) => false,
                );
              }
            }
          }
        });
      },
    );

    return child;
  }
}
