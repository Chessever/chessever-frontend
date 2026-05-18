import 'dart:async';

import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/screens/authentication/auth_screen_provider.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/pending_favorite_players_provider.dart';
import 'package:chessever2/screens/onboarding/player_selection_screen.dart';
import 'package:chessever2/repository/local_storage/country_man/country_man_repository.dart';
import 'package:chessever2/repository/local_storage/onboarding/onboarding_repository.dart';
import 'package:chessever2/repository/local_storage/sesions_manager/session_manager.dart';
import 'package:chessever2/e2e/e2e_config.dart';
import 'package:chessever2/utils/favorites_migration.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/services/push_notifications_service.dart';
import 'package:chessever2/revenue_cat_service/revenue_cat_service.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
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

  // Track if we've already run post-auth sync for the current user
  // This prevents duplicate runs when auth state fires multiple times
  static String? _lastSyncedUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<AppAuthState>>(authStateProvider, (previous, next) {
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
          print(
            '🔐 Auth state changed: ${authState.status} (prev: ${previousState?.status})',
          );
          print('📍 Current route: $currentRoute');
        }

        // Splash screen orchestrates the very first navigation.
        if (currentRoute == '/') {
          return;
        }

        if (authState.status == AppAuthStatus.authenticated) {
          final currentUserId = authState.user?.id;
          final previousUserId = previousState?.user?.id;
          final isAnonymous = authState.user?.isAnonymous == true;

          // Anonymous accounts are no longer allowed in the app. Redirect any
          // lingering anon session (e.g. legacy installs) to the auth screen so
          // they can sign in. Onboarding and auth screens themselves stay open
          // so existing anon favorites can be migrated by the OAuth link flow.
          if (isAnonymous) {
            const protectedRoutes = {'/', '/auth_screen', '/onboarding'};
            if (!protectedRoutes.contains(currentRoute)) {
              navigator.pushNamedAndRemoveUntil(
                '/auth_screen',
                (route) => false,
              );
            }
            return;
          }

          // Only run sync when:
          // 1. We're transitioning FROM unauthenticated/loading TO authenticated, OR
          // 2. The user ID changed (different user logged in)
          final wasNotAuthenticated =
              previousState?.status != AppAuthStatus.authenticated;
          final userChanged =
              currentUserId != null && _lastSyncedUserId != currentUserId;
          final shouldRunSync = wasNotAuthenticated || userChanged;

          unawaited(AnalyticsService.instance.syncUser(authState.user));
          if (currentUserId != null) {
            unawaited(
              PushNotificationsService.instance.loginUser(currentUserId),
            );
            if (!E2eConfig.suppressInterruptivePrompts) {
              // Prompt from auth flow as an additional safety net.
              // This covers paths where onboarding prompt might be skipped.
              unawaited(
                PushNotificationsService.instance
                    .requestPermissionIfNotGranted(),
              );
            }
          }

          if (shouldRunSync && currentUserId != null) {
            _lastSyncedUserId = currentUserId;

            // Sync user with RevenueCat for subscription management
            unawaited(
              Future(() async {
                try {
                  // If we are switching between 2 identified users without a full unauth transition,
                  // explicitly log out first to avoid aliasing/transferring purchases between accounts.
                  final switchingIdentifiedUsers =
                      previousState?.status == AppAuthStatus.authenticated &&
                      previousUserId != null &&
                      previousUserId != currentUserId;
                  if (switchingIdentifiedUsers) {
                    await RevenueCatService().logOut();
                  }

                  await RevenueCatService().logIn(currentUserId);
                  // Sync purchases and refresh subscription state after login
                  // Using syncAndRefresh() instead of separate syncPurchases() + refresh()
                  // to avoid redundant API calls
                  await ref
                      .read(subscriptionProvider.notifier)
                      .syncAndRefresh();
                } catch (e) {
                  if (kDebugMode) {
                    print('⚠️ [Auth] RevenueCat login failed: $e');
                  }
                }
              }),
            );

            // Clear cached favorites when switching accounts to avoid cross-user bleed
            if (userChanged) {
              await ref.read(favoriteEventsProvider.notifier).clearCache();
              await ref.read(favoritePlayersProviderNew.notifier).clearCache();
              ref.invalidate(favoriteEventsProvider);
              ref.invalidate(favoritePlayersProviderNew);
            }

            // User just authenticated - migrate old favorites and sync from Supabase
            unawaited(
              Future(() async {
                try {
                  if (kDebugMode) {
                    print(
                      '🔄 [Auth] User authenticated, starting favorites migration & sync...',
                    );
                  }

                  // If onboarding hasn't been completed yet (fresh session),
                  // clear any legacy favorite event data that could pollute a new account.
                  final hasSeenOnboarding = await ref
                      .read(onboardingRepositoryProvider)
                      .hasSeenOnboarding(userId: currentUserId);
                  if (!hasSeenOnboarding) {
                    await FavoritesMigration.cleanupBadMigrationDataIfNeeded();
                  }

                  // Step 0: Clear stale favorite caches (fixes duplicate UI issue)
                  // This runs once per user and forces fresh sync from Supabase
                  // Fire and forget - don't block auth flow
                  unawaited(
                    FavoritesMigration.cleanupStaleFavoritesCacheIfNeeded(),
                  );

                  // Step 1: Migrate old SharedPreferences favorites (runs only once per user)
                  await FavoritesMigration.migrateIfNeeded();

                  // Step 1.5: Merge anonymous favorites into the new account
                  // (must run before flush/sync so the merged data is visible)
                  await ref
                      .read(authStateProvider.notifier)
                      .mergeAnonymousFavorites(currentUserId);

                  // Steps 1a+1b and step 2 are independent (different Supabase tables)
                  // so run them in parallel to shave ~200-400ms off the sync chain.
                  await Future.wait([
                    // Steps 1a→1b must remain sequential (1b reads what 1a wrote)
                    Future(() async {
                      await ref
                          .read(countryManRepository)
                          .syncLocalSelectionToSupabase();
                      await ref
                          .read(countryDropdownProvider.notifier)
                          .syncFromSupabase();
                    }),
                    // Step 2: Flush any pending (pre-auth) favorite toggles
                    ref
                        .read(pendingFavoriteSelectionsProvider.notifier)
                        .flushToSupabase(),
                  ]);

                  // Step 3: Sync from Supabase (fetch latest)
                  await Future.wait([
                    ref
                        .read(favoriteEventsProvider.notifier)
                        .syncFromSupabase(),
                    ref
                        .read(favoritePlayersProviderNew.notifier)
                        .syncFromSupabase(),
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
          }

          // After OAuth completes on the auth screen, route the user into the
          // app (home or onboarding depending on whether they finished it).
          if (currentRoute == '/auth_screen') {
            final hasSeenOnboarding = await ref
                .read(onboardingRepositoryProvider)
                .hasSeenOnboarding(userId: currentUserId);

            final targetRoute =
                hasSeenOnboarding ? '/home_screen' : '/onboarding';
            navigator.pushNamedAndRemoveUntil(targetRoute, (route) => false);
            ref.read(authScreenProvider.notifier).reset();
          }
        } else if (authState.status == AppAuthStatus.unauthenticated) {
          // Clear the sync tracking when user logs out
          _lastSyncedUserId = null;
          unawaited(AnalyticsService.instance.clearUser());
          unawaited(PushNotificationsService.instance.logoutUser());
          unawaited(
            Future(() async {
              await RevenueCatService().logOut();
              // Ensure UI reflects the logged-out RevenueCat user (anonymous) state.
              await ref.read(subscriptionProvider.notifier).refresh();
            }),
          );

          // Clear favorite caches and state so the next user starts clean
          await ref.read(favoriteEventsProvider.notifier).clearCache();
          await ref.read(favoritePlayersProviderNew.notifier).clearCache();
          ref.invalidate(favoriteEventsProvider);
          ref.invalidate(favoritePlayersProviderNew);
          ref.invalidate(pendingFavoriteSelectionsProvider);
          ref.invalidate(onboardingSelectedFideIdsProvider);

          // Don't redirect if we're on splash, onboarding, or already on auth screen
          // Let splash screen handle initial navigation including onboarding check
          final protectedRoutes = {'/', '/auth_screen', '/onboarding'};
          if (!protectedRoutes.contains(currentRoute)) {
            // User was logged in and is now unauthenticated (e.g., signed out)
            await ref.read(sessionManagerProvider).clearLocalStorage();

            // Check if onboarding was seen - if not, go to onboarding, otherwise auth
            final hasSeenOnboarding =
                await ref
                    .read(onboardingRepositoryProvider)
                    .hasSeenOnboarding();

            navigator.pushNamedAndRemoveUntil(
              hasSeenOnboarding ? '/auth_screen' : '/onboarding',
              (route) => false,
            );
          }
        }
      });
    });

    return child;
  }
}
