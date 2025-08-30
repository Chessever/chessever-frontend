class ScrollState {
  final bool hasPerformedInitialScroll;
  final String? lastSelectedRound;
  final String? pendingScrollToRound;
  final bool isScrolling;
  final bool isUserScrolling;
  final bool isProgrammaticScroll;
  final bool isListViewBuilt;

  const ScrollState({
    this.hasPerformedInitialScroll = false,
    this.lastSelectedRound,
    this.pendingScrollToRound,
    this.isScrolling = false,
    this.isUserScrolling = false,
    this.isProgrammaticScroll = false,
    this.isListViewBuilt = false,
  });

  ScrollState copyWith({
    bool? hasPerformedInitialScroll,
    String? lastSelectedRound,
    String? pendingScrollToRound,
    bool? isScrolling,
    bool? isUserScrolling,
    bool? isProgrammaticScroll,
    bool? isListViewBuilt,
  }) {
    return ScrollState(
      hasPerformedInitialScroll:
          hasPerformedInitialScroll ?? this.hasPerformedInitialScroll,
      lastSelectedRound: lastSelectedRound ?? this.lastSelectedRound,
      pendingScrollToRound: pendingScrollToRound ?? this.pendingScrollToRound,
      isScrolling: isScrolling ?? this.isScrolling,
      isUserScrolling: isUserScrolling ?? this.isUserScrolling,
      isProgrammaticScroll: isProgrammaticScroll ?? this.isProgrammaticScroll,
      isListViewBuilt: isListViewBuilt ?? this.isListViewBuilt,
    );
  }
}
