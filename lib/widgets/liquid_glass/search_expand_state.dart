/// Pure expand/collapse state for on-demand island search chrome.
///
/// Progress / expanded flags drive horizontal-only expand animations.
/// Unit-tested without UI.
class SearchExpandState {
  const SearchExpandState({
    this.expanded = false,
    this.query = '',
  });

  final bool expanded;
  final String query;

  bool get hasQuery => query.trim().isNotEmpty;

  SearchExpandState copyWith({bool? expanded, String? query}) {
    return SearchExpandState(
      expanded: expanded ?? this.expanded,
      query: query ?? this.query,
    );
  }

  SearchExpandState expand() => copyWith(expanded: true);

  SearchExpandState collapse({bool clearQuery = false}) => SearchExpandState(
        expanded: false,
        query: clearQuery ? '' : query,
      );

  SearchExpandState toggle() =>
      expanded ? collapse() : expand();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchExpandState &&
          runtimeType == other.runtimeType &&
          expanded == other.expanded &&
          query == other.query;

  @override
  int get hashCode => Object.hash(expanded, query);
}

/// Pure mapper for horizontal expand width factor.
///
/// [progress] 0 = collapsed circle, 1 = full-width field.
double searchExpandWidthFactor(double progress) {
  final p = progress.clamp(0.0, 1.0);
  return p;
}

/// Target width for an expanding search island given available space.
double searchExpandTargetWidth({
  required double available,
  required bool expanded,
  double collapsedSize = 40,
  double maxExpandedFraction = 1.0,
}) {
  if (!expanded) return collapsedSize;
  final maxW = available * maxExpandedFraction;
  return maxW.clamp(collapsedSize, available);
}
