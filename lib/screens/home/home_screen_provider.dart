import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final homeScreenProvider = AutoDisposeProvider<_HomeScreenController>(
  (ref) => _HomeScreenController(ref),
);

class _HomeScreenController {
  _HomeScreenController(this.ref);

  final Ref ref;

  Future<void> onPullRefresh() async {
    HapticFeedbackService.medium();
    final currentItem = ref.read(selectedBottomNavBarItemProvider);

    // Handle refresh based on current screen
    switch (currentItem) {
      case BottomNavBarItem.tournaments:
        ref.read(groupEventScreenProvider.notifier).onRefresh();
        break;
      case BottomNavBarItem.forYou:
        // Only Today is a live feed; My Space and Discovery refresh from
        // their own providers when their data changes.
        if (ref.read(selectedForYouTabProvider) == ForYouTab.today) {
          await ref.read(forYouEventsProvider.notifier).refresh();
        }
        break;
      case BottomNavBarItem.library:
        debugPrint('Refreshing library...');
        break;
    }
  }
}
