import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/local_storage/sesions_manager/session_manager.dart';
import 'package:chessever2/screens/tournaments/tournament_screen.dart';
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
    await Future.wait([
      ref
          .read(groupBroadcastLocalStorage(TournamentCategory.current))
          .fetchAndSaveGroupBroadcasts(),
      ref
          .read(groupBroadcastLocalStorage(TournamentCategory.upcoming))
          .fetchAndSaveGroupBroadcasts(),
    ]);

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
