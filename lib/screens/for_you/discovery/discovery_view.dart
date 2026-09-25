import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_section.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/todays_miniatures_section.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:flutter/material.dart';
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
/// on top, then Most Liked and today's Miniatures, each listing its games
/// the way an event's Games tab does.
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
  late final Widget _mostLiked = const MostLikedSection();
  late final Widget _miniatures = const TodaysMiniaturesSection();

  Widget _section(DiscoverySection section) {
    return switch (section) {
      DiscoverySection.tiles => const _DiscoveryTiles(),
      DiscoverySection.mostLiked => _mostLiked,
      DiscoverySection.miniatures => _miniatures,
    };
  }

  @override
  Widget build(BuildContext context) {
    const sections = DiscoverySection.values;
    return RefreshIndicator(
      color: context.colors.accentText,
      backgroundColor: context.colors.surface,
      onRefresh: () async => refreshDiscovery(ref),
      child: ListView.builder(
        controller: widget.scrollController,
        scrollCacheExtent: kListScrollCacheExtent,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        // The same top inset Today and My Space open with, so the tiles sit
        // on one line across the three pages.
        padding: EdgeInsets.only(top: 16.sp, bottom: 32.w),
        itemCount: sections.length,
        // Each item is its own slot, which adds these itself: the slot must
        // be the list's child so a trimmed last line keeps its full target.
        addRepaintBoundaries: false,
        addSemanticIndexes: false,
        itemBuilder: (context, index) {
          final section = sections[index];
          // The tiles carry their own gap below them, as on Today.
          final top =
              index == 0 || sections[index - 1] == DiscoverySection.tiles
              ? 0.0
              : _gap;
          return DiscoverySectionSlot(
            key: ValueKey(section),
            child: IndexedSemantics(
              index: index,
              child: RepaintBoundary(
                child: Padding(
                  padding: EdgeInsets.only(top: top),
                  child: _section(section),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DiscoveryTiles extends StatelessWidget {
  const _DiscoveryTiles();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
      child: HubTileRow(
        left: HubTile(
          key: const ValueKey('discovery_feed_tile'),
          title: 'Feed',
          ramp: false,
          artwork: const HubPixelArtwork(section: SpaceSection.games),
          onTap: () => FeedScreen.open(context),
        ),
        right: HubTile(
          key: const ValueKey('discovery_collection_tile'),
          title: 'Collection',
          ramp: false,
          artwork: const HubPixelArtwork(section: SpaceSection.library),
          onTap: () => CollectionsScreen.open(context),
        ),
      ),
    );
  }
}
