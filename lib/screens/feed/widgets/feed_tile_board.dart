import 'dart:async';

import 'package:chessever2/screens/feed/feed_screen.dart'
    show feedCurrentEntryKeyProvider;
import 'package:chessever2/screens/feed/feed_visibility.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Reads the first page Feed cached on disk. The seam tests override so the
/// tile's preview can be exercised without SQLite.
final feedFirstPageCacheReaderProvider =
    Provider<Future<List<FeedItem>> Function()>(
      (ref) =>
          () => readFeedFirstPageCache(userId: feedCacheUserId()),
    );

/// How long the preview outlives the tile, so coming back to Discovery paints
/// the board at once instead of the fallback for a few frames.
const Duration _kFeedTileKeepWarm = Duration(minutes: 5);

/// The game the Discovery Feed tile previews: the one Feed opens on.
///
/// - While Feed has already loaded this session, the page it would put the
///   viewer back on (a game), else its first game.
/// - Otherwise the first game of the page Feed cached on disk, which is
///   exactly the page it paints first on its next open.
/// - Null when neither exists (a first launch): the tile shows its pixel
///   object and "Games and news".
///
/// It never builds [feedProvider], so Discovery never starts the Feed's
/// five-source load; it only reads what Feed left. It reads again whenever
/// Feed closes ([feedScreenOpenProvider]), since that is when Feed has
/// cached a new first page.
final feedTilePreviewProvider = FutureProvider.autoDispose<FeedItem?>((
  ref,
) async {
  ref.watch(feedScreenOpenProvider);
  final link = ref.keepAlive();
  Timer? release;
  ref.onCancel(() {
    release?.cancel();
    release = Timer(_kFeedTileKeepWarm, link.close);
  });
  ref.onResume(() {
    release?.cancel();
    release = null;
  });
  ref.onDispose(() => release?.cancel());

  if (ref.exists(feedProvider)) {
    final items = ref.read(feedProvider).valueOrNull ?? const <FeedItem>[];
    if (items.isNotEmpty) {
      final resumeKey = ref.read(feedCurrentEntryKeyProvider);
      for (final item in items) {
        if ('game:${item.game.gameId}' == resumeKey) return item;
      }
      return items.first;
    }
  }
  final cached = await ref.read(feedFirstPageCacheReaderProvider)();
  return cached.isEmpty ? null : cached.first;
});

/// The position the Feed tile draws for [item]: its first headline moment
/// (the move Feed lingers on), else where the game ended. Null for an item
/// with no plies.
FeedPly? feedTilePly(FeedItem item) {
  final plies = item.plies;
  if (plies.isEmpty) return null;
  for (final index in item.headlineIndexes) {
    if (index > 0 && index < plies.length) return plies[index];
  }
  return plies.last;
}
