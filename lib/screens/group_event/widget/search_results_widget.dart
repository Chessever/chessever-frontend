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

/// Widget for displaying search results in a format identical to "For You" tab
/// Shows tournament headers followed by game cards
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
    final groupedGames = ref.watch(groupedSearchGamesProvider);
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

    // Cache the flattened items list
    final items = useMemoized(() {
      final result = <_ListItem>[];
      for (final group in groupedGames) {
        result.add(
          _ListItem.header(
            tourId: group.tourId,
            tourName: group.tourName,
            hasLiveGames: group.hasLiveGames,
            gameCount: group.games.length,
          ),
        );
        for (final game in group.games) {
          final gameIndex = convertedGames.indexWhere(
            (g) => g.gameId == game.id,
          );
          if (gameIndex != -1) {
            result.add(
              _ListItem.game(gameIndex: gameIndex, isLive: game.status == '*'),
            );
          }
        }
      }
      return result;
    }, [groupedGames, convertedGames]);

    // Cache GamesScreenModel
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
            Icon(Icons.search_off, size: 64.sp, color: kDarkGreyColor),
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
              style: TextStyle(fontSize: 14.sp, color: kDarkGreyColor),
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
            Icon(Icons.search, size: 64.sp, color: kDarkGreyColor),
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
              style: TextStyle(fontSize: 14.sp, color: kDarkGreyColor),
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

/// Skeleton loader that mimics the search results structure
class _SearchResultsSkeletonLoader extends StatelessWidget {
  const _SearchResultsSkeletonLoader();

  @override
  Widget build(BuildContext context) {
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
        _SkeletonTournamentHeader(isFirst: true),
        ...List.generate(
          3,
          (index) => _SkeletonGameCard(mockGame: mockGame, index: index),
        ),
        _SkeletonTournamentHeader(isFirst: false),
        ...List.generate(
          2,
          (index) => _SkeletonGameCard(mockGame: mockGame, index: index + 3),
        ),
      ],
    );
  }
}

class _SkeletonTournamentHeader extends StatelessWidget {
  const _SkeletonTournamentHeader({required this.isFirst});

  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    return SkeletonWidget(
      child: Container(
        margin: EdgeInsets.only(top: isFirst ? 0 : 16.sp, bottom: 12.sp),
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(8.br),
          border: Border.all(color: kDarkGreyColor.withValues(alpha: 0.3)),
        ),
        padding: EdgeInsets.all(12.sp),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              ],
            ),
          ],
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

/// List view for search results
class _SearchResultsListView extends ConsumerWidget {
  const _SearchResultsListView({
    required this.scrollController,
    required this.items,
    required this.gamesData,
    required this.allGames,
    required this.searchQuery,
  });

  final ScrollController scrollController;
  final List<_ListItem> items;
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
        key: PageStorageKey<String>('search_results_list_$searchQuery'),
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

          final gamesTourModel = allGames[item.gameIndex!];

          return _KeepAliveSearchGameCard(
            key: ValueKey('search_game_${gamesTourModel.gameId}'),
            game: gamesTourModel,
            gamesData: gamesData,
            gameIndex: item.gameIndex!,
            listIndex: index,
            allGames: allGames,
          );
        },
      ),
    );
  }
}

/// Game card with keep alive
class _KeepAliveSearchGameCard extends StatefulWidget {
  const _KeepAliveSearchGameCard({
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
  State<_KeepAliveSearchGameCard> createState() =>
      _KeepAliveSearchGameCardState();
}

class _KeepAliveSearchGameCardState extends State<_KeepAliveSearchGameCard>
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
        onReturnFromChessboard: (returnedIndex) {},
      ),
    );

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

/// Helper class for list items
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

  factory _ListItem.game({required int gameIndex, required bool isLive}) {
    return _ListItem._(isHeader: false, gameIndex: gameIndex, isLive: isLive);
  }
}
