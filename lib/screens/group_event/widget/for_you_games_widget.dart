import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/screens/group_event/widget/premium_collection_cards.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// For You tab widget - displays events with their top 4 games
///
/// KEY DESIGN:
/// - Events load IMMEDIATELY (same source as Current tab)
/// - Games load LAZILY per event (with shimmer)
/// - Always exactly 4 games per event (hardcoded)
/// - Favorite players get priority in game selection
class ForYouGamesWidget extends ConsumerWidget {
  const ForYouGamesWidget({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(forYouEventsProvider);

    return eventsAsync.when(
      data: (events) {
        if (events.isEmpty) {
          return _buildEmptyState();
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(forYouEventsProvider);
          },
          color: kPrimaryColor,
          backgroundColor: kBlack2Color,
          child: _buildEventsList(events),
        );
      },
      loading: () => _buildLoadingState(),
      error: (error, stack) {
        debugPrint('[ForYouGamesWidget] Error: $error');
        return const GenericErrorWidget();
      },
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const PremiumCollectionCards(),
        ...List.generate(3, (index) => _ForYouEventSkeleton(isFirst: index == 0)),
      ],
    );
  }

  Widget _buildEventsList(List<GroupEventCardModel> events) {
    final isTablet = ResponsiveHelper.isTablet;
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.sp,
      tablet: 24.sp,
    );

    // For tablets in landscape, use a two-column layout for events
    if (isTablet && ResponsiveHelper.isLandscape) {
      return CustomScrollView(
        key: const PageStorageKey<String>('for_you_events_list'),
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: 16.sp,
              ),
              child: const PremiumCollectionCards(),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16.sp,
                mainAxisSpacing: 16.sp,
                // For event sections with games, use a taller aspect ratio
                childAspectRatio: 0.8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final event = events[index];
                  return _ForYouEventSection(
                    key: ValueKey('event_${event.id}'),
                    event: event,
                    isFirst: index == 0,
                    isTabletGrid: true,
                  );
                },
                childCount: events.length,
              ),
            ),
          ),
        ],
      );
    }

    // Phone layout or tablet portrait - use list
    return ListView.builder(
      key: const PageStorageKey<String>('for_you_events_list'),
      controller: scrollController,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16.sp),
      itemCount: events.length + 1, // +1 for premium cards
      cacheExtent: 1500,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      itemBuilder: (context, index) {
        // Premium collection cards at top
        if (index == 0) {
          return const PremiumCollectionCards();
        }

        final event = events[index - 1];
        return _ForYouEventSection(
          key: ValueKey('event_${event.id}'),
          event: event,
          isFirst: index == 1,
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const PremiumCollectionCards(),
        SizedBox(height: 40.sp),
        Center(
          child: Text(
            'No events available',
            style: TextStyle(color: kWhiteColor70, fontSize: 14.sp),
          ),
        ),
      ],
    );
  }
}

/// Section for one event: event card + 4 game cards
class _ForYouEventSection extends ConsumerWidget {
  const _ForYouEventSection({
    super.key,
    required this.event,
    required this.isFirst,
    this.isTabletGrid = false,
  });

  final GroupEventCardModel event;
  final bool isFirst;
  final bool isTabletGrid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shouldAnimate = !forYouAnimatedEventIds.contains(event.id);
    if (shouldAnimate) {
      forYouAnimatedEventIds.add(event.id);
    }

    // For tablet grid mode, use a more compact layout
    final section = isTabletGrid
        ? _buildTabletGridSection(context, ref)
        : _buildListSection(context, ref);

    if (shouldAnimate) {
      return section
          .animate()
          .fadeIn(duration: 200.ms)
          .slideY(begin: 0.02, end: 0, duration: 200.ms);
    }

