import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/group_event_match_card.dart';
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
    final selectedRoundId = ref.watch(
      gamesAppBarProvider.select((v) => v.value?.selectedId),
    );

    final gamesAppBar = ref.watch(gamesAppBarProvider);
    if (gamesAppBar.isLoading || !gamesAppBar.hasValue) {
      return const TourLoadingWidget();
    }
    final rounds = gamesAppBar.value!.gamesAppBarModels;
    final orderedGamesData = ref
        .read(gamesTourContentProvider)
        .getOrderedGamesForChessBoard(
          rounds: rounds,
          gamesScreenModel: widget.gamesScreenModel,
        );

    return widget.gamesScreenModel.isSearchMode
        ? _buildGroupedGameCardsOnSearchMode(rounds, orderedGamesData)
        : selectedRoundId != null
        ? Padding(
          padding: EdgeInsets.only(left: 16.sp, right: 16.sp, bottom: 12.sp),
          child: _buildGroupedGameCardsBuilder(
            rounds,
            rounds.firstWhere((r) => r.id == selectedRoundId),
            orderedGamesData,
          ),
        )
        : const SizedBox.shrink();
  }

  Widget _buildGroupedGameCardsBuilder(
    List<GamesAppBarModel> gamesAppBarModels,
    GamesAppBarModel selectedRound,
    GamesScreenModel orderedGamesData,
  ) {
    final grouped = ref
        .read(gamesTourContentProvider)
        .getGroupHeader(
          selectedRoundId: selectedRound.id,
          gamesScreenModel: widget.gamesScreenModel,
        );

    // Build grouped cards
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final header = grouped.keys.elementAt(index);
        final gamesForTeam = grouped[header]!;

        return GroupEventMatchCard(
          roundTitle: header,
          games: gamesForTeam,
          gamesData: orderedGamesData,
          gamesListViewMode: widget.gamesListViewMode,
          onReturnFromChessboard: widget.onReturnFromChessboard,
        );
      },
    );
  }

  Widget _buildGroupedGameCardsOnSearchMode(
    List<GamesAppBarModel> gamesAppBarModels,
    GamesScreenModel orderedGamesData,
  ) {
    final grouped = ref
        .read(gamesTourContentProvider)
        .getGroupHeaderOnSearch(
          rounds: gamesAppBarModels,
          gamesScreenModel: widget.gamesScreenModel,
        );

    // Build grouped cards
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final header = grouped.keys.elementAt(index);
        final gamesForTeam = grouped[header]!;

        return GroupEventMatchCard(
          roundTitle: header,
          games: gamesForTeam,
          gamesData: orderedGamesData,
          gamesListViewMode: widget.gamesListViewMode,
          onReturnFromChessboard: widget.onReturnFromChessboard,
        );
      },
    );
  }
}
