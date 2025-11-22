import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Widget for displaying the "For You" personalized games feed
/// Optimized with:
/// - Infinite scroll with on-demand loading (like onboarding player selection)
/// - Tournament grouping with headers
/// - Subtle animations using flutter_animate
/// - AutoDispose providers (disposed when tab changes)
/// - Cached game conversions (O(n) instead of O(n²))
class ForYouGamesWidget extends HookConsumerWidget {
  const ForYouGamesWidget({
    super.key,
    required this.scrollController,
  });

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamesAsync = ref.watch(forYouGamesProvider);
    final groupedGames = ref.watch(groupedForYouGamesProvider);
    final convertedGames = ref.watch(convertedForYouGamesProvider);

    // Track if we're loading more for UI feedback
    final isLoadingMore = useState(false);

    // Set up scroll listener for infinite scroll
    useEffect(() {
      void onScroll() {
        if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 300) {
          final notifier = ref.read(forYouGamesProvider.notifier);
          if (!notifier.isFetchingMore && notifier.hasMore) {
            isLoadingMore.value = true;
            notifier.loadMore().then((_) {
              isLoadingMore.value = false;
            });
          }
        }
      }

      scrollController.addListener(onScroll);
      return () => scrollController.removeListener(onScroll);
    }, [scrollController]);

    return gamesAsync.when(
      data: (games) {
        if (games.isEmpty) {
          return _buildEmptyState(context);
        }

        // Create GamesScreenModel once, not per item!
        final gamesData = GamesScreenModel(
          gamesTourModels: convertedGames,
          pinnedGamedIs: const [],
        );

        return _buildGroupedList(
          context,
          ref,
          groupedGames,
          gamesData,
          convertedGames,
          isLoadingMore.value,
        );
      },
      loading: () => _buildLoadingState(),
      error: (error, stackTrace) {
        debugPrint('[ForYouGamesWidget] Error: $error');
        debugPrint('[ForYouGamesWidget] Stack: $stackTrace');
        return const GenericErrorWidget();
      },
    );
  }

  Widget _buildGroupedList(
    BuildContext context,
    WidgetRef ref,
    List<ForYouGameGroup> groups,
    GamesScreenModel gamesData,
    List<GamesTourModel> allGames,
    bool isLoadingMore,
  ) {
    // Flatten groups into a list of items (headers + games)
    final items = <_ListItem>[];

    for (final group in groups) {
      // Add tournament header
      items.add(_ListItem.header(
        tourId: group.tourId,
        tourName: group.tourName,
        hasLiveGames: group.hasLiveGames,
        gameCount: group.games.length,
      ));

      // Add games for this group
      for (final game in group.games) {
        final gameIndex = allGames.indexWhere((g) => g.gameId == game.id);
        if (gameIndex != -1) {
          items.add(_ListItem.game(
            gameIndex: gameIndex,
            isLive: game.status == '*',
          ));
        }
      }
    }

    return ListView.builder(
      controller: scrollController,
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
      itemCount: items.length + (isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Loading indicator at the end
        if (index == items.length) {
          return _buildLoadingIndicator();
        }

        final item = items[index];

        if (item.isHeader) {
          return _buildTournamentHeader(
            item.tourName!,
            item.hasLiveGames!,
            item.gameCount!,
            index,
          );
        }

        // Game card
        final gamesTourModel = allGames[item.gameIndex!];

        return Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: GameCardWrapperWidget(
            key: ValueKey('game_${gamesTourModel.gameId}'),
            game: gamesTourModel,
            gamesData: gamesData,
            gameIndex: item.gameIndex!,
            isChessBoardVisible: false,
          ),
        )
            .animate()
            .fadeIn(
              duration: 200.ms,
              delay: Duration(milliseconds: (index % 10) * 30),
            )
            .slideY(
              begin: 0.05,
              end: 0,
              duration: 200.ms,
              curve: Curves.easeOut,
            );
      },
    );
  }

  Widget _buildTournamentHeader(
    String tourName,
    bool hasLiveGames,
    int gameCount,
    int index,
  ) {
    return Container(
      margin: EdgeInsets.only(
        top: index == 0 ? 0 : 16.sp,
        bottom: 8.sp,
      ),
      child: Row(
        children: [
          if (hasLiveGames) ...[
            Container(
              width: 8.sp,
              height: 8.sp,
              decoration: BoxDecoration(
                color: kRedColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: kRedColor.withValues(alpha: 0.5),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            )
                .animate(
                  onPlay: (controller) => controller.repeat(reverse: true),
                )
                .scale(
                  begin: const Offset(1.0, 1.0),
                  end: const Offset(1.2, 1.2),
                  duration: 800.ms,
                ),
            SizedBox(width: 8.sp),
          ],
          Expanded(
            child: Text(
              tourName,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: hasLiveGames ? kWhiteColor : kWhiteColor70,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 2.sp),
            decoration: BoxDecoration(
              color: kDarkGreyColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4.sp),
            ),
            child: Text(
              '$gameCount',
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
                color: kWhiteColor70,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 150.ms);
  }

  Widget _buildLoadingIndicator() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 20.sp),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16.sp,
              height: 16.sp,
              child: CircularProgressIndicator(
                color: kWhiteColor70,
                strokeWidth: 2.sp,
              ),
            ),
            SizedBox(width: 12.sp),
            Text(
              'Loading more games...',
              style: TextStyle(
                fontSize: 12.sp,
                color: kWhiteColor.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 150.ms);
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.sp),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border,
              size: 64.sp,
              color: kDarkGreyColor,
            ),
            SizedBox(height: 16.sp),
            Text(
              'No games to show',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: kWhiteColor70,
              ),
            ),
            SizedBox(height: 8.sp),
            Text(
              'Add favorite players or select your country\nto see personalized games',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.sp,
                color: kDarkGreyColor,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).scale(
          begin: const Offset(0.95, 0.95),
          end: const Offset(1.0, 1.0),
          duration: 300.ms,
        );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
      itemCount: 10,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: SkeletonWidget(
            child: Container(
              height: 100.sp,
              decoration: BoxDecoration(
                color: kDarkGreyColor,
                borderRadius: BorderRadius.circular(12.sp),
              ),
            ),
          ),
        )
            .animate()
            .fadeIn(
              duration: 200.ms,
              delay: Duration(milliseconds: index * 50),
            )
            .shimmer(
              duration: 1200.ms,
              color: kWhiteColor.withValues(alpha: 0.05),
            );
      },
    );
  }
}

/// Helper class for list items (either header or game)
class _ListItem {
  final bool isHeader;
  final String? tourId;
  final String? tourName;
  final bool? hasLiveGames;
  final int? gameCount;
  final int? gameIndex;
  final bool? isLive;

  const _ListItem._({
    required this.isHeader,
    this.tourId,
    this.tourName,
    this.hasLiveGames,
    this.gameCount,
    this.gameIndex,
    this.isLive,
  });

  factory _ListItem.header({
    required String tourId,
    required String tourName,
    required bool hasLiveGames,
    required int gameCount,
  }) {
    return _ListItem._(
      isHeader: true,
      tourId: tourId,
      tourName: tourName,
      hasLiveGames: hasLiveGames,
      gameCount: gameCount,
    );
  }

  factory _ListItem.game({
    required int gameIndex,
    required bool isLive,
  }) {
    return _ListItem._(
      isHeader: false,
      gameIndex: gameIndex,
      isLive: isLive,
    );
  }
}
