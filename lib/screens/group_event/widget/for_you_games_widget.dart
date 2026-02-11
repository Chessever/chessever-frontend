import 'dart:async';

import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
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
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// For You tab widget - displays events with their top 4 games
///
/// KEY DESIGN:
/// - Events load IMMEDIATELY (same source as Current tab)
/// - Games load LAZILY per event (with shimmer)
/// - Always exactly 4 games per event (hardcoded)
/// - Favorite players get priority in game selection
class ForYouGamesWidget extends ConsumerStatefulWidget {
  const ForYouGamesWidget({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<ForYouGamesWidget> createState() => _ForYouGamesWidgetState();
}

class _ForYouGamesWidgetState extends ConsumerState<ForYouGamesWidget>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref.read(forYouEventsProvider.notifier).refreshIfStale(),
      );
    }
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    final max = widget.scrollController.position.maxScrollExtent;
    final current = widget.scrollController.position.pixels;
    if (max - current <= 300) {
      ref.read(forYouEventsProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(forYouEventsProvider);

    if (state.isLoading && state.events.isEmpty) {
      return _buildLoadingState();
    }

    if (state.error != null && state.events.isEmpty) {
      debugPrint('[ForYouGamesWidget] Error: ${state.error}');
      return const GenericErrorWidget();
    }

    if (state.events.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(forYouEventsProvider.notifier).refresh();
      },
      color: kPrimaryColor,
      backgroundColor: kBlack2Color,
      child: _buildEventsList(state.events, showLoadingMore: state.hasMore && !state.isLoading),
    );
  }

  Widget _buildLoadingState() {
    // On tablet, show grid skeleton
    if (ResponsiveHelper.isTablet) {
      return _buildTabletLoadingSkeleton();
    }

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const PremiumCollectionCards(),
        ...List.generate(
          3,
          (index) => _ForYouEventSkeleton(isFirst: index == 0),
        ),
      ],
    );
  }

  Widget _buildTabletLoadingSkeleton() {
    final horizontalPadding = ResponsiveHelper.isLandscape ? 32.sp : 24.sp;
    final columnSpacing = 16.sp;
    final eventCardAspectRatio = ResponsiveHelper.isLandscape ? 1.8 : 1.4;

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 16.sp,
      ),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const PremiumCollectionCards(),
        // 2-column skeleton rows (2 event pairs)
        ...List.generate(2, (rowIndex) {
          return Padding(
            padding: EdgeInsets.only(top: rowIndex == 0 ? 0 : 20.sp),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left column skeleton
                Expanded(
                  child: _TabletColumnSkeleton(
                    eventCardAspectRatio: eventCardAspectRatio,
                  ),
                ),
                SizedBox(width: columnSpacing),
                // Right column skeleton
                Expanded(
                  child: _TabletColumnSkeleton(
                    eventCardAspectRatio: eventCardAspectRatio,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEventsList(List<GroupEventCardModel> events, {bool showLoadingMore = false}) {
    // On tablet, use a beautiful grid layout
    if (ResponsiveHelper.isTablet) {
      return _buildTabletGridLayout(events, showLoadingMore: showLoadingMore);
    }

    // Phone: vertical list layout
    final horizontalPadding = 16.sp;

    // +1 for premium cards, +1 for loading indicator if showing
    final itemCount = events.length + 1 + (showLoadingMore ? 1 : 0);

    return ListView.builder(
      key: const PageStorageKey<String>('for_you_events_list'),
      controller: widget.scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 16.sp,
      ),
      itemCount: itemCount,
      cacheExtent: 600,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      itemBuilder: (context, index) {
        // Premium collection cards at top
        if (index == 0) {
          return const PremiumCollectionCards();
        }

        // Loading indicator at bottom
        if (showLoadingMore && index == itemCount - 1) {
          return _buildLoadingMoreIndicator();
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

  Widget _buildLoadingMoreIndicator() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16.sp),
      child: Center(
        child: SizedBox(
          width: 24.sp,
          height: 24.sp,
          child: CircularProgressIndicator(
            strokeWidth: 2.sp,
            color: kPrimaryColor,
          ),
        ),
      ),
    );
  }

  /// Tablet: 2-column grid where each column = event card + its games
  /// Creates a beautiful magazine-style layout that fills tablet width
  /// Uses ListView.builder for lazy, on-demand rendering
  Widget _buildTabletGridLayout(List<GroupEventCardModel> events, {bool showLoadingMore = false}) {
    final horizontalPadding = ResponsiveHelper.isLandscape ? 32.sp : 24.sp;
    final columnSpacing = 16.sp;

    // Number of event-pair rows (ceil division)
    final rowCount = (events.length + 1) ~/ 2;
    // +1 for premium cards at top, +1 for loading indicator if showing
    final itemCount = rowCount + 1 + (showLoadingMore ? 1 : 0);

    return ListView.builder(
      key: const PageStorageKey<String>('for_you_events_tablet_grid'),
      controller: widget.scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 16.sp,
      ),
      itemCount: itemCount,
      cacheExtent: 600,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      itemBuilder: (context, index) {
        // Premium collection cards at top
        if (index == 0) {
          return const PremiumCollectionCards();
        }

        // Loading indicator at bottom
        if (showLoadingMore && index == itemCount - 1) {
          return _buildLoadingMoreIndicator();
        }

        final rowIndex = index - 1;
        final i = rowIndex * 2;
        final event1 = events[i];
        final event2 = i + 1 < events.length ? events[i + 1] : null;

        return Padding(
          padding: EdgeInsets.only(top: rowIndex == 0 ? 0 : 20.sp),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left column: event1 + its games
              Expanded(
                child: _ForYouTabletEventColumn(
                  key: ValueKey('tablet_col_${event1.id}'),
                  event: event1,
                ),
              ),
              SizedBox(width: columnSpacing),
              // Right column: event2 + its games (or empty space)
              Expanded(
                child:
                    event2 != null
                        ? _ForYouTabletEventColumn(
                          key: ValueKey('tablet_col_${event2.id}'),
                          event: event2,
                        )
                        : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
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

/// Skeleton for a single column in the 2-column tablet grid
class _TabletColumnSkeleton extends StatelessWidget {
  const _TabletColumnSkeleton({required this.eventCardAspectRatio});

  final double eventCardAspectRatio;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Event card skeleton
        SkeletonWidget(
          child: AspectRatio(
            aspectRatio: eventCardAspectRatio,
            child: Container(
              decoration: BoxDecoration(
                color: kBlack2Color,
                borderRadius: BorderRadius.circular(12.br),
              ),
            ),
          ),
        ),
        SizedBox(height: 10.sp),
        // Game card skeletons (2 rows of 2 = 4 total, matching actual content)
        ...List.generate(2, (rowIndex) {
          return Padding(
            padding: EdgeInsets.only(bottom: 8.sp),
            child: Row(
              children: [
                Expanded(
                  child: SkeletonWidget(
                    ignoreContainers: true,
                    child: Container(
                      height: 72.sp,
                      decoration: BoxDecoration(
                        color: kBlack2Color,
                        borderRadius: BorderRadius.circular(8.br),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8.sp),
                Expanded(
                  child: SkeletonWidget(
                    ignoreContainers: true,
                    child: Container(
                      height: 72.sp,
                      decoration: BoxDecoration(
                        color: kBlack2Color,
                        borderRadius: BorderRadius.circular(8.br),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
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
  });

  final GroupEventCardModel event;
  final bool isFirst;

  /// Builds the EventCard with proper constraints for tablet
  /// Tablet uses image-as-background layout which needs bounded height
  Widget _buildEventCard(BuildContext context, WidgetRef ref) {
    final eventCard = EventCard(
      tourEventCardModel: event,
      heroTagSuffix: '_foryou',
      onTap: () {
        ref
            .read(groupEventScreenProvider.notifier)
            .onSelectTournament(context: context, id: event.id);
      },
    );

    // On tablet, wrap in AspectRatio to give the Stack-based layout proper height
    // This matches the aspect ratio used in CURRENT tab's SliverGrid
    if (ResponsiveHelper.isTablet) {
      return AspectRatio(
        aspectRatio: ResponsiveHelper.isLandscape ? 1.4 : 1.2,
        child: eventCard,
      );
    }

    return eventCard;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shouldAnimate = !forYouAnimatedEventIds.contains(event.id);
    if (shouldAnimate) {
      forYouAnimatedEventIds.add(event.id);
    }

    final section = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Event card
        Padding(
          padding: EdgeInsets.only(top: isFirst ? 0 : 16.sp, bottom: 12.sp),
          child: _buildEventCard(context, ref),
        ),

        // Games for this event (lazy loaded with shimmer)
        _ForYouEventGames(eventId: event.id),
      ],
    );

    if (shouldAnimate) {
      return section
          .animate()
          .fadeIn(duration: 200.ms)
          .slideY(begin: 0.02, end: 0, duration: 200.ms);
    }

    return section;
  }
}

/// Single column in the 2-column tablet grid
/// Contains: event card on top + games stacked below (1 game per row within column)
class _ForYouTabletEventColumn extends ConsumerWidget {
  const _ForYouTabletEventColumn({super.key, required this.event});

  final GroupEventCardModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shouldAnimate = !forYouAnimatedEventIds.contains(event.id);
    if (shouldAnimate) {
      forYouAnimatedEventIds.add(event.id);
    }

    // Aspect ratio for event card in column layout
    // Landscape: wider cards since we have 2 columns
    // Portrait: taller cards for better visual
    final eventCardAspectRatio = ResponsiveHelper.isLandscape ? 1.8 : 1.4;

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Event card
        AspectRatio(
          aspectRatio: eventCardAspectRatio,
          child: EventCard(
            tourEventCardModel: event,
            heroTagSuffix: '_foryou_tablet_col',
            onTap: () {
              ref
                  .read(groupEventScreenProvider.notifier)
                  .onSelectTournament(context: context, id: event.id);
            },
          ),
        ),
        SizedBox(height: 10.sp),
        // Games for this event (stacked vertically, 1 per row in this column)
        _ForYouTabletColumnGames(eventId: event.id),
      ],
    );

    if (shouldAnimate) {
      return column
          .animate()
          .fadeIn(duration: 200.ms)
          .slideY(begin: 0.02, end: 0, duration: 200.ms);
    }

    return column;
  }
}

/// Games for a single column - shows games in 2-column grid (2 per row)
/// Uses auto-refresh provider that watches live games and re-fetches when they finish
class _ForYouTabletColumnGames extends ConsumerWidget {
  const _ForYouTabletColumnGames({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use auto-refresh provider that watches live game status
    final gamesAsync = ref.watch(forYouEventGamesWithAutoRefreshProvider(eventId));

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

        // Convert to GamesTourModel - limit to 4 games (2 rows of 2)
        final allGameModels =
            games
                .where((g) => g.players != null && g.players!.length >= 2)
                .map((g) => GamesTourModel.fromGame(g))
                .toList();

        if (allGameModels.isEmpty) {
          return const SizedBox.shrink();
        }

        // Take only first 4 games for tablet column view
        final gameModels = allGameModels.take(4).toList();

        // Build 2-column grid of games (2 per row, max 2 rows = 4 games)
        // Wrap with animated slots for smooth transitions when games change
        final List<Widget> rows = [];
        for (int i = 0; i < gameModels.length; i += 2) {
          final game1 = gameModels[i];
          final game2 = i + 1 < gameModels.length ? gameModels[i + 1] : null;

          rows.add(
            Padding(
              padding: EdgeInsets.only(bottom: 8.sp),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _AnimatedGameCardSlot(
                      key: ValueKey('tablet_slot_$i'),
                      gameId: game1.gameId,
                      child: _TabletGameCard(
                        game: game1,
                        games: gameModels,
                        index: i,
                      ),
                    ),
                  ),
                  SizedBox(width: 8.sp),
                  Expanded(
                    child:
                        game2 != null
                            ? _AnimatedGameCardSlot(
                              key: ValueKey('tablet_slot_${i + 1}'),
                              gameId: game2.gameId,
                              child: _TabletGameCard(
                                game: game2,
                                games: gameModels,
                                index: i + 1,
                              ),
                            )
                            : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(children: rows);
      },
      loading: () => _buildColumnShimmer(),
      error: (error, stack) {
        debugPrint(
          '[_ForYouTabletColumnGames] Error loading games for $eventId: $error',
        );
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

  Widget _buildColumnShimmer() {
    // Show 2 rows of 2 game cards (4 total) matching actual content
    return Column(
      children: List.generate(2, (rowIndex) {
        return Padding(
          padding: EdgeInsets.only(bottom: 8.sp),
          child: Row(
            children: [
              Expanded(
                child: SkeletonWidget(
                  ignoreContainers: true,
                  child: Container(
                    height: 72.sp,
                    decoration: BoxDecoration(
                      color: kBlack2Color,
                      borderRadius: BorderRadius.circular(8.br),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8.sp),
              Expanded(
                child: SkeletonWidget(
                  ignoreContainers: true,
                  child: Container(
                    height: 72.sp,
                    decoration: BoxDecoration(
                      color: kBlack2Color,
                      borderRadius: BorderRadius.circular(8.br),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// Clean game card for tablet grid - full game card style, not compact
class _TabletGameCard extends ConsumerWidget {
  const _TabletGameCard({
    required this.game,
    required this.games,
    required this.index,
  });

  final GamesTourModel game;
  final List<GamesTourModel> games;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridGameCardWrapperWidget(
      key: ValueKey('tablet_grid_game_${game.gameId}'),
      game: game,
      orderedGames: games,
      gameIndex: index,
      onChangedWithLiveGames:
          (updatedGames) => ref
              .read(gameCardWrapperProvider)
              .navigateToChessBoard(
                context: context,
                orderedGames: updatedGames,
                gameIndex: index,
                onReturnFromChessboard: (_) {},
                viewSource: ChessboardView.forYou,
              ),
      pinnedIds: const [],
      onPinToggle: (_) {},
    );
  }
}

/// Games section for one event - loads lazily with shimmer
/// Uses auto-refresh provider that watches live games and re-fetches when they finish
class _ForYouEventGames extends ConsumerWidget {
  const _ForYouEventGames({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use auto-refresh provider that watches live game status
    final gamesAsync = ref.watch(forYouEventGamesWithAutoRefreshProvider(eventId));
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
        final gameModels =
            games
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

        // List mode: one game per row with smooth transition animation
        return Column(
          children: List.generate(gameModels.length, (index) {
            final game = gameModels[index];
            return _AnimatedGameCardSlot(
              key: ValueKey('slot_$index'),
              gameId: game.gameId,
              child: _ForYouGameCard(
                key: ValueKey('game_${game.gameId}'),
                game: game,
                gamesData: gamesData,
                gameIndex: index,
                allGames: gameModels,
                viewMode: viewMode,
              ),
            );
          }),
        );
      },
      loading: () => _buildGameShimmers(viewMode),
      error: (error, stack) {
        debugPrint(
          '[ForYouEventGames] Error loading games for $eventId: $error',
        );
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
                child: _AnimatedGameCardSlot(
                  key: ValueKey('grid_slot_$i'),
                  gameId: game1.gameId,
                  child: GridGameCardWrapperWidget(
                    key: ValueKey('grid_game_${game1.gameId}'),
                    game: game1,
                    orderedGames: games,
                    gameIndex: i,
                    onChangedWithLiveGames:
                        (updatedGames) => ref
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
              ),
              SizedBox(width: 12.sp),
              Expanded(
                child:
                    game2 != null
                        ? _AnimatedGameCardSlot(
                          key: ValueKey('grid_slot_${i + 1}'),
                          gameId: game2.gameId,
                          child: GridGameCardWrapperWidget(
                            key: ValueKey('grid_game_${game2.gameId}'),
                            game: game2,
                            orderedGames: games,
                            gameIndex: i + 1,
                            onChangedWithLiveGames:
                                (updatedGames) => ref
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
                          ),
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
          .fadeIn(
            duration: 150.ms,
            delay: Duration(milliseconds: gameIndex * 50),
          )
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

// ============================================================================
// ANIMATED GAME CARD TRANSITION
// ============================================================================

/// Animated wrapper for game cards using motor springs
/// Provides smooth crossfade with scale when game at a slot changes
class _AnimatedGameCardSlot extends StatefulWidget {
  const _AnimatedGameCardSlot({
    super.key,
    required this.gameId,
    required this.child,
  });

  final String gameId;
  final Widget child;

  @override
  State<_AnimatedGameCardSlot> createState() => _AnimatedGameCardSlotState();
}

class _AnimatedGameCardSlotState extends State<_AnimatedGameCardSlot> {
  double _animationProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _animationProgress = 1.0; // Start fully visible
  }

  @override
  void didUpdateWidget(covariant _AnimatedGameCardSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If game changed, trigger animation
    if (oldWidget.gameId != widget.gameId) {
      _animationProgress = 0.0;
      // Animate to 1.0
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _animationProgress = 1.0;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      motion: const CupertinoMotion.bouncy(),
      value: _animationProgress,
      builder: (context, value, child) {
        // Scale and fade in effect
        final scale = 0.92 + (0.08 * value);
        final opacity = value.clamp(0.0, 1.0);

        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: widget.child,
          ),
        );
      },
    );
  }
}
