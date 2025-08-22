class ScrollState {
  final bool hasPerformedInitialScroll;
  final String? lastSelectedRound;
  final String? pendingScrollToRound;
  final bool isScrolling;
  final bool isUserScrolling; // New: Track if user is manually scrolling

  const ScrollState({
    this.hasPerformedInitialScroll = false,
    this.lastSelectedRound,
    this.pendingScrollToRound,
    this.isScrolling = false,
    this.isUserScrolling = false,
  });

  ScrollState copyWith({
    bool? hasPerformedInitialScroll,
    String? lastSelectedRound,
    String? pendingScrollToRound,
    bool? isScrolling,
    bool? isUserScrolling,
  }) {
    return ScrollState(
      hasPerformedInitialScroll:
          hasPerformedInitialScroll ?? this.hasPerformedInitialScroll,
      lastSelectedRound: lastSelectedRound ?? this.lastSelectedRound,
      pendingScrollToRound: pendingScrollToRound ?? this.pendingScrollToRound,
      isScrolling: isScrolling ?? this.isScrolling,
      isUserScrolling: isUserScrolling ?? this.isUserScrolling,
    );
  }
}
