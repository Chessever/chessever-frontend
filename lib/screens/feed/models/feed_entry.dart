import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:flutter/foundation.dart';

/// One page of the Feed: a replaying game, a Lichess puzzle, a ChessEver
/// News article, or (for viewers who see ads) an ad between them.
@immutable
sealed class FeedEntry {
  const FeedEntry();

  /// Stable across rebuilds and recaptions, so a page keeps its state (and
  /// its place in the PageView) while the list around it grows.
  String get key;
}

final class FeedGameEntry extends FeedEntry {
  const FeedGameEntry(this.item);

  final FeedItem item;

  @override
  String get key => 'game:${item.game.gameId}';
}

final class FeedPuzzleEntry extends FeedEntry {
  const FeedPuzzleEntry(this.puzzle);

  final FeedPuzzle puzzle;

  @override
  String get key => 'puzzle:${puzzle.id}';
}

final class FeedNewsEntry extends FeedEntry {
  const FeedNewsEntry(this.news);

  final FeedNews news;

  @override
  String get key => 'news:${news.id}';
}

/// An ad on a page of its own, laid between posts by [withFeedAds]. Never
/// part of [composeFeedEntries]'s arrangement.
final class FeedAdEntry extends FeedEntry {
  const FeedAdEntry(this.after);

  /// The key of the post it follows: unique in an arrangement, and gone with
  /// it when a refresh draws new posts.
  final String after;

  @override
  String get key => 'ad:$after';
}

/// An ad page follows every this many posts.
const int kFeedAdEvery = 5;

/// [entries] with an ad page after every [every]th post, only ever between
/// two posts: never first, and never last (the tail follows the last post).
/// Ads in [withdrawn] (by [FeedAdEntry.key]) are left out.
List<FeedEntry> withFeedAds(
  List<FeedEntry> entries, {
  int every = kFeedAdEvery,
  Set<String> withdrawn = const {},
}) {
  if (every <= 0 || entries.length <= every) return entries;
  final out = <FeedEntry>[];
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    out.add(entry);
    final posts = i + 1;
    if (posts % every == 0 && posts < entries.length) {
      final ad = FeedAdEntry(entry.key);
      if (!withdrawn.contains(ad.key)) out.add(ad);
    }
  }
  return List.unmodifiable(out);
}

/// Page [index] of [pages] as an index into the posts under them: a post's
/// own index, the next post's for an ad page, and past the last page (the
/// tail) as far beyond the posts as it is beyond the pages.
int feedPostIndexAt(List<FeedEntry> pages, int index) {
  var ads = 0;
  final end = index.clamp(0, pages.length);
  for (var i = 0; i < end; i++) {
    if (pages[i] is FeedAdEntry) ads++;
  }
  return index - ads;
}

/// A puzzle joins the feed after every this many games.
const int kFeedPuzzleEvery = 4;

/// A news article joins the feed after every this many games.
const int kFeedNewsEvery = 6;

