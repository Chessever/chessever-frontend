import 'dart:async';

import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/pending_favorite_players_provider.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/onboarding/onboarding_repository.dart';
import 'package:chessever2/repository/local_storage/sesions_manager/session_manager.dart';
import 'package:chessever2/utils/favorites_migration.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Widget that listens to auth state changes and handles navigation.
/// Receives the root [navigatorKey] so we can interact with the app navigator
/// even though this listener wraps the entire [MaterialApp].
class AuthStateListener extends ConsumerWidget {
  const AuthStateListener({
    required this.child,
    required this.navigatorKey,
    super.key,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<AppAuthState>>(
      authStateProvider,
      (previous, next) {
        next.whenData((authState) async {
          final previousState = previous?.valueOrNull;
          final navigator = navigatorKey.currentState;
          final navigatorContext = navigatorKey.currentContext;
          if (navigator == null || navigatorContext == null) {
            if (kDebugMode) {
              print('⚠️ Navigator not ready yet - skipping auth navigation');
            }
            return;
          }

          final currentRoute =
              ModalRoute.of(navigatorContext)?.settings.name ?? '';

          if (kDebugMode) {
            print('🔐 Auth state changed: ${authState.status}');
            print('📍 Current route: $currentRoute');
          }

          // Splash screen orchestrates the very first navigation.
          if (currentRoute == '/') {
            return;
          }

          if (authState.status == AppAuthStatus.authenticated) {
            unawaited(
              AnalyticsService.instance.syncUser(authState.user),
            );
            // User just authenticated - migrate old favorites and sync from Supabase
            unawaited(
              Future(() async {
                try {
                  if (kDebugMode) {
                    print('🔄 [Auth] User authenticated, starting favorites migration & sync...');
                  }

                  // Step 1: Migrate old SharedPreferences favorites (runs only once)
                  await FavoritesMigration.migrateIfNeeded();

                  // Step 1b: Sync country selection from Supabase (fetch user's saved selection)
                  await ref.read(countryDropdownProvider.notifier).syncFromSupabase();

                  // Step 2: Flush any pending (pre-auth) favorite toggles
                  await ref
                      .read(pendingFavoriteSelectionsProvider.notifier)
                      .flushToSupabase();

                  // Step 3: Sync from Supabase (fetch latest)
                  await Future.wait([
                    ref.read(favoriteEventsProvider.notifier).syncFromSupabase(),
                    ref.read(favoritePlayersProviderNew.notifier).syncFromSupabase(),
                  ]);

                  // Step 4: Invalidate the old player provider to trigger reload from Supabase
                  ref.invalidate(favoritePlayersNotifierProvider);

                  if (kDebugMode) {
                    print('✅ [Auth] Favorites migration & sync complete');
                  }
                } catch (e, st) {
                  if (kDebugMode) {
                    print('⚠️ [Auth] Failed to sync favorites: $e');
                    print('Stack: $st');
                  }
                  // Don't rethrow - shouldn't block authentication flow
                }
              }),
            );

            final hasCompletedOnboarding = await ref
                .read(onboardingRepositoryProvider)
                .isCompleted(authState.user?.id);
            final targetRoute =
                hasCompletedOnboarding ? '/home_screen' : '/onboarding';

            if (currentRoute == '/auth_screen') {
              navigator.pushNamedAndRemoveUntil(
                targetRoute,
                (route) => false,
              );
            }
          } else if (authState.status == AppAuthStatus.unauthenticated) {
            unawaited(AnalyticsService.instance.clearUser());
            if (currentRoute != '/auth_screen') {
              await ref.read(sessionManagerProvider).clearLocalStorage();
              navigator.pushNamedAndRemoveUntil(
                '/auth_screen',
                (route) => false,
              );
            }
          } else if (authState.status == AppAuthStatus.error &&
              authState.errorMessage != null &&
              authState.errorMessage!.isNotEmpty &&
              (previousState?.status != AppAuthStatus.error ||
                  previousState?.errorMessage != authState.errorMessage)) {
            ScaffoldMessenger.of(navigatorContext)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(content: Text(authState.errorMessage!)),
              );
          }
        });
      },
    );

    return child;
  }
}
