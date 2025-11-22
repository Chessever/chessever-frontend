import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/screens/group_event/widget/for_you_tournament_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Widget for displaying the "For You" personalized games feed
///
/// OPTIMIZATIONS:
/// - useMemoized for cached items list (avoids O(n) rebuild on each frame)
/// - addAutomaticKeepAlives: true keeps items in memory when scrolled
/// - Large cacheExtent (2000px) keeps more items rendered off-screen
/// - AutomaticKeepAlive wrapper prevents game cards from being disposed
/// - Animations only play once (not on rebuild) via AnimatedSwitcher pattern
/// - AutoDispose providers clean up when tab changes
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

    // Auto-refresh when the tab is reopened after sitting idle, so live games float to the top
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Defer to post-frame to avoid mutating providers during build
        ref.read(forYouGamesProvider.notifier).refreshIfStale();
      });
      return null;
    }, const []);

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

    // OPTIMIZATION: Cache the flattened items list using useMemoized
    // This prevents O(n) rebuild on every frame
    final items = useMemoized(() {
      final result = <_ListItem>[];
      for (final group in groupedGames) {
        result.add(_ListItem.header(
          tourId: group.tourId,
          tourName: group.tourName,
          hasLiveGames: group.hasLiveGames,
          gameCount: group.games.length,
        ));
        for (final game in group.games) {
          final gameIndex = convertedGames.indexWhere((g) => g.gameId == game.id);
          if (gameIndex != -1) {
            result.add(_ListItem.game(
              gameIndex: gameIndex,
              isLive: game.status == '*',
            ));
          }
        }
      }
      return result;
    }, [groupedGames, convertedGames]);

    // OPTIMIZATION: Cache GamesScreenModel
    final gamesData = useMemoized(
      () => GamesScreenModel(
        gamesTourModels: convertedGames,
        pinnedGamedIs: const [],
      ),
      [convertedGames],
    );

    return gamesAsync.when(
      data: (games) {
        if (games.isEmpty) {
          return _buildEmptyState(context);
        }

        return _ForYouListView(
          scrollController: scrollController,
          items: items,
          gamesData: gamesData,
          allGames: convertedGames,
          isLoadingMore: isLoadingMore.value,
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
    return const _ForYouSkeletonLoader();
  }
}

/// Skeleton loader that mimics the For You feed structure
/// Shows tournament headers followed by game cards
class _ForYouSkeletonLoader extends StatelessWidget {
  const _ForYouSkeletonLoader();

  @override
  Widget build(BuildContext context) {
    // Create mock player data for skeleton
    final mockPlayer = PlayerCard(
      name: 'Player Name Here',
      federation: 'Federation',
      title: 'GM',
      rating: 2700,
      countryCode: 'USA',
      team: 'Team Name',
    );

    final mockGame = GamesTourModel(
      roundId: 'roundId',
      tourId: 'tourId',
      gameId: 'gameId',
      whitePlayer: mockPlayer,
      blackPlayer: mockPlayer,
      whiteTimeDisplay: '1:30:00',
      blackTimeDisplay: '1:30:00',
      whiteClockCentiseconds: 540000,
      blackClockCentiseconds: 540000,
      gameStatus: GameStatus.ongoing,
    );

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // First tournament group
        _SkeletonTournamentHeader(isFirst: true),
        ...List.generate(
          3,
          (index) => _SkeletonGameCard(mockGame: mockGame, index: index),
        ),

        // Second tournament group
        _SkeletonTournamentHeader(isFirst: false),
        ...List.generate(
          2,
          (index) => _SkeletonGameCard(mockGame: mockGame, index: index + 3),
        ),

        // Third tournament group
        _SkeletonTournamentHeader(isFirst: false),
        ...List.generate(
          3,
          (index) => _SkeletonGameCard(mockGame: mockGame, index: index + 5),
        ),
      ],
    );
  }
}

/// Skeleton tournament header card
class _SkeletonTournamentHeader extends StatelessWidget {
  const _SkeletonTournamentHeader({required this.isFirst});

  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    return SkeletonWidget(
      child: Container(
        margin: EdgeInsets.only(
          top: isFirst ? 0 : 16.sp,
          bottom: 12.sp,
        ),
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(8.br),
          border: Border.all(
            color: kDarkGreyColor.withValues(alpha: 0.3),
          ),
        ),
        padding: EdgeInsets.all(12.sp),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tournament name row
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 16.sp,
                    decoration: BoxDecoration(
                      color: kDarkGreyColor,
                      borderRadius: BorderRadius.circular(4.br),
                    ),
                  ),
                ),
                SizedBox(width: 12.sp),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 3.sp),
                  decoration: BoxDecoration(
                    color: kDarkGreyColor.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4.br),
                  ),
                  child: Text(
                    '3 games',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w500,
                      color: kWhiteColor70,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 6.sp),
            // Details row
            Row(
              children: [
                Container(
                  width: 80.sp,
                  height: 12.sp,
                  decoration: BoxDecoration(
                    color: kDarkGreyColor.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4.br),
                  ),
                ),
                SizedBox(width: 12.sp),
                Container(
                  width: 50.sp,
                  height: 12.sp,
                  decoration: BoxDecoration(
                    color: kDarkGreyColor.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4.br),
                  ),
                ),
              ],
            ),
            SizedBox(height: 6.sp),
            // Tap hint row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Tap to view tournament',
                  style: AppTypography.textXsRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.4),
                    fontSize: 10.sp,
                  ),
                ),
                SizedBox(width: 4.sp),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 10.sp,
                  color: kWhiteColor.withValues(alpha: 0.4),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton game card using actual GameCard structure
