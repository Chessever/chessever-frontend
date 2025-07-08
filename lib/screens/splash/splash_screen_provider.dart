import 'package:chessever2/repository/local_storage/sesions_manager/session_manager.dart';
import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final splashScreenProvider = AutoDisposeProvider<_SplashScreenProvider>((ref) {
  return _SplashScreenProvider(ref);
});

class _SplashScreenProvider {
  final Ref ref;

  _SplashScreenProvider(this.ref);

  Future<void> runAuthenticationPreProcessor(BuildContext context) async {
    //Fetch all tournament
    await ref.read(tourLocalStorageProvider).fetchAndSaveTournament();
    //Fetch all starred tournament
    ref.read(starredProvider.notifier).init();

    /// check if user   is already logged in
    final sessionManager = ref.read(sessionManagerProvider);
    final isLoggedIn = await sessionManager.isLoggedIn();
    if (isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/home_screen');
    } else {
      Navigator.pushReplacementNamed(context, '/auth_screen');
    }
  }
}
