import 'package:chessever2/screens/tournaments/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/tournaments/widget/bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final homeScreenProvider = AutoDisposeProvider<_HomeScreenController>(
  (ref) => _HomeScreenController(ref),
);

class _HomeScreenController {
  _HomeScreenController(this.ref);

  final Ref ref;

  Future<void> onPullRefresh() async {
    final currentItem = ref.read(selectedBottomNavBarItemProvider);

    // Handle refresh based on current screen
    switch (currentItem) {
      case BottomNavBarItem.tournaments:
        ref.read(groupEventScreenProvider.notifier).onRefresh();
        break;
      case BottomNavBarItem.calendar:
        debugPrint('Refreshing calendar...');
        break;
      case BottomNavBarItem.library:
        debugPrint('Refreshing library...');
        break;
    }
  }
}