class _SkeletonGameCard extends StatelessWidget {
  const _SkeletonGameCard({
    required this.mockGame,
    required this.index,
  });

  final GamesTourModel mockGame;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.sp),
      child: SkeletonWidget(
        ignoreContainers: true,
        child: GameCard(
          onTap: () {},
          matchComparison: MatchWithComparison(
            game: mockGame,
            comparison: MatchComparison.sameOrder,
          ),
          onPinToggle: (_) {},
          pinnedIds: const [],
        ),
      ),
    );
  }
}

/// Optimized ListView that keeps items alive when scrolled off-screen
class _ForYouListView extends StatelessWidget {
  const _ForYouListView({
    required this.scrollController,
    required this.items,
    required this.gamesData,
    required this.allGames,
    required this.isLoadingMore,
  });

  final ScrollController scrollController;
  final List<_ListItem> items;
  final GamesScreenModel gamesData;
  final List<GamesTourModel> allGames;
  final bool isLoadingMore;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      // CRITICAL: PageStorageKey preserves scroll position across tab switches
      key: const PageStorageKey<String>('for_you_games_list'),
      controller: scrollController,
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
      itemCount: items.length + (isLoadingMore ? 1 : 0),
      // CRITICAL: Keep items alive when scrolled off-screen
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      // OPTIMIZATION: Large cache extent keeps more items rendered
      cacheExtent: 2000,
      itemBuilder: (context, index) {
        // Loading indicator at the end
        if (index == items.length) {
          return _buildLoadingIndicator();
        }

        final item = items[index];

        if (item.isHeader) {
          return ForYouTournamentCard(
            key: ValueKey('header_${item.tourId}'),
            tourId: item.tourId!,
            tourName: item.tourName!,
            hasLiveGames: item.hasLiveGames!,
            gameCount: item.gameCount!,
            isFirst: index == 0,
          );
        }

        // Game card with KeepAlive wrapper
        final gamesTourModel = allGames[item.gameIndex!];

        return _KeepAliveGameCard(
          key: ValueKey('game_${gamesTourModel.gameId}'),
          game: gamesTourModel,
          gamesData: gamesData,
          gameIndex: item.gameIndex!,
          listIndex: index,
          allGames: allGames, // Pass all games for navigation
        );
      },
    );
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
}

/// StatefulWidget that uses AutomaticKeepAliveClientMixin to keep game cards alive
/// This prevents the card from being disposed when scrolled off-screen
class _KeepAliveGameCard extends StatefulWidget {
  const _KeepAliveGameCard({
    super.key,
    required this.game,
    required this.gamesData,
    required this.gameIndex,
    required this.listIndex,
    required this.allGames,
  });

  final GamesTourModel game;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final int listIndex;
  final List<GamesTourModel> allGames;

  @override
  State<_KeepAliveGameCard> createState() => _KeepAliveGameCardState();
}

class _KeepAliveGameCardState extends State<_KeepAliveGameCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // CRITICAL: Keep this widget alive

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final gameId = widget.game.gameId;
    final card = Padding(
      padding: EdgeInsets.only(bottom: 12.sp),
      child: GameCardWrapperWidget(
        game: widget.game,
        gamesData: widget.gamesData,
        gameIndex: widget.gameIndex,
        isChessBoardVisible: false,
        // Enable navigation for game cards in For You tab
        onReturnFromChessboard: (returnedIndex) {
          // Handle returning from chess board if needed
          // For now, we don't need to do anything special
        },
      ),
    );

    // Use global set to track animations - survives tab switches and rebuilds
    if (!forYouAnimatedGameIds.contains(gameId)) {
      forYouAnimatedGameIds.add(gameId);
      return card
          .animate()
          .fadeIn(
            duration: 200.ms,
            delay: Duration(milliseconds: (widget.listIndex % 10) * 30),
          )
          .slideY(
            begin: 0.05,
            end: 0,
            duration: 200.ms,
            curve: Curves.easeOut,
          );
    }

    return card;
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
