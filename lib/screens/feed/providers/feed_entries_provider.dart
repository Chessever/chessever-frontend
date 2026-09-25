import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Feed tab as pages: [feedProvider]'s games with a ChessEver News
/// article after every [kFeedNewsEvery], once one has loaded. Puzzles live
/// in their own tab ([puzzleTabProvider]).
///
/// Games never wait on news: the first page is exactly the games' first
/// page, and articles slot in behind the viewer as they arrive. Pages the
/// viewer has reached are frozen ([markSeen]) so a late article can never
/// shift the page under their thumb.
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

  @override
  List<FeedEntry> build() {
    final games = ref.watch(feedProvider).valueOrNull ?? const [];
    if (games.isEmpty) {
      // A refresh (or a failed load) starts the arrangement over.
      _last = const [];
      _frozenThrough = -1;
      return _last;
    }
    final news = ref.watch(feedNewsProvider).valueOrNull ?? const [];
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
}
