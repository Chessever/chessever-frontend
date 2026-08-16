import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_flattened_layout.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/match_header_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/widgets/positioned_list_scrollbar.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

// RoundStatus is already imported via games_app_bar_view_model.dart

class GamesListView extends ConsumerWidget {
  const GamesListView({
    super.key,
    required this.gamesByRound,
    required this.gamesData,
    required this.gamesListViewMode,
    required this.itemScrollController,
    required this.itemPositionsListener,
    this.isSearchMode = false,
    this.onReturnFromChessboard,
    required this.layout,
  });

  final Map<String, List<GamesTourModel>> gamesByRound;
  final GamesScreenModel gamesData;
  final GamesListViewMode gamesListViewMode;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final bool isSearchMode;
  final void Function(int)? onReturnFromChessboard;
  final GamesTourFlattenedLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Expansion states for rounds and matches
    // In search mode, override expansion to show everything
    final scopeId = ref.watch(gamesTourScrollScopeProvider);
    final shouldStream = ref.watch(shouldStreamProvider);
    final streamEnabled = shouldStream;
    final allowStockfishFallback = streamEnabled;
    final orderedGamesList = layout.orderedGames;

    // Realtime fan-in: instead of one Supabase channel PER card (which blows
    // the per-client channel rate limit — `ChannelRateLimitReached` — and
    // silently kills live updates, leaving only the slow poll), every mounted
    // live Supabase game in a round shares a batched `.inFilter` channel. Each
    // card still rebuilds individually (it selects only its own gameId from
    // the shared update map), so updates stay per-card and instant. Chunked so
    // one channel's `in` filter never grows unbounded on huge rounds.
    final liveBatchKeyByGameId = _buildLiveBatchKeys(gamesByRound);

    // No Spoilers is stored per event under the tour the menu writes —
    // `aboutTourModel.id` (tournament_menu_button.dart). Keying off a game's
    // own `tourId` instead would miss every multi-stage knockout, because
    // those rounds are filled from sibling tours, so the setting would hide
    // nothing on exactly the events that have match headers. Read once here
    // rather than per row: it is one value for the whole list, and this keeps
    // the provider's first touch (which does sqlite I/O) out of the lazy
    // sliver layout pass.
    final eventTourId = ref.watch(
      tourDetailScreenProvider.select(
        (state) => state.valueOrNull?.aboutTourModel.id,
      ),
    );
    // Hide while the stored value is still loading too, so a score can never
    // flash before the setting resolves.
    final hideMatchScores =
        eventTourId == null || eventTourId.isEmpty
            ? false
            : ref.watch(
              eventNoSpoilersProvider(
                eventTourId,
              ).select((state) => state.isLoading || state.enabled),
            );

    final itemCount = layout.itemCount;

    if (itemCount == 0) {
      return const SizedBox.shrink();
    }

