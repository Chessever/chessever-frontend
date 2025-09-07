import 'package:chessever2/screens/tour_detail/games_tour/models/scroll_state_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:async';

final scrollStateProvider =
StateNotifierProvider<ScrollStateNotifier, ScrollState>(
      (ref) => ScrollStateNotifier(),
);

class ScrollStateNotifier extends StateNotifier<ScrollState> {
  ScrollStateNotifier() : super(const ScrollState());

  Timer? _debounceTimer;
  Timer? _scrollEndTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollEndTimer?.cancel();
    super.dispose();
  }

  void setListViewBuilt() {
    if (mounted && !state.isListViewBuilt) {
      state = state.copyWith(isListViewBuilt: true);
    }
  }

  void setInitialScrollPerformed() {
    if (mounted && !state.hasPerformedInitialScroll) {
      state = state.copyWith(hasPerformedInitialScroll: true);
    }
  }

  void updateSelectedRound(String? roundId) {
    if (mounted && state.lastSelectedRound != roundId) {
      state = state.copyWith(lastSelectedRound: roundId);
    }
  }

  void setPendingScroll(String? roundId) {
    if (mounted && state.pendingScrollToRound != roundId) {
      state = state.copyWith(pendingScrollToRound: roundId);
    }
  }

  /// Debounced scroll state update to prevent excessive state changes
  void setScrolling(bool isScrolling) {
    if (!mounted) return;

    if (isScrolling) {
      // Cancel any pending scroll end timer
      _scrollEndTimer?.cancel();

      if (!state.isScrolling) {
        state = state.copyWith(isScrolling: true);
      }
    } else {
      // Debounce scroll end to avoid flickering
      _scrollEndTimer?.cancel();
      _scrollEndTimer = Timer(const Duration(milliseconds: 50), () {
        if (mounted && state.isScrolling) {
          state = state.copyWith(isScrolling: false);
        }
      });
    }
  }

  /// Debounced user scrolling state to reduce unnecessary updates
  void setUserScrolling(bool isUserScrolling) {
    if (!mounted) return;

    _debounceTimer?.cancel();

    if (isUserScrolling) {
      if (!state.isUserScrolling) {
        state = state.copyWith(isUserScrolling: true);
      }
    } else {
      // Debounce the end of user scrolling
      _debounceTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted && state.isUserScrolling) {
          state = state.copyWith(isUserScrolling: false);
        }
      });
    }
  }

  void setProgrammaticScroll(bool isProgrammaticScroll) {
    if (mounted && state.isProgrammaticScroll != isProgrammaticScroll) {
      state = state.copyWith(isProgrammaticScroll: isProgrammaticScroll);
    }
  }

  /// Atomic reset of scroll flags with validation
  void resetScrollFlags() {
    if (!mounted) return;

    _debounceTimer?.cancel();
    _scrollEndTimer?.cancel();

    state = state.copyWith(
      isScrolling: false,
      isUserScrolling: false,
      pendingScrollToRound: null,
      isProgrammaticScroll: false,
    );
  }

  /// Atomic preparation for programmatic scroll
  void prepareForProgrammaticScroll(String roundId) {
    if (!mounted) return;

    // Cancel any pending debounced operations
    _debounceTimer?.cancel();
    _scrollEndTimer?.cancel();

    state = state.copyWith(
      isScrolling: true,
      isUserScrolling: false,
      isProgrammaticScroll: true,
      lastSelectedRound: roundId,
      pendingScrollToRound: roundId,
    );
  }

  /// Complete programmatic scroll with cleanup
  void completeProgrammaticScroll() {
    if (!mounted) return;

    state = state.copyWith(
      isScrolling: false,
      isProgrammaticScroll: false,
      pendingScrollToRound: null,
    );
  }

  /// Batch update multiple scroll states atomically
  void updateScrollState({
    bool? isScrolling,
    bool? isUserScrolling,
    bool? isProgrammaticScroll,
    String? selectedRound,
    String? pendingScrollToRound,
  }) {
    if (!mounted) return;

    // Cancel timers if we're doing a direct update
    if (isScrolling != null || isUserScrolling != null) {
      _debounceTimer?.cancel();
      _scrollEndTimer?.cancel();
    }

    state = state.copyWith(
      isScrolling: isScrolling,
      isUserScrolling: isUserScrolling,
      isProgrammaticScroll: isProgrammaticScroll,
      lastSelectedRound: selectedRound,
      pendingScrollToRound: pendingScrollToRound,
    );
  }

  /// Safe reset with cleanup
  void reset() {
    if (!mounted) return;

    _debounceTimer?.cancel();
    _scrollEndTimer?.cancel();

    state = const ScrollState();
  }

  /// Check if it's safe to perform scroll operations
  bool get canScroll => mounted &&
      state.isListViewBuilt &&
      !state.isProgrammaticScroll;

  /// Check if user interaction should be processed
  bool get shouldProcessUserInput => mounted &&
      !state.isProgrammaticScroll &&
      !state.isScrolling;
}