import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/group_event_match_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/widgets/positioned_list_scrollbar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class GroupEventGamesTourContentBody extends ConsumerStatefulWidget {
  final GamesScreenModel gamesScreenModel;
  final GamesListViewMode gamesListViewMode;
  final void Function(int)? onReturnFromChessboard;

  const GroupEventGamesTourContentBody({
    super.key,
    required this.gamesScreenModel,
    required this.gamesListViewMode,
    this.onReturnFromChessboard,
  });

  @override
  ConsumerState<GroupEventGamesTourContentBody> createState() =>
      _GroupEventGamesTourContentBodyState();
}

class _GroupEventGamesTourContentBodyState
    extends ConsumerState<GroupEventGamesTourContentBody> {
  @override
  Widget build(BuildContext context) {
    final gamesAppBar = ref.watch(gamesAppBarProvider);
    if (gamesAppBar.isLoading || !gamesAppBar.hasValue) {
      return const TourLoadingWidget();
    }
    final rounds = gamesAppBar.value!.gamesAppBarModels;
    final selectedRoundId = gamesAppBar.value?.selectedId;
    final userSelected = gamesAppBar.value?.userSelectedId ?? false;

    // Filter rounds to hide upcoming rounds by default.
    // Include upcoming only when user explicitly selected that round.
    final visibleRounds =
        rounds.where((round) {
          final roundGames =
              widget.gamesScreenModel.gamesTourModels
                  .where((game) => game.roundId == round.id)
                  .toList();
          if (roundGames.isEmpty) return false;

          // Always include explicitly user-selected round
          if (userSelected && round.id == selectedRoundId) return true;

          // Otherwise, exclude upcoming rounds
          return round.roundStatus != RoundStatus.upcoming;
        }).toList();

    if (visibleRounds.isEmpty) {
      return const SizedBox.shrink();
    }

    final orderedGamesData = ref
        .read(gamesTourContentProvider)
        .getOrderedGamesForChessBoard(
          rounds: visibleRounds,
          gamesScreenModel: widget.gamesScreenModel,
        );

    // Get scroll controller and listener from provider
    final scopeId = ref.watch(gamesTourScrollScopeProvider);
    final scrollController = ref.watch(gamesTourScrollProvider(scopeId));
    final itemPositionsListener =
        ref.watch(gamesTourScrollProvider(scopeId).notifier).itemPositionsListener;
    final roundExpansionState = ref.watch(roundExpansionProvider);

    return _buildAllRoundsView(
      context,
      visibleRounds,
      orderedGamesData,
      scrollController,
      itemPositionsListener,
      roundExpansionState,
    );
  }

  Widget _buildAllRoundsView(
    BuildContext context,
    List<GamesAppBarModel> visibleRounds,
    GamesScreenModel orderedGamesData,
    ItemScrollController scrollController,
    ItemPositionsListener itemPositionsListener,
    Map<String, bool> roundExpansionState,
  ) {
    // Build a flat list of all items with round tracking
    final allItems = <_GroupEventItem>[];

    for (final round in visibleRounds) {
      // Get team groupings for this round
      final grouped = ref
          .read(gamesTourContentProvider)
          .getGroupHeader(
            selectedRoundId: round.id,
            gamesScreenModel: widget.gamesScreenModel,
          );

      // Get all games for this round to show in header
      final roundGames =
          widget.gamesScreenModel.gamesTourModels
              .where((game) => game.roundId == round.id)
              .toList();

      final isRoundExpanded = roundExpansionState[round.id] ?? true;

      // Add round header item
      allItems.add(
        _GroupEventItem(
          roundId: round.id,
          widget: RoundHeader(
            round: round,
            roundGames: roundGames,
            isExpanded: isRoundExpanded,
            onToggle: () {
              ref.read(roundExpansionProvider.notifier).toggleRound(round.id);
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
            ),
            isHeader: false,
          ),
        );
      }
    }

    // Build scrollable positioned list with all rounds
    return PositionedListScrollbar(
      itemPositionsListener: itemPositionsListener,
      itemScrollController: scrollController,
      itemCount: allItems.length,
      thumbWidth: 4.sp,
      padding: EdgeInsets.only(
        top: 16.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom + 8.sp,
      ),
      child: ScrollablePositionedList.builder(
        itemScrollController: scrollController,
        itemPositionsListener: itemPositionsListener,
        padding: EdgeInsets.only(
          left: 16.sp,
          right: 16.sp,
          top: 16.sp,
          bottom: MediaQuery.of(context).viewPadding.bottom + 8.sp,
        ),
        itemCount: allItems.length,
        itemBuilder: (context, index) {
          final item = allItems[index];
          final isLastItem = index == allItems.length - 1;
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