/// Weaves [puzzles] and [news] between [games]: a puzzle after every
/// [puzzleEvery]th game and an article after every [newsEvery]th, each only
/// while one is left to show. Games always keep their own order.
///
/// Pages the viewer has already reached must not move under them, so
/// `previous[0..frozenThrough]` is kept exactly as it was — puzzles and news
/// that arrive late start at the next free slot after it. Game entries in
/// that prefix are refreshed from [games] (a recaptioned item replaces its
/// stale copy in place). When [games] no longer starts with the prefix's
/// games (the feed was refreshed), the prefix is dropped and the feed is
/// composed afresh.
List<FeedEntry> composeFeedEntries({
  required List<FeedItem> games,
  List<FeedPuzzle> puzzles = const [],
  List<FeedNews> news = const [],
  List<FeedEntry> previous = const [],
  int frozenThrough = -1,
  int puzzleEvery = kFeedPuzzleEvery,
  int newsEvery = kFeedNewsEvery,
}) {
  final out = <FeedEntry>[];
  final usedPuzzles = <String>{};
  final usedNews = <int>{};
  var placedGames = 0;

  // ---------------------------------------------------------- frozen prefix
  final keep = frozenThrough < 0
      ? 0
      : (frozenThrough + 1).clamp(0, previous.length);
  var prefixValid = true;
  for (var i = 0; i < keep && prefixValid; i++) {
    final entry = previous[i];
    switch (entry) {
      case FeedGameEntry(:final item):
        if (placedGames >= games.length ||
            games[placedGames].game.gameId != item.game.gameId) {
          prefixValid = false;
          break;
        }
        out.add(FeedGameEntry(games[placedGames]));
        placedGames++;
      case FeedPuzzleEntry(:final puzzle):
        usedPuzzles.add(puzzle.id);
        out.add(entry);
      case FeedNewsEntry(news: final article):
        usedNews.add(article.id);
        out.add(entry);
      // Laid over an arrangement, never part of one ([withFeedAds]).
      case FeedAdEntry():
        break;
    }
  }
  if (!prefixValid) {
    out.clear();
    usedPuzzles.clear();
    usedNews.clear();
    placedGames = 0;
  }

  var puzzleCursor = 0;
  FeedPuzzle? nextPuzzle() {
    while (puzzleCursor < puzzles.length) {
      final candidate = puzzles[puzzleCursor++];
      if (usedPuzzles.add(candidate.id)) return candidate;
    }
    return null;
  }

  var newsCursor = 0;
  FeedNews? nextNews() {
    while (newsCursor < news.length) {
      final candidate = news[newsCursor++];
      if (usedNews.add(candidate.id)) return candidate;
    }
    return null;
  }

  /// Slots that open after game number [count] (1-based). [skipPuzzle] /
  /// [skipNews] are set when the frozen prefix already filled that slot.
  void fillSlots(int count, {bool skipPuzzle = false, bool skipNews = false}) {
    if (count <= 0) return;
    if (!skipPuzzle && puzzleEvery > 0 && count % puzzleEvery == 0) {
      final puzzle = nextPuzzle();
      if (puzzle != null) out.add(FeedPuzzleEntry(puzzle));
    }
    if (!skipNews && newsEvery > 0 && count % newsEvery == 0) {
      final article = nextNews();
      if (article != null) out.add(FeedNewsEntry(article));
    }
  }

  // The prefix may end right after a game whose slots were still empty when
  // it froze (nothing had loaded yet): those slots are still open.
  if (placedGames > 0) {
    var puzzleAfterLastGame = false;
    var newsAfterLastGame = false;
    for (var i = out.length - 1; i >= 0; i--) {
      final entry = out[i];
      if (entry is FeedGameEntry) break;
      if (entry is FeedPuzzleEntry) puzzleAfterLastGame = true;
      if (entry is FeedNewsEntry) newsAfterLastGame = true;
    }
    // Only when nothing after the prefix's last game is frozen yet: a frozen
    // news page after it means the puzzle slot was passed over for good.
    final lastIsGame = out.isNotEmpty && out.last is FeedGameEntry;
    if (lastIsGame || (puzzleAfterLastGame && !newsAfterLastGame)) {
      fillSlots(
        placedGames,
        skipPuzzle: puzzleAfterLastGame,
        skipNews: newsAfterLastGame,
      );
    }
  }

  for (var i = placedGames; i < games.length; i++) {
    out.add(FeedGameEntry(games[i]));
    fillSlots(i + 1);
  }
  return List.unmodifiable(out);
}

/// How many games sit at or before [index] in [entries], minus one: the
/// index into the game list of the last game the viewer has reached. -1 when
/// no game is at or before it.
int feedGameIndexAt(List<FeedEntry> entries, int index) {
  var games = 0;
  final end = index.clamp(-1, entries.length - 1);
  for (var i = 0; i <= end; i++) {
    if (entries[i] is FeedGameEntry) games++;
  }
  return games - 1;
}
