import 'package:chessever2/screens/tour_detail/games_tour/models/scroll_state_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final scrollStateProvider =
    StateNotifierProvider.autoDispose<ScrollStateNotifier, ScrollState>(
      (ref) => ScrollStateNotifier(),
    );

class ScrollStateNotifier extends StateNotifier<ScrollState> {
  ScrollStateNotifier() : super(const ScrollState());

  void setListViewBuilt() {
    state = state.copyWith(isListViewBuilt: true);
  }

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

  void setUserScrolling(bool isUserScrolling) {
    state = state.copyWith(isUserScrolling: isUserScrolling);
  }

  void setProgrammaticScroll(bool isProgrammaticScroll) {
    state = state.copyWith(isProgrammaticScroll: isProgrammaticScroll);
  }

  void resetScrollFlags() {
    state = state.copyWith(
      isScrolling: false,
      isUserScrolling: false,
      pendingScrollToRound: null,
      isProgrammaticScroll: false,
    );
  }

  void prepareForProgrammaticScroll(String roundId) {
    state = state.copyWith(
      isScrolling: true,
      isUserScrolling: false,
      isProgrammaticScroll: true,
      lastSelectedRound: roundId,
      pendingScrollToRound: roundId,
    );
  }

  void completeProgrammaticScroll() {
    state = state.copyWith(
      isScrolling: false,
      isProgrammaticScroll: false,
      pendingScrollToRound: null,
    );
  }

  void reset() {
    state = const ScrollState();
  }
}
