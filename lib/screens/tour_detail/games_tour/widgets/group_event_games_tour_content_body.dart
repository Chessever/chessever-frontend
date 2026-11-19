import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/group_event_match_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/search_list_resume.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_games_list_end.dart';
import 'package:chessever2/widgets/positioned_list_scrollbar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_list_presentation_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class GroupEventGamesTourContentBody extends ConsumerStatefulWidget {
  final GamesScreenModel gamesScreenModel;
  final GamesListViewMode gamesListViewMode;
  final void Function(int)? onReturnFromChessboard;

  /// Where the list starts when it is built afresh (a search's hits giving
  /// way to every matchup): the reader's place before the search.
  final ListResumePoint? startAt;

  const GroupEventGamesTourContentBody({
    super.key,
    required this.gamesScreenModel,
    required this.gamesListViewMode,
    this.onReturnFromChessboard,
    this.startAt,
  });

  @override
  ConsumerState<GroupEventGamesTourContentBody> createState() =>
      _GroupEventGamesTourContentBodyState();
}

class _GroupEventGamesTourContentBodyState
    extends ConsumerState<GroupEventGamesTourContentBody> {
  @override
  Widget build(BuildContext context) {
    final groupedData = ref.watch(gamesTourGroupedProvider);
    if (groupedData.isLoading) {
      return const TourLoadingWidget();
    }
    final gamesByRound = groupedData.gamesByRound;
    // Same rounds, same order as an individual event's Games list: a live
    // round whose boards have no moves yet stays on screen.
    final visibleRounds = ref.watch(gamesTourDisplayRoundsProvider);

    if (visibleRounds.isEmpty) {
      return const SizedBox.shrink();
    }

    // Matchup grouping is this tab's visual order: boards render under their
    // team-pair card, not interleaved by the flat Games-tab sort. The board
    // switcher receives that same order so a swipe moves to the adjacent board
    // of the same matchup instead of the next team's board (Trello #1158).
    final groupedByRound = <String, Map<String, List<MatchWithComparison>>>{
      for (final round in visibleRounds)
        round.id: ref
            .read(gamesTourContentProvider)
            .getGroupHeader(
              selectedRoundId: round.id,
              gamesScreenModel: widget.gamesScreenModel.copyWith(
                gamesTourModels:
                    gamesByRound[round.id] ?? const <GamesTourModel>[],
              ),
              roundName: round.name,
            ),
    };
    final orderedGamesData = widget.gamesScreenModel.copyWith(
      gamesTourModels: <GamesTourModel>[
        for (final round in visibleRounds)
          ...orderedGamesForTeamMatchups(groupedByRound[round.id]!),
      ],
    );
    final liveBatchKeyByGameId = buildGroupEventLiveBatchKeys(
      orderedGamesData.gamesTourModels,
    );

    // Get scroll controller and listener from provider
    final scopeId = ref.watch(gamesTourScrollScopeProvider);
    final shouldStream = ref.watch(tournamentDataActiveProvider);
    final streamEnabled = shouldStream;
    final allowStockfishFallback = streamEnabled;
    final scrollController = ref.watch(gamesTourScrollProvider(scopeId));
    final itemPositionsListener = ref
        .watch(gamesTourScrollProvider(scopeId).notifier)
        .itemPositionsListener;
    final roundExpansionState = ref.watch(roundExpansionProvider);

    return _buildAllRoundsView(
      context,
      visibleRounds,
      gamesByRound,
      groupedByRound,
      orderedGamesData,
      scrollController,
      itemPositionsListener,
      roundExpansionState,
      liveBatchKeyByGameId,
      allowStockfishFallback,
      streamEnabled,
      scopeId,
    );
  }

  Widget _buildAllRoundsView(
    BuildContext context,
    List<GamesAppBarModel> visibleRounds,
    Map<String, List<GamesTourModel>> gamesByRound,
    Map<String, Map<String, List<MatchWithComparison>>> groupedByRound,
    GamesScreenModel orderedGamesData,
    ItemScrollController scrollController,
    ItemPositionsListener itemPositionsListener,
    Map<String, bool> roundExpansionState,
    Map<String, LiveGamesBatchKey> liveBatchKeyByGameId,
    bool allowStockfishFallback,
    bool streamEnabled,
    String scopeId,
  ) {
    // Build a flat list of all items with round tracking
    final allItems = <_GroupEventItem>[];
    // A search opens every round with a hit, as the board list does, so no
    // hit hides in a folded round; the folds come back as it ends.
    final isSearchMode = widget.gamesScreenModel.isSearchMode;

    for (final round in visibleRounds) {
      final roundGames = gamesByRound[round.id] ?? const <GamesTourModel>[];
      final grouped = groupedByRound[round.id]!;

      final isRoundExpanded =
          isSearchMode || (roundExpansionState[round.id] ?? true);

      // Add round header item
      allItems.add(
        _GroupEventItem(
          roundId: round.id,
          widget: RoundHeader(
            round: round,
            roundGames: roundGames,
            isExpanded: isRoundExpanded,
            onToggle: isSearchMode
                ? null
                : () {
                    ref
                        .read(roundExpansionProvider.notifier)
                        .toggleRound(round.id);
                  },
          ),
          isHeader: true,
        ),
      );

      if (!isRoundExpanded) {
        continue;
      }

      // Add all team matchup cards for this round
      for (final header in grouped.keys) {
        final gamesForTeam = grouped[header]!;
        allItems.add(
          _GroupEventItem(
            roundId: round.id,
            widget: GroupEventMatchCard(
              roundTitle: header,
              games: gamesForTeam,
              gamesData: orderedGamesData,
              gamesListViewMode: widget.gamesListViewMode,
              onReturnFromChessboard: widget.onReturnFromChessboard,
              liveBatchKeyByGameId: liveBatchKeyByGameId,
              allowStockfishFallback: allowStockfishFallback,
              streamEnabled: streamEnabled,
            ),
            isHeader: false,
          ),
        );
      }
    }

    final listItemCount = allItems.length;
    final start = listItemCount == 0
        ? null
        : widget.startAt?.clampedTo(listItemCount);
    return GamesTourScrollActivityDetector(
      scopeId: scopeId,
      child: PositionedListScrollbar(
        itemPositionsListener: itemPositionsListener,
        itemScrollController: scrollController,
        itemCount: listItemCount,
        thumbWidth: 4.sp,
        padding: EdgeInsets.only(
          top: 0,
          bottom: MediaQuery.of(context).viewPadding.bottom + 8.sp,
        ),
        child: ScrollablePositionedList.builder(
          // The hits and every matchup are two lists: the hits start at
          // their top, every matchup comes back where the reader left it.
          key: ValueKey('team_matchups_search_$isSearchMode'),
          itemScrollController: scrollController,
          itemPositionsListener: itemPositionsListener,
          initialScrollIndex: start?.index ?? 0,
          initialAlignment: start?.alignment ?? 0,
          // The bottom is the last row's: [EventGamesListEnd].
          padding: EdgeInsets.only(left: 16.sp, right: 16.sp, top: 8.sp),
          // The matchups, then where the list ends.
          itemCount: listItemCount + 1,
          itemBuilder: (context, index) {
            // Clear of the floating buttons, giving way with them as the
            // search opens, as every Games list ends.
            if (index == listItemCount) return const EventGamesListEnd();
            final item = allItems[index];
            final isLastItem = index == listItemCount - 1;
            final nextIsHeader = !isLastItem && allItems[index + 1].isHeader;

            // Apply beautiful UI spacing with visual hierarchy
            EdgeInsets padding;
            if (item.isHeader) {
              // Round headers get more spacing below (16sp)
              padding = EdgeInsets.only(bottom: 16.sp);
            } else {
              // Team cards: standard spacing (12sp), extra before next header (20sp)
              padding = EdgeInsets.only(bottom: nextIsHeader ? 20.sp : 12.sp);
            }

            return Padding(padding: padding, child: item.widget);
          },
        ),
      ),
    );
  }
}

/// Helper class to track items with their round association
class _GroupEventItem {
  final String roundId;
  final Widget widget;
  final bool isHeader;

  _GroupEventItem({
    required this.roundId,
    required this.widget,
    required this.isHeader,
  });
}