    // Tablet-optimized horizontal padding
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.sp,
      tablet: 24.sp,
    );

    // Wrap in Center + ConstrainedBox for tablet max-width
    Widget listContent = PositionedListScrollbar(
      itemPositionsListener: itemPositionsListener,
      itemScrollController: itemScrollController,
      itemCount: itemCount,
      thumbWidth: 4.sp,
      padding: EdgeInsets.only(
        top: 0,
        bottom: MediaQuery.of(context).viewPadding.bottom + 8.sp,
      ),
      child: LayoutBuilder(
        builder: (context, outerConstraints) {
          // TABLET FIX: Capture the available width from LayoutBuilder
          // and pass it to items to ensure they have bounded width.
          // ScrollablePositionedList can give unbounded width to items,
          // which breaks nested Expanded widgets.
          final itemWidth =
              ResponsiveHelper.isTablet ? outerConstraints.maxWidth : null;

          return ScrollablePositionedList.builder(
            itemScrollController: itemScrollController,
            itemPositionsListener: itemPositionsListener,
            itemCount: itemCount,
            minCacheExtent: listCacheExtentPixels(context),
            itemBuilder: (context, index) {
              final lookup = layout.entryAt(index);

              if (lookup == null) {
                return const SizedBox.shrink();
              }

              if (lookup is GamesTourMatchFormatHeaderEntry) {
                return Padding(
                  padding: EdgeInsets.only(bottom: 16.sp),
                  child: MatchHeader(
                    match: lookup.matchHeader,
                    hideScores: hideMatchScores,
                    isExpanded: true,
                    onToggle: null,
                  ),
                );
              }

              if (lookup is GamesTourRoundHeaderEntry) {
                final isRoundExpanded =
                    isSearchMode
                        ? true
                        : ref.watch(
                          roundExpansionStateProvider(lookup.round.id),
                        );
                return Padding(
                  padding: EdgeInsets.only(bottom: 16.sp),
                  child: RoundHeader(
                    round: lookup.round,
                    roundGames: lookup.roundGames,
                    isExpanded: isRoundExpanded,
                    onToggle:
                        isSearchMode
                            ? null // Disable toggle in search mode
                            : () {
                              ref
                                  .read(roundExpansionProvider.notifier)
                                  .toggleRound(lookup.round.id);
                            },
                  ),
                );
              }

              if (lookup is GamesTourMatchHeaderEntry) {
                final matchKey = lookup.matchHeader.matchKey;
                final isExpanded =
                    isSearchMode
                        ? true
                        : ref.watch(matchExpansionStateProvider(matchKey));

                return Padding(
                  padding: EdgeInsets.only(bottom: 12.sp),
                  child: MatchHeader(
                    match: lookup.matchHeader,
                    hideScores: hideMatchScores,
                    isExpanded: isExpanded,
                    onToggle:
                        isSearchMode
                            ? null // Disable toggle in search mode
                            : () {
                              ref
                                  .read(matchExpansionProvider.notifier)
                                  .toggleMatch(matchKey);
                            },
                  ),
                );
              }

              if (lookup is GamesTourGameRowEntry) {
                Widget rowContent = Padding(
                  padding: EdgeInsets.only(
                    bottom: lookup.isLastInSection ? 20.sp : 12.sp,
                  ),
                  child:
                      gamesListViewMode == GamesListViewMode.chessBoardGrid
                          ? _buildGridRow(
                            context,
                            ref,
                            lookup,
                            orderedGamesList,
                            liveBatchKeyByGameId,
                            allowStockfishFallback,
                            streamEnabled,
                          )
                          : _buildCardRow(
                            context,
                            ref,
                            lookup,
                            orderedGamesList,
                            liveBatchKeyByGameId,
                            allowStockfishFallback,
                            streamEnabled,
                          ),
                );
                // TABLET: Wrap with SizedBox to provide bounded width
                if (itemWidth != null) {
                  if (gamesListViewMode != GamesListViewMode.chessBoardGrid &&
                      ResponsiveHelper.isTablet) {
                    // Compact List View for Tablet
                    rowContent = SizedBox(
                      width: itemWidth,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600.0),
                          child: rowContent,
                        ),
                      ),
                    );
                  } else {
                    rowContent = SizedBox(width: itemWidth, child: rowContent);
                  }
                }
                return rowContent;
              }

              return const SizedBox.shrink();
            },
            padding: EdgeInsets.only(
              left: horizontalPadding,
              right: horizontalPadding,
              top: 8.sp,
              bottom: MediaQuery.of(context).viewPadding.bottom + 8.sp,
            ),
          );
        },
      ),
    );

    // Note: Tablet max-width constraint is applied by parent TournamentDetailScreen
    // Applying it here would create nested Center > ConstrainedBox which can cause
    // layout issues on tablet landscape with PageView animations.
    return GamesTourScrollActivityDetector(
      scopeId: scopeId,
      child: listContent,
    );
  }

  Widget _buildGridRow(
    BuildContext context,
    WidgetRef ref,
    GamesTourGameRowEntry item,
    List<GamesTourModel> orderedGamesList,
    Map<String, LiveGamesBatchKey> liveBatchKeyByGameId,
    bool allowStockfishFallback,
    bool streamEnabled,
  ) {
    final game1Widget = _buildGridGame(
      context,
      ref,
      item.game1,
      item.globalIndex1,
      orderedGamesList,
      item.fixedBottomSide1,
      liveBatchKeyByGameId,
      allowStockfishFallback,
      streamEnabled,
    );

    final game2Widget =
        item.game2 != null
            ? _buildGridGame(
              context,
              ref,
              item.game2!,
              item.globalIndex2!,
              orderedGamesList,
              item.fixedBottomSide2,
              liveBatchKeyByGameId,
              allowStockfishFallback,
              streamEnabled,
            )
            : null;

    // On tablet, use Expanded to give children bounded width constraints.
    // Without this, Row with spaceBetween gives children unbounded width,
    // which breaks nested Expanded widgets in PlayerFirstRowDetailWidget.
    if (ResponsiveHelper.isTablet) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: game1Widget),
          SizedBox(width: 16.sp),
          Expanded(child: game2Widget ?? const SizedBox()),
        ],
      );
    }

    // On phone, keep original spaceBetween layout
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [game1Widget, if (game2Widget != null) game2Widget],
    );
  }

  Widget _buildGridGame(
    BuildContext context,
    WidgetRef ref,
    GamesTourModel game,
    int globalIndex,
    List<GamesTourModel> orderedGamesList,
    Side? fixedBottomSide,
    Map<String, LiveGamesBatchKey> liveBatchKeyByGameId,
    bool allowStockfishFallback,
    bool streamEnabled,
  ) {
    return GridGameCardWrapperWidget(
      key: ValueKey('game_${game.gameId}'),
      game: game,
      liveBatchKey: liveBatchKeyByGameId[game.gameId],
      orderedGames: orderedGamesList,
      gameIndex: globalIndex,
      onChangedWithLiveGames:
          (updatedGames) => ref
              .read(gameCardWrapperProvider)
              .navigateToChessBoard(
                context: context,
                orderedGames: updatedGames,
                gameIndex: globalIndex,
                onReturnFromChessboard: (returnedIndex) {
                  _scrollToGameIndex(returnedIndex);
                  onReturnFromChessboard?.call(returnedIndex);
                },
                listPolicy: boardNavigationListPolicyForGamesData(gamesData),
              ),
      pinnedIds: gamesData.pinnedGamedIs,
      fixedBottomSide: fixedBottomSide,
      allowStockfishFallback: allowStockfishFallback,
      streamEnabled: streamEnabled,
      onPinToggle:
          (_) async => await ref
              .read(gamesTourScreenProvider.notifier)
              .togglePinGame(game.gameId, sourceTourId: game.tourId),
    );
  }

  Widget _buildCardRow(
    BuildContext context,
    WidgetRef ref,
    GamesTourGameRowEntry item,
    List<GamesTourModel> orderedGamesList,
    Map<String, LiveGamesBatchKey> liveBatchKeyByGameId,
    bool allowStockfishFallback,
    bool streamEnabled,
  ) {
    // Create modified gamesData with correct orderedGames for multi-stage knockouts
    final modifiedGamesData = GamesScreenModel(
      gamesTourModels: orderedGamesList,
      pinnedGamedIs: gamesData.pinnedGamedIs,
    );

    return GameCardWrapperWidget(
      game: item.game1,
      liveBatchKey: liveBatchKeyByGameId[item.game1.gameId],
      gamesData: modifiedGamesData,
      gameIndex: item.globalIndex1,
      isChessBoardVisible: gamesListViewMode == GamesListViewMode.chessBoard,
      navigationListPolicy: boardNavigationListPolicyForGamesData(gamesData),
      fixedBottomSide: item.fixedBottomSide1,
      allowStockfishFallback: allowStockfishFallback,
      streamEnabled: streamEnabled,
      onReturnFromChessboard: (returnedIndex) {
        _scrollToGameIndex(returnedIndex);
        onReturnFromChessboard?.call(returnedIndex);
      },
    );
  }

  void _scrollToGameIndex(int gameIndex) {
    final listIndex = layout.itemIndexForOrderedGameIndex(gameIndex);
    if (listIndex != null) {
      itemScrollController.scrollTo(
        index: listIndex,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }
}

/// Builds the gameId → shared [LiveGamesBatchKey] map for the whole list.
///
/// Every live Supabase game in a round is assigned a chunked batch key so the
/// round's visible live games share a handful of realtime channels instead of
/// one channel per card. Finished/static cards remain display-only.
Map<String, LiveGamesBatchKey> _buildLiveBatchKeys(
  Map<String, List<GamesTourModel>> gamesByRound,
) {
  final result = <String, LiveGamesBatchKey>{};
  for (final entry in gamesByRound.entries) {
    final roundId = entry.key;
    result.addAll(
      liveBatchKeysForGames(
        games: entry.value,
        scopePrefix: 'tour_round:$roundId',
      ),
    );
  }
  return result;
}
