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
    //Fetch all tournament
    await Future.wait([
      ref
          .read(groupBroadcastLocalStorage(GroupEventCategory.current))
          .fetchAndSaveGroupBroadcasts(),
      ref
          .read(groupBroadcastLocalStorage(GroupEventCategory.upcoming))
          .fetchAndSaveGroupBroadcasts(),
      ref
          .read(groupBroadcastLocalStorage(GroupEventCategory.past))
          .fetchAndSaveGroupBroadcasts(),
      ref
          .read(starredProvider(GroupEventCategory.current.name).notifier)
          .init(),
      ref
          .read(starredProvider(GroupEventCategory.upcoming.name).notifier)
          .init(),
      ref.read(starredProvider(GroupEventCategory.past.name).notifier).init(),
    ]);

    /// check if user   is already logged in
    final sessionManager = ref.read(sessionManagerProvider);
    final isLoggedIn = await sessionManager.isLoggedIn();
    print('Is user logged in: $isLoggedIn');

    if (isLoggedIn || kDebugMode) {
      Navigator.pushNamedAndRemoveUntil(context, '/home_screen', (_) => false);
    } else {
      Navigator.pushNamedAndRemoveUntil(context, '/auth_screen', (_) => false);
    }
  }
}