    return section;
  }

  Widget _buildListSection(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Event card
        Padding(
          padding: EdgeInsets.only(top: isFirst ? 0 : 16.sp, bottom: 12.sp),
          child: EventCard(
            tourEventCardModel: event,
            heroTagSuffix: '_foryou',
            onTap: () {
              ref.read(groupEventScreenProvider.notifier).onSelectTournament(
                context: context,
                id: event.id,
              );
            },
          ),
        ),

        // Games for this event (lazy loaded with shimmer)
        _ForYouEventGames(eventId: event.id),
      ],
    );
  }

  Widget _buildTabletGridSection(BuildContext context, WidgetRef ref) {
    // In tablet grid mode, show a card-like container with event header
    return Container(
      decoration: BoxDecoration(
        color: kBlack2Color.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kDarkGreyColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Compact event card header
          Padding(
            padding: EdgeInsets.all(12.sp),
            child: EventCard(
              tourEventCardModel: event,
              heroTagSuffix: '_foryou_grid',
              onTap: () {
                ref.read(groupEventScreenProvider.notifier).onSelectTournament(
                  context: context,
                  id: event.id,
                );
              },
            ),
          ),

          // Games for this event
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.sp),
              child: _ForYouEventGames(eventId: event.id, isCompact: true),
            ),
          ),
        ],
      ),
    );
  }
}

/// Games section for one event - loads lazily with shimmer
class _ForYouEventGames extends ConsumerWidget {
  const _ForYouEventGames({required this.eventId, this.isCompact = false});

  final String eventId;
  final bool isCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamesAsync = ref.watch(eventGamesProvider(eventId));
    final viewMode = ref.watch(gamesListViewModeProvider);

