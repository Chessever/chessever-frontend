import 'package:chessever2/providers/search_games_provider.dart';
import 'package:chessever2/screens/group_event/widget/for_you_tournament_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Widget for displaying search results as a list of events with their games
/// Shows tournament cards followed by game cards (similar to ForYou tab)
class SearchResultsWidget extends HookConsumerWidget {
  const SearchResultsWidget({
    super.key,
    required this.scrollController,
    required this.searchQuery,
  });

  final ScrollController scrollController;
  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamesAsync = ref.watch(searchGamesProvider);
    final groupedGamesAsync = ref.watch(groupedSearchGamesProvider);
    final convertedGames = ref.watch(convertedSearchGamesProvider);

    // Track mounted state
    final isMounted = useRef(true);
    useEffect(() {
      isMounted.value = true;
      return () => isMounted.value = false;
    }, []);

    // Load games when search query changes
    useEffect(() {
      if (searchQuery.trim().isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (isMounted.value) {
            ref.read(searchGamesProvider.notifier).loadGamesForSearch(searchQuery);
          }
        });
      }
      return null;
    }, [searchQuery]);

    // Build flattened list of items (headers + games)
    final items = useMemoized(() {
      final groupedGames = groupedGamesAsync.valueOrNull ?? [];
      final result = <_SearchListItem>[];

      for (final group in groupedGames) {
        // Add event header
        result.add(
          _SearchListItem.header(
            tourId: group.tourId,
            tourName: group.tourName,
            hasLiveGames: group.hasLiveGames,
            gameCount: group.games.length,
          ),
        );

        // Add game cards for this event
        for (final game in group.games) {
          final gameIndex = convertedGames.indexWhere((g) => g.gameId == game.id);
          if (gameIndex != -1) {
            result.add(
              _SearchListItem.game(
                gameIndex: gameIndex,
                isLive: game.status == '*',
              ),
            );
          }
        }
      }

      return result;
    }, [groupedGamesAsync, convertedGames]);

    // Build GamesScreenModel for game card navigation
    final gamesData = useMemoized(
      () => GamesScreenModel(
        gamesTourModels: convertedGames,
        pinnedGamedIs: const [],
      ),
      [convertedGames],
    );

    return gamesAsync.when(
      data: (games) {
        if (games.isEmpty && searchQuery.isNotEmpty) {
          return _buildEmptyState(context, searchQuery);
        }

        if (games.isEmpty) {
          return _buildInitialState(context);
        }

        // Wait for grouped games to be ready (async lookup of group_broadcast_ids)
        return groupedGamesAsync.when(
          data: (groupedGames) {
            if (groupedGames.isEmpty) {
              return _buildEmptyState(context, searchQuery);
            }
            return _SearchResultsListView(
              scrollController: scrollController,
              items: items,
              gamesData: gamesData,
              allGames: convertedGames,
              searchQuery: searchQuery,
            );
          },
          loading: () => _buildLoadingState(),
          error: (error, stackTrace) {
            debugPrint('[SearchResultsWidget] Grouping error: $error');
            return const GenericErrorWidget();
          },
        );
      },
      loading: () => _buildLoadingState(),
      error: (error, stackTrace) {
        debugPrint('[SearchResultsWidget] Error: $error');
        return const GenericErrorWidget();
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, String query) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.sp),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64.sp, color: kSubtleIconColor),
            SizedBox(height: 16.sp),
            Text(
              'No games found',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: kWhiteColor70,
              ),
            ),
            SizedBox(height: 8.sp),
            Text(
              'No games match "$query"',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.sp, color: kSecondaryTextColor),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .scale(
          begin: const Offset(0.95, 0.95),
          end: const Offset(1.0, 1.0),
          duration: 300.ms,
        );
  }

  Widget _buildInitialState(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.sp),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64.sp, color: kSubtleIconColor),
            SizedBox(height: 16.sp),
            Text(
              'Search Results',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: kWhiteColor70,
              ),
            ),
            SizedBox(height: 8.sp),
            Text(
              'Enter a search term to find games',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.sp, color: kSecondaryTextColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const _SearchResultsSkeletonLoader();
  }
}

/// Skeleton loader that mimics the search results structure (events + games)
class _SearchResultsSkeletonLoader extends StatelessWidget {
  const _SearchResultsSkeletonLoader();

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
        _SkeletonEventCard(isFirst: true),
        ...List.generate(
          2,
          (index) => _SkeletonGameCard(mockGame: mockGame, index: index),
        ),

