import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/feed/widgets/feed_tile_board.dart';
import 'package:chessever2/screens/for_you/discovery/likes_screen.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/providers/reports_provider.dart';
import 'package:chessever2/screens/for_you/discovery/reports_screen.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/todays_miniatures_section.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hub_context_art.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/hub_tile_captions.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Discovery is a two-row set of destinations. Each destination owns its
/// loading, empty and retry states, and stays available if its preview fails.
enum DiscoverySection { tiles, likes, miniatures, reports }

class DiscoveryView extends ConsumerStatefulWidget {
  const DiscoveryView({super.key, this.scrollController});
  final ScrollController? scrollController;

  @override
  ConsumerState<DiscoveryView> createState() => _DiscoveryViewState();
}

class _DiscoveryViewState extends ConsumerState<DiscoveryView> {
  @override
  void initState() {
    super.initState();
    // Read without listening: warm one page, but allow its cache to expire
    // while Discovery is mounted. Reports reuses this same in-flight read.
    ref.read(reportsFirstPageProvider);
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedTilePreviewProvider).valueOrNull;
    return RefreshIndicator(
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      onRefresh: () async {
        refreshDiscovery(ref);
        ref.invalidate(discoveryAnalyzedGamesProvider);
        ref.invalidate(discoveryReviewCurveProvider);
        ref.invalidate(feedTilePreviewProvider);
        ref.invalidate(reportsFirstPageProvider);
        ref.read(reportsFirstPageProvider);
      },
      child: ListView(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.only(top: 16.sp, bottom: 96.sp),
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: ResponsiveHelper.contentMaxWidth,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hubGutter),
                child: Column(
                  children: [
                    HubTileRow(
                      left: HubTile(
                        key: const ValueKey('discovery_feed_tile'),
                        dotId: 'discovery.tile.feed',
                        title: 'Feed',
                        caption: hubFeedCaption(feed),
                        artwork: const HubSceneBackdrop(scene: HubScene.feed),
                        onTap: () => FeedScreen.open(context),
                      ),
                      right: HubTile(
                        key: const ValueKey('discovery_likes_tile'),
                        dotId: 'discovery.tile.likes',
                        title: 'Likes',
                        caption: 'Community favorites',
                        artwork: const HubSceneBackdrop(
                          scene: HubScene.mostLiked,
                        ),
                        onTap: () => LikesScreen.open(context),
                      ),
                    ),
                    HubTileRow(
                      left: HubTile(
                        key: const ValueKey('discovery_miniatures_tile'),
                        dotId: 'discovery.tile.miniatures',
                        title: 'Miniatures',
                        caption: '25 moves or fewer',
                        artwork: const HubSceneBackdrop(
                          scene: HubScene.miniatures,
                        ),
                        onTap: () => TodaysMiniaturesSection.open(context),
                      ),
                      right: HubTile(
                        key: const ValueKey('discovery_reports_tile'),
                        dotId: 'discovery.tile.reports',
                        title: 'Reports',
                        caption: 'Games with analysis',
                        artwork: const HubSceneBackdrop(
                          scene: HubScene.reports,
                        ),
                        onTap: () => ReportsScreen.open(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
