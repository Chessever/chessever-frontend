// Free-tier access rules for Miniatures.
//
// Free users get **Today** (local): its games open, and the Games tab lists
// only Today's sections. Every earlier day is the Premium archive: opening an
// older (or undated) game, stepping the date control back, and narrowing the
// list by a date range all go through the premium paywall. Premium users (and
// while subscription is still loading) are never locked.
//
// Date source matches the Miniatures day headers: bare PGN days are stored
// as UTC midnight and read back in UTC so the calendar day is stable; that
// day is then compared against the viewer's local Today.

import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';

/// The upgrade hand-off's feature id for everything before Today in
/// Miniatures: earlier days, the date navigation, archived games. A fixed
/// identifier for the paywall analytics, never user data.
const String kMiniaturesArchiveFeatureId = 'miniatures_archive';

/// Where a Miniatures archive gate resumes once the viewer is entitled.
const String kMiniaturesReturnTo = 'library/miniatures';

/// The Premium outcome the Miniatures boundary sells (spec 5.1).
const String kMiniaturesArchiveCta = 'Explore the Miniatures archive';

/// Whether the archive (every day before Today, and the date navigation that
/// walks it) is behind Premium for this viewer. Nothing is locked while the
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

/// A loaded Miniatures list cut at the archive boundary: the games from Today
/// on, in their original order, and how many loaded games sit before it.
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

/// Whether a locked list stops paging at the archive boundary.
///
/// Pages arrive newest first, so once a loaded game predates Today every
/// Today game is already in hand and anything further would only be hidden.
/// When the order is not newest first ([newestFirst] false) Today's games can
/// sit on any page, so paging carries on; an open archive always pages.
bool miniaturesPagingStopsAtArchive({
  required bool archiveLocked,
  required bool reachedArchive,
  required bool newestFirst,
}) => archiveLocked && reachedArchive && newestFirst;

/// Whether [filter] lists its games newest first, the order the archive
/// boundary relies on to stop paging.
bool miniaturesFilterIsNewestFirst(MiniatureGamesFilter filter) =>
    filter.sort == MiniatureGamesSort.recent &&
    filter.order == MiniatureGamesSortOrder.desc;

/// Whether [filter] narrows the list by a date range. The range picker walks
/// the archive, so for a locked archive it is Premium date navigation.
bool miniaturesFilterWalksArchive(MiniatureGamesFilter filter) =>
    _hasText(filter.dateFrom) || _hasText(filter.dateTo);

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
