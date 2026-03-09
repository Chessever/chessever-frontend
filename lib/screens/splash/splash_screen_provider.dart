import 'dart:async';
import 'dart:io';

import 'package:chessever2/e2e/e2e_config.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/local_storage/onboarding/onboarding_repository.dart';
import 'package:chessever2/repository/local_storage/sesions_manager/session_manager.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Exception thrown when network is unavailable during splash initialization
class NoNetworkException implements Exception {
  final String message;
  NoNetworkException([this.message = 'No internet connection']);

  @override
  String toString() => message;
}

final splashScreenProvider = AutoDisposeProvider<_SplashScreenProvider>((ref) {
  return _SplashScreenProvider(ref);
});

class _SplashScreenProvider {
  final Ref ref;

  _SplashScreenProvider(this.ref);

  Future<void> _warmTournamentDataInBackground() async {
    unawaited(
      Future(() async {
        try {
          await Future.wait([
            ref
                .read(groupBroadcastLocalStorage(GroupEventCategory.current))
                .fetchAndSaveGroupBroadcasts(),
            ref
                .read(groupBroadcastLocalStorage(GroupEventCategory.forYou))
                .fetchAndSaveGroupBroadcasts(),
          ]);
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Background tournament refresh failed: $e');
          }
        }
      }),
    );
  }

  Future<void> _warmPastTournamentDataInBackground() async {
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
  }

  Future<void> _routeAfterStartup(
    BuildContext context, {
    required bool isLoggedIn,
  }) async {
    if (!context.mounted) {
      DeepLinkService.notifyAppReady();
      return;
    }

    final onboardingRepo = ref.read(onboardingRepositoryProvider);
    bool hasSeenOnboarding = true;
    try {
      hasSeenOnboarding = await onboardingRepo.hasSeenOnboarding().timeout(
        const Duration(seconds: 3),
      );
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Onboarding check failed/timeout: $e');
      }
      hasSeenOnboarding = true;
    }

    if (!context.mounted) {
      DeepLinkService.notifyAppReady();
      return;
    }

    if (!hasSeenOnboarding) {
      ref.read(countryDropdownProvider);
      FlutterNativeSplash.remove();
      Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (_) => false);
      DeepLinkService.notifyAppReady();
      return;
    }

    FlutterNativeSplash.remove();

    if (isLoggedIn) {
      ref.read(countryDropdownProvider);
      ref.read(favoritePlayersProviderNew);
      Navigator.pushNamedAndRemoveUntil(context, '/home_screen', (_) => false);
    } else {
      Navigator.pushNamedAndRemoveUntil(context, '/auth_screen', (_) => false);
    }

    DeepLinkService.notifyAppReady();
  }

  /// Check if we have network connectivity by attempting DNS lookup
  Future<bool> _hasNetworkConnectivity() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    }
  }

  Future<void> runAuthenticationPreProcessor(BuildContext context) async {
    final sessionManager = ref.read(sessionManagerProvider);

    // Resolve auth token state up-front so subsequent Supabase calls don't race
    // against token refresh on cold start.
    bool isLoggedIn = false;
    try {
      isLoggedIn = await sessionManager.isLoggedIn().timeout(
        const Duration(seconds: 5),
      );
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Startup session warm-up failed/timeout: $e');
      }
      isLoggedIn = false;
    }

    if (E2eConfig.isEnabled) {
      _warmTournamentDataInBackground();
      _warmPastTournamentDataInBackground();
      if (!context.mounted) {
        DeepLinkService.notifyAppReady();
        return;
      }
      await _routeAfterStartup(context, isLoggedIn: isLoggedIn);
      return;
    }

    // Tournament data: use local cache when available to avoid blocking on
    // slow network / auth-token refresh race during cold start.
    final currentStorage = ref.read(
      groupBroadcastLocalStorage(GroupEventCategory.current),
    );
    final forYouStorage = ref.read(
      groupBroadcastLocalStorage(GroupEventCategory.forYou),
    );

    bool hasCachedData = false;
    try {
      hasCachedData = (await currentStorage.getGroupBroadcasts()).isNotEmpty;
    } catch (_) {}

    if (!hasCachedData) {
      // No cache (first launch or cleared data) — need network fetch.
      final hasNetwork = await _hasNetworkConnectivity();
      if (!hasNetwork) {
        throw NoNetworkException(
          'No internet connection. Please check your network and try again.',
        );
      }

      try {
        await Future.wait([
          currentStorage.fetchAndSaveGroupBroadcasts(),
          forYouStorage.fetchAndSaveGroupBroadcasts(),
          ref
              .read(starredProvider(GroupEventCategory.current.name).notifier)
              .init(),
          ref
              .read(starredProvider(GroupEventCategory.forYou.name).notifier)
              .init(),
        ]).timeout(const Duration(seconds: 15));
      } on TimeoutException {
        throw NoNetworkException('Connection timed out. Please try again.');
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Tournament data fetch failed: $e');
        }
        if (e.toString().contains('SocketException') ||
            e.toString().contains('Failed host lookup') ||
            e.toString().contains('No address associated')) {
          throw NoNetworkException(
            'Network error. Please check your connection.',
          );
        }
        rethrow;
      }
    } else {
      // Cache exists — proceed immediately, refresh in background.
      // Warm up starred providers (constructor calls init).
      ref.read(starredProvider(GroupEventCategory.current.name).notifier);
      ref.read(starredProvider(GroupEventCategory.forYou.name).notifier);
      _warmTournamentDataInBackground();
    }

    // Non-critical: Load past tournaments in background
    _warmPastTournamentDataInBackground();
    if (!context.mounted) {
      DeepLinkService.notifyAppReady();
      return;
    }
    await _routeAfterStartup(context, isLoggedIn: isLoggedIn);
  }
}