        // Second tournament group
        _SkeletonEventCard(isFirst: false),
        ...List.generate(
          2,
          (index) => _SkeletonGameCard(mockGame: mockGame, index: index + 2),
        ),
      ],
    );
  }
}

class _SkeletonEventCard extends StatelessWidget {
  const _SkeletonEventCard({required this.isFirst});

  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    return SkeletonWidget(
      child: Container(
        margin: EdgeInsets.only(top: isFirst ? 0 : 16.sp, bottom: 12.sp),
        height: 80.sp,
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: kDarkGreyColor.withValues(alpha: 0.3)),
        ),
      ),
    );
  }
}

class _SkeletonGameCard extends StatelessWidget {
  const _SkeletonGameCard({required this.mockGame, required this.index});

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

/// List view showing event cards followed by their game cards
class _SearchResultsListView extends ConsumerWidget {
  const _SearchResultsListView({
    required this.scrollController,
    required this.items,
    required this.gamesData,
    required this.allGames,
    required this.searchQuery,
  });

  final ScrollController scrollController;
  final List<_SearchListItem> items;
  final GamesScreenModel gamesData;
  final List<GamesTourModel> allGames;
  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(searchGamesProvider.notifier).refresh();
      },
      color: kPrimaryColor,
      backgroundColor: kBlack2Color,
      displacement: 60.h,
      strokeWidth: 3.w,
      child: ListView.builder(
        key: PageStorageKey<String>('search_results_$searchQuery'),
        controller: scrollController,
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
        itemCount: items.length,
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: true,
        cacheExtent: 2000,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        itemBuilder: (context, index) {
          final item = items[index];

          if (item.isHeader) {
            return ForYouTournamentCard(
              key: ValueKey('search_header_${item.tourId}'),
              tourId: item.tourId!,
              tourName: item.tourName!,
              hasLiveGames: item.hasLiveGames!,
              gameCount: item.gameCount!,
              isFirst: index == 0,
            );
          }

          // Game card
          final gamesTourModel = allGames[item.gameIndex!];
          return _SearchGameCard(
            key: ValueKey('search_game_${gamesTourModel.gameId}'),
            game: gamesTourModel,
            gamesData: gamesData,
            gameIndex: item.gameIndex!,
            listIndex: index,
          );
        },
      ),
    );
  }
}

/// Game card widget with keep-alive and animation support
class _SearchGameCard extends StatefulWidget {
  const _SearchGameCard({
    super.key,
    required this.game,
    required this.gamesData,
    required this.gameIndex,
    required this.listIndex,
  });

  final GamesTourModel game;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final int listIndex;

  @override
  State<_SearchGameCard> createState() => _SearchGameCardState();
}

class _SearchGameCardState extends State<_SearchGameCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final gameId = widget.game.gameId;
    final card = Padding(
      padding: EdgeInsets.only(bottom: 12.sp),
      child: GameCardWrapperWidget(
        game: widget.game,
        gamesData: widget.gamesData,
        gameIndex: widget.gameIndex,
        isChessBoardVisible: false,
        onReturnFromChessboard: (returnedIndex) {
          // Handle returning from chess board if needed
        },
      ),
    );

    // Use global set to track animations - survives tab switches and rebuilds
    if (!searchAnimatedGameIds.contains(gameId)) {
      searchAnimatedGameIds.add(gameId);
      return card
          .animate()
          .fadeIn(
            duration: 200.ms,
            delay: Duration(milliseconds: (widget.listIndex % 10) * 30),
          )
          .slideY(begin: 0.05, end: 0, duration: 200.ms, curve: Curves.easeOut);
    }

    return card;
  }
}

/// Helper class for list items (either header or game)
class _SearchListItem {
  final bool isHeader;
  final String? tourId;
  final String? tourName;
  final bool? hasLiveGames;
  final int? gameCount;
  final int? gameIndex;
  final bool? isLive;

  const _SearchListItem._({
    required this.isHeader,
    this.tourId,
    this.tourName,
    this.hasLiveGames,
    this.gameCount,
    this.gameIndex,
    this.isLive,
  });

  factory _SearchListItem.header({
    required String tourId,
    required String tourName,
    required bool hasLiveGames,
    required int gameCount,
  }) {
    return _SearchListItem._(
      isHeader: true,
      tourId: tourId,
      tourName: tourName,
      hasLiveGames: hasLiveGames,
      gameCount: gameCount,
    );
  }

  factory _SearchListItem.game({required int gameIndex, required bool isLive}) {
    return _SearchListItem._(isHeader: false, gameIndex: gameIndex, isLive: isLive);
  }
}
