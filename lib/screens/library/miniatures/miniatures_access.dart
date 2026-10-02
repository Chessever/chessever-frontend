// Free-tier access rules for Miniatures.
//
// Everyone browses the same Miniatures list: every day, every filter. What a
// free account goes through the premium guard for is OPENING a game from
// before Today (or an undated one). Premium users (and while subscription is
// still loading) are never locked.
//
// Date source matches the Miniatures day headers: bare PGN days are stored
// as UTC midnight and read back in UTC so the calendar day is stable; that
// day is then compared against the viewer's local Today.

/// The upgrade hand-off's feature id for opening a Miniatures game from
/// before Today. A fixed identifier for the paywall analytics, never user
/// data.
const String kMiniaturesArchiveFeatureId = 'miniatures_archive';

/// Where a Miniatures archive gate resumes once the viewer is entitled.
const String kMiniaturesReturnTo = 'library/miniatures';

/// Whether opening games from before Today is behind Premium for this
/// viewer. Nothing is locked while the
/// subscription is still loading, so a subscriber never sees a lock flash.
bool isMiniaturesArchiveLocked({
  required bool isSubscribed,
  required bool subscriptionLoading,
}) => !isSubscribed && !subscriptionLoading;

/// Whether a miniature dated [gameDate] belongs to the archive: its calendar
/// day is before the viewer's local Today, or it has no date at all.
///
/// Pass [now] in tests to pin the local "Today" boundary.
bool isMiniatureArchiveDay(DateTime? gameDate, {DateTime? now}) {
  if (gameDate == null) return true;

  final reference = now ?? DateTime.now();
  final todayStart = DateTime(reference.year, reference.month, reference.day);

  // Same UTC day extraction as Miniatures section grouping.
  final utc = gameDate.toUtc();
  final gameDay = DateTime(utc.year, utc.month, utc.day);

  return gameDay.isBefore(todayStart);
}

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
  final archiveLocked = isMiniaturesArchiveLocked(
    isSubscribed: isSubscribed,
    subscriptionLoading: subscriptionLoading,
  );
  if (!archiveLocked) return false;
  return isMiniatureArchiveDay(gameDate, now: now);
}

/// A loaded Miniatures list cut at Today: the games from Today on, in their
/// original order, and how many loaded games sit before it. The board a free
/// account opens walks only the Today part.
({List<T> today, int archived}) splitMiniaturesAtToday<T>(
  Iterable<T> games,
  DateTime? Function(T game) dateOf, {
  DateTime? now,
}) {
  final today = <T>[];
  var archived = 0;
  for (final game in games) {
    if (isMiniatureArchiveDay(dateOf(game), now: now)) {
      archived++;
    } else {
      today.add(game);
    }
  }
  return (today: today, archived: archived);
}
