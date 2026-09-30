import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:flutter/foundation.dart';

/// One page of the Feed: a replaying game, a Lichess puzzle, or a ChessEver
/// News article.
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
