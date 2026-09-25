import 'package:chessever2/repository/gamebase/collections/collections_models.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/widgets/feed_format.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The one line under each hub tile's title (My Likes, My Prep, Feed,
// Collection): what is behind the tile, in numbers when they are known.
//
// Every function here is pure and answers from the first frame: while its
// data is loading, failed or unknown it returns the tile's fallback, and the
// real line replaces it in one frame when the data lands. A value that is
// refreshing keeps its last line.

/// "1 game", "12 games", "1,284 games": a count and its noun, the figure
/// grouped from 1,000 and shortened from a million ([formatCompactCount]).
String _count(int n, String one, String many) =>
    n == 1 ? '1 $one' : '${formatCompactCount(n)} $many';

/// My Likes as the tile reads it: how many games are liked, and how many of
/// them today (the local calendar day of [now]).
///
/// Built to be the selector of `likedGamesProvider.select(likesSummary)`,
/// so a tag written on a liked game (same counts) does not rebuild the tile.
/// Loading and error states pass through; a refresh keeps its last counts.
AsyncValue<(int total, int today)> likesSummary(
  AsyncValue<List<SavedAnalysis>> likes, {
  DateTime? now,
}) {
  return likes.whenData((list) {
    final day = (now ?? DateTime.now()).toLocal();
    var today = 0;
    for (final like in list) {
      final at = like.createdAt.toLocal();
      if (at.year == day.year && at.month == day.month && at.day == day.day) {
        today++;
      }
    }
    return (list.length, today);
  });
}

/// "128 games · 2 today", "128 games", "1 game", "No likes yet";
/// "Tap to view" until the likes are read (and for a read that failed).
String hubLikesCaption(AsyncValue<(int total, int today)> summary) {
  final counts = summary.valueOrNull;
  if (counts == null) return kHubTileCaption;
  final (total, today) = counts;
  if (total <= 0) return 'No likes yet';
  final games = _count(total, 'game', 'games');
  return today > 0 ? '$games · ${formatCompactCount(today)} today' : games;
}

/// My Prep: the viewer's own databases ("3 databases", "1 database") once
/// the folders are read ([settled]); with none, or for a guest, the master
/// database's size ("9.8M master games"). "Your databases" while that
/// total is loading or failed, and while a signed-in viewer's folders are
/// still being read.
String hubPrepCaption({
  required bool guest,
  required bool settled,
  required int databases,
  AsyncValue<int>? masterTotal,
}) {
  const fallback = 'Your databases';
  if (!guest) {
    if (!settled) return fallback;
    if (databases > 0) return _count(databases, 'database', 'databases');
  }
  final total = masterTotal?.valueOrNull;
  if (total == null || total <= 0) return fallback;
  return '${formatCompactCount(total)} master games';
}

/// Feed: the players of the game Feed opens on ("Gukesh vs Nakamura"), by
/// surname; "Games and news" before Feed has a first page cached.
String hubFeedCaption(FeedItem? item) {
  const fallback = 'Games and news';
  if (item == null) return fallback;
  final white = feedSurname(item.game.whitePlayer.name);
  final black = feedSurname(item.game.blackPlayer.name);
  if (white.isEmpty || black.isEmpty) return fallback;
  return '$white vs $black';
}

/// Collection: what the team has published, by kind. "6 events · 2 books",
/// "6 annotated events" (events alone), "2 books", "1 book", "Nothing
/// published yet"; "Tap to view" until the list is read (and for a read
/// that failed).
String hubCollectionsCaption(AsyncValue<List<Collection>> collections) {
  final list = collections.valueOrNull;
  if (list == null) return kHubTileCaption;
  final events = list.where((c) => c.kind == CollectionKind.event).length;
  final books = list.length - events;
  if (events == 0 && books == 0) return 'Nothing published yet';
  if (books == 0) {
    return _count(events, 'annotated event', 'annotated events');
  }
  if (events == 0) return _count(books, 'book', 'books');
  return '${_count(events, 'event', 'events')} · '
      '${_count(books, 'book', 'books')}';
}
