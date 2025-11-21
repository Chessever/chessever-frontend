import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/local_storage/onboarding/onboarding_repository.dart';
import 'package:chessever2/repository/local_storage/sesions_manager/session_manager.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final splashScreenProvider = AutoDisposeProvider<_SplashScreenProvider>((ref) {
  return _SplashScreenProvider(ref);
});

class _SplashScreenProvider {
  final Ref ref;

  _SplashScreenProvider(this.ref);

  Future<void> runAuthenticationPreProcessor(BuildContext context) async {
    // Fetch only critical tournament data with timeout to prevent indefinite blocking
    try {
      await Future.wait([
        // Critical: Current and upcoming tournaments (user needs these immediately)
        ref
            .read(groupBroadcastLocalStorage(GroupEventCategory.current))
            .fetchAndSaveGroupBroadcasts(),
        ref
            .read(groupBroadcastLocalStorage(GroupEventCategory.forYou))
            .fetchAndSaveGroupBroadcasts(),
        ref
            .read(starredProvider(GroupEventCategory.current.name).notifier)
            .init(),
        ref
            .read(starredProvider(GroupEventCategory.forYou.name).notifier)
            .init(),
      ]).timeout(const Duration(seconds: 5));
    } catch (e) {
      // If network is slow or fails, proceed anyway to avoid indefinite blocking
      if (kDebugMode) {
        print('⚠️ Tournament data fetch failed or timed out: $e');
      }
    }

    // Non-critical: Load past tournaments in background (defer to improve perceived speed)
    unawaited(
      Future(() async {
        try {
          await Future.wait([
            ref
                .read(groupBroadcastLocalStorage(GroupEventCategory.past))
                .fetchAndSaveGroupBroadcasts(),
            ref
                .read(starredProvider(GroupEventCategory.past.name).notifier)
                .init(),
          ]);
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Failed to load past tournaments: $e');
          }
        }
      }),
    );

    // Check authentication state - session manager will recover session if exists
    // This also triggers Supabase auth state change which the listener will pick up
    final sessionManager = ref.read(sessionManagerProvider);
    var isLoggedIn = await sessionManager.isLoggedIn();

    if (!isLoggedIn) {
      try {
        await ref.read(authStateProvider.notifier).signInAnonymously();
        isLoggedIn = true;
        if (kDebugMode) {
          print('✅ Anonymous session created for guest access');
        }
      } catch (e, st) {
        if (kDebugMode) {
          print('❌ Failed to start anonymous session: $e');
          debugPrintStack(stackTrace: st);
        }
      }
    }

    // Check if context is still valid before navigation
    if (!context.mounted) return;

    // Evaluate onboarding completion based on current user
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final onboardingRepo = ref.read(onboardingRepositoryProvider);
    final hasCompletedOnboarding = await onboardingRepo.isCompleted(userId);

    // Initial navigation - the AuthStateListener will handle subsequent auth changes
    if (!hasCompletedOnboarding) {
      // Initialize country drop-down early for recommendations
      ref.read(countryDropdownProvider);
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/onboarding',
        (_) => false,
      );
      return;
    }

    if (isLoggedIn) {
      // User is logged in - initialize country dropdown and go to home
      ref.read(countryDropdownProvider);

      // Note: Favorites migration and sync happens in AuthStateListener

      Navigator.pushNamedAndRemoveUntil(context, '/home_screen', (_) => false);
    } else {
      // User is not logged in and anonymous sign-in failed - go to auth screen
      Navigator.pushNamedAndRemoveUntil(context, '/auth_screen', (_) => false);
    }
  }
}
