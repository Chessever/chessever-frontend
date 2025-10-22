import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/group_event_match_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/utils/responsive_helper.dart';

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
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gamesAppBar = ref.watch(gamesAppBarProvider);
    if (gamesAppBar.isLoading || !gamesAppBar.hasValue) {
      return const TourLoadingWidget();
    }
    final rounds = gamesAppBar.value!.gamesAppBarModels;

    // Filter to only rounds that have games
    final visibleRounds =
        rounds
            .where((round) => widget.gamesScreenModel.gamesTourModels
                .any((game) => game.roundId == round.id))
            .toList();

    if (visibleRounds.isEmpty) {
      return const SizedBox.shrink();
    }

    final orderedGamesData = ref
        .read(gamesTourContentProvider)
        .getOrderedGamesForChessBoard(
          rounds: rounds,
          gamesScreenModel: widget.gamesScreenModel,
        );

    return Padding(
      padding: EdgeInsets.only(left: 16.sp, right: 16.sp, bottom: 12.sp),
      child: _buildAllRoundsView(
        visibleRounds,
        orderedGamesData,
      ),
    );
  }

  Widget _buildAllRoundsView(
    List<GamesAppBarModel> visibleRounds,
    GamesScreenModel orderedGamesData,
  ) {
    // Build a list of all items: [round header, team cards, round header, team cards, ...]
    final allItems = <Widget>[];

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

      // Add round header
      allItems.add(
        RoundHeader(
          round: round,
          roundGames: roundGames,
        ),
      );

      // Add all team matchup cards for this round
      for (final header in grouped.keys) {
        final gamesForTeam = grouped[header]!;
        allItems.add(
          GroupEventMatchCard(
            roundTitle: header,
            games: gamesForTeam,
            gamesData: orderedGamesData,
            gamesListViewMode: widget.gamesListViewMode,
            onReturnFromChessboard: widget.onReturnFromChessboard,
          ),
        );
      }
    }

    // Build scrollable list with all rounds
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      itemCount: allItems.length,
      itemBuilder: (context, index) {
        return allItems[index];
      },
    );
  }
}
