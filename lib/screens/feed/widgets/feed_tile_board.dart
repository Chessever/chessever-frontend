import 'dart:async';

import 'package:chessever2/screens/feed/feed_screen.dart'
    show feedCurrentEntryKeyProvider;
import 'package:chessever2/screens/feed/feed_visibility.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryMiniBoard;
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:flutter/material.dart';
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

/// The side of a hub tile's picture mark in a [slot]-wide square, snapped so
/// a board's eight squares land on whole device pixels: at 3x a 44-point
/// board would put every other square edge on half a pixel and blur it. The
/// picture sits centred in the slot, less than a point in from its edges.
double hubPictureMarkSide(double slot, double devicePixelRatio) {
  if (slot <= 0 || devicePixelRatio <= 0) return slot;
  final pixels = (slot * devicePixelRatio / 8).floorToDouble() * 8;
  return pixels <= 0 ? slot : pixels / devicePixelRatio;
}

/// The corner of a picture set in a hub tile's mark slot: the game cards'
/// board corner, so the preview reads as the board it opens.
double get hubPictureMarkRadius => 4.br;

/// A picture in a hub tile's mark slot: clipped to [hubPictureMarkRadius]
/// with a self-coloured 1px edge (white at 10% on the dark tile, ink at 10%
/// on paper), so a board or a photo whose own edge matches the tile's ink
/// still reads as an object. Nothing is drawn behind it.
class HubPictureMark extends StatelessWidget {
  const HubPictureMark({super.key, required this.child, required this.side});

  final Widget child;
  final double side;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(hubPictureMarkRadius);
    final edge = context.isLightTheme
        ? Colors.black.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.10);
    return Center(
      child: SizedBox.square(
        dimension: side,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: edge),
          ),
          child: ClipRRect(borderRadius: radius, child: child),
        ),
      ),
    );
  }
}

/// The Feed tile's mark: the board of the game Feed opens on, still, in the
/// viewer's own board theme with no coordinates, white at the bottom. The
/// tile's pixel object stands in until Feed has a page cached.
class FeedTileBoard extends StatelessWidget {
  const FeedTileBoard({super.key, required this.item});

  final FeedItem? item;

  @override
  Widget build(BuildContext context) {
    final current = item;
    final ply = current == null ? null : feedTilePly(current);
    if (ply == null) return const HubPixelArtwork(section: SpaceSection.games);
    return LayoutBuilder(
      builder: (context, constraints) {
        final slot = constraints.biggest.shortestSide;
        if (!slot.isFinite || slot <= 0) return const SizedBox.shrink();
        final side = hubPictureMarkSide(
          slot,
          MediaQuery.devicePixelRatioOf(context),
        );
        return HubPictureMark(
          side: side,
          child: DiscoveryMiniBoard(fen: ply.fen, size: side, lastMove: ply.uci),
        );
      },
    );
  }
}
