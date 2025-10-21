import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/local_storage/sesions_manager/session_manager.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
            .read(groupBroadcastLocalStorage(GroupEventCategory.upcoming))
            .fetchAndSaveGroupBroadcasts(),
        ref
            .read(starredProvider(GroupEventCategory.current.name).notifier)
            .init(),
        ref
            .read(starredProvider(GroupEventCategory.upcoming.name).notifier)
            .init(),
      ]).timeout(
        const Duration(seconds: 5),
      );
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

    /// check if user is already logged in
    final sessionManager = ref.read(sessionManagerProvider);
    final isLoggedIn = await sessionManager.isLoggedIn();
    if (kDebugMode) {
      print('Is user logged in: $isLoggedIn');
    }

    // if (isLoggedIn || kDebugMode) {
    //   await Future.microtask(() async {
    //     ref.read(countryDropdownProvider);
    //   });
    //   Navigator.pushNamedAndRemoveUntil(context, '/home_screen', (_) => false);
    // } else {
    //   Navigator.pushNamedAndRemoveUntil(context, '/auth_screen', (_) => false);
    // }

    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home_screen', (_) => false);
  }
}
