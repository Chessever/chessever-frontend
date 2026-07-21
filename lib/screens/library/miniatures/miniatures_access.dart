// Free-tier access rules for Miniatures game opens.
//
// Free users may open only games whose wall-clock calendar day is **Today**
// (local). Anything before Today, or with a missing/unknown date, is locked
// and must show the premium paywall. Premium users (and while subscription
// is still loading) are never locked.
//
// Date source matches the Miniatures day headers: bare PGN days are stored
// as UTC midnight and read back in UTC so the calendar day is stable; that
// day is then compared against the viewer's local Today.

/// Whether a free user may NOT open a Miniatures game with [gameDate].
///
/// [gameDate] is [GamesTourModel.lastMoveTime] (or null when missing).
/// Pass [now] in tests to pin the local "Today" boundary.
bool isMiniatureGameLocked(
  DateTime? gameDate, {
  required bool isSubscribed,
  required bool subscriptionLoading,
  DateTime? now,
}) {
  if (isSubscribed || subscriptionLoading) return false;
  if (gameDate == null) return true;

  final reference = now ?? DateTime.now();
  final todayStart = DateTime(reference.year, reference.month, reference.day);

  // Same UTC day extraction as Miniatures section grouping.
  final utc = gameDate.toUtc();
  final gameDay = DateTime(utc.year, utc.month, utc.day);

  return gameDay.isBefore(todayStart);
}