    return gamesAsync.when(
      data: (games) {
        if (games.isEmpty) {
          return Padding(
            padding: EdgeInsets.only(bottom: 8.sp),
            child: Text(
              'No games available yet',
              style: TextStyle(color: kWhiteColor70, fontSize: 12.sp),
            ),
          );
        }

        // Convert to GamesTourModel
        final gameModels = games
            .where((g) => g.players != null && g.players!.length >= 2)
            .map((g) => GamesTourModel.fromGame(g))
            .toList();

        if (gameModels.isEmpty) {
          return const SizedBox.shrink();
        }

        final gamesData = GamesScreenModel(
          gamesTourModels: gameModels,
          pinnedGamedIs: const [],
        );

        // Grid mode: 2 games per row
        if (viewMode == GamesListViewMode.chessBoardGrid) {
          return _buildGridGames(context, ref, gameModels);
        }

        // List mode: one game per row
        return Column(
          children: List.generate(gameModels.length, (index) {
            final game = gameModels[index];
            return _ForYouGameCard(
              key: ValueKey('game_${game.gameId}'),
              game: game,
              gamesData: gamesData,
              gameIndex: index,
              allGames: gameModels,
              viewMode: viewMode,
            );
          }),
        );
      },
      loading: () => _buildGameShimmers(viewMode),
      error: (error, stack) {
        debugPrint('[ForYouEventGames] Error loading games for $eventId: $error');
        return Padding(
          padding: EdgeInsets.only(bottom: 8.sp),
          child: Text(
            'Could not load games',
            style: TextStyle(color: kWhiteColor70, fontSize: 12.sp),
          ),
        );
      },
    );
  }

  Widget _buildGridGames(
    BuildContext context,
    WidgetRef ref,
    List<GamesTourModel> games,
  ) {
    final rows = <Widget>[];

    for (int i = 0; i < games.length; i += 2) {
      final game1 = games[i];
      final game2 = i + 1 < games.length ? games[i + 1] : null;

      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: Row(
            children: [
              Expanded(
                child: GridGameCardWrapperWidget(
                  key: ValueKey('grid_game_${game1.gameId}'),
                  game: game1,
                  orderedGames: games,
                  gameIndex: i,
                  onChangedWithLiveGames: (updatedGames) => ref
                      .read(gameCardWrapperProvider)
                      .navigateToChessBoard(
                        context: context,
                        orderedGames: updatedGames,
                        gameIndex: i,
                        onReturnFromChessboard: (_) {},
                        viewSource: ChessboardView.forYou,
                      ),
                  pinnedIds: const [],
                  onPinToggle: (_) {},
                ),
              ),
              SizedBox(width: 12.sp),
              Expanded(
                child: game2 != null
                    ? GridGameCardWrapperWidget(
                        key: ValueKey('grid_game_${game2.gameId}'),
                        game: game2,
                        orderedGames: games,
                        gameIndex: i + 1,
                        onChangedWithLiveGames: (updatedGames) => ref
                            .read(gameCardWrapperProvider)
                            .navigateToChessBoard(
                              context: context,
                              orderedGames: updatedGames,
                              gameIndex: i + 1,
                              onReturnFromChessboard: (_) {},
                              viewSource: ChessboardView.forYou,
                            ),
                        pinnedIds: const [],
                        onPinToggle: (_) {},
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  /// Shimmer placeholders for 4 games
  Widget _buildGameShimmers(GamesListViewMode viewMode) {
    final mockPlayer = PlayerCard(
      name: 'Loading...',
      federation: '',
      title: 'GM',
      rating: 2700,
      countryCode: 'USA',
      team: '',
    );

    final mockGame = GamesTourModel(
      roundId: 'roundId',
      tourId: 'tourId',
      gameId: 'gameId',
      whitePlayer: mockPlayer,
      blackPlayer: mockPlayer,
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.ongoing,
    );

    if (viewMode == GamesListViewMode.chessBoardGrid) {
      // 2 rows of 2 games each
      return Column(
        children: List.generate(2, (rowIndex) {
          return Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: Row(
              children: [
                Expanded(child: _GameShimmer(mockGame: mockGame)),
                SizedBox(width: 12.sp),
                Expanded(child: _GameShimmer(mockGame: mockGame)),
              ],
            ),
          );
        }),
      );
    }

    // List mode: 4 shimmer cards
    return Column(
      children: List.generate(kGamesPerEvent, (index) {
        return Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: _GameShimmer(mockGame: mockGame),
        );
      }),
    );
  }
}

/// Shimmer for a single game card
class _GameShimmer extends StatelessWidget {
  const _GameShimmer({required this.mockGame});

  final GamesTourModel mockGame;

  @override
  Widget build(BuildContext context) {
    return SkeletonWidget(
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
    );
  }
}

/// Single game card with animation
class _ForYouGameCard extends ConsumerWidget {
  const _ForYouGameCard({
    super.key,
    required this.game,
    required this.gamesData,
    required this.gameIndex,
    required this.allGames,
    required this.viewMode,
  });

  final GamesTourModel game;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final List<GamesTourModel> allGames;
  final GamesListViewMode viewMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChessBoardVisible = viewMode == GamesListViewMode.chessBoard;
    final shouldAnimate = !forYouAnimatedGameIds.contains(game.gameId);

    if (shouldAnimate) {
      forYouAnimatedGameIds.add(game.gameId);
    }

    final card = Padding(
      padding: EdgeInsets.only(bottom: 12.sp),
      child: GameCardWrapperWidget(
        game: game,
        gamesData: gamesData,
        gameIndex: gameIndex,
        isChessBoardVisible: isChessBoardVisible,
        viewSource: ChessboardView.forYou,
        onReturnFromChessboard: (_) {},
      ),
    );

    if (shouldAnimate) {
      return card
          .animate()
          .fadeIn(duration: 150.ms, delay: Duration(milliseconds: gameIndex * 50))
          .slideY(begin: 0.03, end: 0, duration: 150.ms);
    }

    return card;
  }
}

/// Skeleton for entire event section (event card + 4 games)
class _ForYouEventSkeleton extends StatelessWidget {
  const _ForYouEventSkeleton({required this.isFirst});

  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final mockPlayer = PlayerCard(
      name: 'Loading...',
      federation: '',
      title: 'GM',
      rating: 2700,
      countryCode: 'USA',
      team: '',
    );

    final mockGame = GamesTourModel(
      roundId: 'roundId',
      tourId: 'tourId',
      gameId: 'gameId',
      whitePlayer: mockPlayer,
      blackPlayer: mockPlayer,
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.ongoing,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Event card skeleton
        SkeletonWidget(
          child: Container(
            margin: EdgeInsets.only(top: isFirst ? 0 : 16.sp, bottom: 12.sp),
            height: 80.sp,
            decoration: BoxDecoration(
              color: kBlack2Color,
              borderRadius: BorderRadius.circular(8.br),
            ),
          ),
        ),
        // Game card skeletons
        ...List.generate(kGamesPerEvent, (index) {
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
        }),
      ],
    );
  }
}
