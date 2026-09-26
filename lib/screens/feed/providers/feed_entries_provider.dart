import 'dart:math' as math;

import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Feed tab as pages: [feedProvider]'s games with a ChessEver News
/// article after every [kFeedNewsEvery], once one has loaded. Puzzles live
/// in their own tab ([puzzleTabProvider]).
///
/// Games never wait on news: the first page is exactly the games' first
/// page, and articles slot in behind the viewer as they arrive. Pages the
/// viewer has reached are frozen ([markSeen]) so a late article can never
/// shift the page under their thumb. After a refresh the news slots open
/// with the articles the viewer has not reached yet.
///
/// Loading, errors and paging stay on [feedProvider]; this provider only
/// arranges what it has.
final feedEntriesProvider =
    NotifierProvider<FeedEntriesNotifier, List<FeedEntry>>(
      FeedEntriesNotifier.new,
    );

class FeedEntriesNotifier extends Notifier<List<FeedEntry>> {
  List<FeedEntry> _last = const [];
  int _frozenThrough = -1;

  /// Articles the viewer reached in an arrangement a refresh has replaced.
  /// The next arrangement opens its news slots with the ones not reached
  /// yet ([feedNewsUnseenFirst]), so a refresh is new past its games too.
  final Set<int> _newsReached = <int>{};

  @override
  List<FeedEntry> build() {
    final games = ref.watch(feedProvider).valueOrNull ?? const [];
    if (games.isEmpty) {
      // A refresh (or a failed load) starts the arrangement over.
      _retire();
      return _last;
    }
    // A refresh landed: a new first game.
    final first = _last.isEmpty ? null : _last.first;
    if (first is FeedGameEntry &&
        first.item.game.gameId != games.first.game.gameId) {
      _retire();
    }
    final news = feedNewsUnseenFirst(
      ref.watch(feedNewsProvider).valueOrNull ?? const [],
      _newsReached,
    );
    final next = composeFeedEntries(
      games: games,
      news: news,
      previous: _last,
      frozenThrough: _frozenThrough,
    );
    // A prefix that no longer matches the games was dropped: nothing frozen.
    if (next.isEmpty || _last.isEmpty || next.first.key != _last.first.key) {
      _frozenThrough = -1;
    }
    _last = next;
    return next;
  }

  /// The viewer reached page [index]. It and the page after it (already
  /// built, and visible mid-swipe) keep their places from now on.
  void markSeen(int index) {
    final through = index + 1;
    if (through > _frozenThrough) _frozenThrough = through;
  }

  /// Ends the current arrangement, noting the articles the viewer reached
  /// in it.
  void _retire() {
    final reached = math.min(_frozenThrough, _last.length);
    for (var i = 0; i < reached; i++) {
      final entry = _last[i];
      if (entry is FeedNewsEntry) _newsReached.add(entry.news.id);
    }
    _last = const [];
    _frozenThrough = -1;
  }
}

/// [news] with the articles not in [reached] first, each group in its own
/// order (newest first), so a fresh arrangement brings articles the viewer
/// has not had yet and comes back round to the others once all are read.
@visibleForTesting
List<FeedNews> feedNewsUnseenFirst(List<FeedNews> news, Set<int> reached) {
  if (reached.isEmpty) return news;
  return [
    for (final article in news)
      if (!reached.contains(article.id)) article,
    for (final article in news)
      if (reached.contains(article.id)) article,
  ];
}
