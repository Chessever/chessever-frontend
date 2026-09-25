import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/feed/widgets/feed_tile_board.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_section.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/todays_miniatures_section.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/hub_tile_art.dart';
import 'package:chessever2/widgets/hub_tile_captions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Discovery sections, top to bottom.
enum DiscoverySection {
  /// The Feed and Collection tiles, as Today opens with Favorites and
  /// Countrymen.
  tiles,
  mostLiked,
  miniatures,
}

/// For You › Discovery, laid out like Today: the Feed and Collection tiles
/// on top, each previewing what it opens, then short previews of today's
/// Most liked and Miniatures, each listing its games the way an event's
/// Games tab does and ending in "See all" to its full page. On a tablet the
/// two previews stand side by side.
///
/// Every section reads its own data and handles its own loading, empty and
/// failure states, so one failing never blanks the page. The list is lazy:
/// a section below the fold starts its reads only when it comes near.
class DiscoveryView extends ConsumerStatefulWidget {
  const DiscoveryView({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<DiscoveryView> createState() => _DiscoveryViewState();
}

class _DiscoveryViewState extends ConsumerState<DiscoveryView> {
  /// From one section's last ink to the next section's header.
  static double get _gap => 28.w;

  // Built once and handed back as the same instances, so a parent rebuild
  // (the For You swipe flips its in-view state) skips these sections and
  // their card lists instead of rebuilding them on every swipe.
  late final Widget _mostLiked = const MostLikedPreview();
  late final Widget _miniatures = const TodaysMiniaturesSection();
  late final Widget _pair = const _PreviewPair();

  @override
  Widget build(BuildContext context) {
    final tablet = ResponsiveHelper.isTablet;
    // A tablet sets the two previews side by side in one slot.
    final slots = <(Key, Widget)>[
      (const ValueKey(DiscoverySection.tiles), const _DiscoveryTiles()),
      if (tablet)
        (const ValueKey('discovery_previews'), _pair)
      else ...[
        (const ValueKey(DiscoverySection.mostLiked), _mostLiked),
        (const ValueKey(DiscoverySection.miniatures), _miniatures),
      ],
    ];
    return RefreshIndicator(
      color: context.colors.accentText,
      backgroundColor: context.colors.surface,
      onRefresh: () async {
        refreshDiscovery(ref);
        ref.invalidate(feedTilePreviewProvider);
      },
      child: ListView.builder(
        controller: widget.scrollController,
        scrollCacheExtent: kListScrollCacheExtent,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        // The same top inset Today and My Space open with, so the tiles sit
        // on one line across the three pages.
        padding: EdgeInsets.only(top: 16.sp, bottom: 32.w),
        itemCount: slots.length,
        // Each item is its own slot, which adds these itself: the slot must
        // be the list's child so a trimmed last line keeps its full target.
        addRepaintBoundaries: false,
        addSemanticIndexes: false,
        itemBuilder: (context, index) {
          final (key, child) = slots[index];
          // The tiles carry their own gap below them, as on Today.
          final top = index <= 1 ? 0.0 : _gap;
          return DiscoverySectionSlot(
            key: key,
            child: IndexedSemantics(
              index: index,
              child: RepaintBoundary(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: ResponsiveHelper.contentMaxWidth,
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(top: top),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Feed and Collection, each tile previewing what it opens: the board of the
/// game Feed opens on and who is playing, the newest collection cover and
/// what the team has published.
class _DiscoveryTiles extends ConsumerWidget {
  const _DiscoveryTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedTilePreviewProvider).valueOrNull;
    // Watching the list here also keeps it warm, so Collection opens with
    // its cards already read.
    final collections = ref.watch(collectionsProvider);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
      child: HubTileRow(
        left: HubTile(
          key: const ValueKey('discovery_feed_tile'),
          title: 'Feed',
          artwork: _feedArt(),
          caption: hubFeedCaption(feed),
          onTap: () => FeedScreen.open(context),
        ),
        right: HubTile(
          key: const ValueKey('discovery_collection_tile'),
          title: 'Collection',
          artwork: _collectionArt(),
          caption: hubCollectionsCaption(collections),
          onTap: () => CollectionsScreen.open(context),
        ),
      ),
    );
  }
}

/// The Feed tile's picture: the Feed's own pixel object (the magnifier over
/// a board) drawn large across the tile, its scan line sweeping and its
/// blocks glinting, as the heart moves on My Likes.
Widget _feedArt() => const HubPixelBackdrop(section: SpaceSection.games);

/// The Collection tile's picture: the trophy, animated like the other hub
/// tiles (the newest cover stays inside Collection itself).
Widget _collectionArt() => const HubPixelBackdrop(section: SpaceSection.events);

/// Most liked and Miniatures side by side (tablets): two columns with one
/// gap between them, each section drawn exactly as on a phone.
class _PreviewPair extends StatelessWidget {
  const _PreviewPair();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(child: _Column(child: MostLikedPreview())),
          SizedBox(width: 16.sp),
          const Expanded(child: _Column(child: TodaysMiniaturesSection())),
        ],
      ),
    );
  }
}

/// A Discovery section in a column narrower than the page: every Discovery
/// line sets itself in the page gutter, so the section is laid out a gutter
/// wider on each side and centred, which puts that gutter exactly on the
/// column's edges.
class _Column extends StatelessWidget {
  const _Column({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth + 2 * discoveryGutter;
        return OverflowBox(
          fit: OverflowBoxFit.deferToChild,
          minWidth: width,
          maxWidth: width,
          alignment: Alignment.topCenter,
          child: child,
        );
      },
    );
  }
}
