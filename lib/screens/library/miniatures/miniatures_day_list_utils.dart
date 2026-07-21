/// Whether a collapsible day-section list should request the next page after a
/// layout change (e.g. every day collapsed so content no longer fills the
/// viewport). Matches Countrymen / Favorites Games tabs.
///
/// [maxScrollExtent] ≤ 0 means content fits the viewport entirely — collapse
/// can leave `hasMore` stranded with no scroll event left to fire.
bool miniaturesListNeedsMoreAfterLayout({
  required double maxScrollExtent,
  required double pixels,
  required double viewportDimension,
}) {
  if (maxScrollExtent <= 0) return true;
  return maxScrollExtent - pixels <= viewportDimension;
}

/// Date-section header label for Miniatures Games / scorecard.
///
/// Intentionally **date only** — never append an in-memory game count. Loaded
/// pages are a partial subset of the day under active filters, so
/// `dateGames.length` undercounts and misleads. A cheap isolative per-day
/// total for arbitrary filters is not available on the gamebase miniatures
/// path; omit the counter rather than show a wrong number.
String miniatureDateHeaderLabel(String dateLabel) => dateLabel;
