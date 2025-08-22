import 'package:chessever2/screens/games_tour_screen/models/scroll_state_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final scrollStateProvider =
    StateNotifierProvider.autoDispose<ScrollStateNotifier, ScrollState>(
      (ref) => ScrollStateNotifier(),
    );

class ScrollStateNotifier extends StateNotifier<ScrollState> {
  ScrollStateNotifier() : super(const ScrollState());

  void setInitialScrollPerformed() {
    state = state.copyWith(hasPerformedInitialScroll: true);
  }

  void updateSelectedRound(String? roundId) {
    state = state.copyWith(lastSelectedRound: roundId);
  }

  void setPendingScroll(String? roundId) {
    state = state.copyWith(pendingScrollToRound: roundId);
  }

  void setScrolling(bool isScrolling) {
    state = state.copyWith(isScrolling: isScrolling);
  }

  // New: Track user scrolling state
  void setUserScrolling(bool isUserScrolling) {
    state = state.copyWith(isUserScrolling: isUserScrolling);
  }

  void reset() {
    state = const ScrollState();
  }
}