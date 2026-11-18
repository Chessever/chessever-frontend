import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final homeScreenProvider = AutoDisposeProvider<_HomeScreenController>(
  (ref) => _HomeScreenController(ref),
);

class _HomeScreenController {
  _HomeScreenController(this.ref);

  final Ref ref;

  /// Pull to refresh on the Events lists (opened from Profile).
  Future<void> onEventsPullRefresh() async {
    HapticFeedbackService.medium();
    ref.read(groupEventScreenProvider.notifier).onRefresh();
  }

  /// Pull to refresh on Home. Only Today is a live feed; My Space and
  /// Discovery refresh from their own providers when their data changes.
  Future<void> onHomePullRefresh() async {
    HapticFeedbackService.medium();
    if (ref.read(selectedForYouTabProvider) == ForYouTab.today) {
      await ref.read(forYouEventsProvider.notifier).refresh();
    }
  }
}
