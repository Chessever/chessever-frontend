import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_list_view.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_list_presentation_provider.dart';

class GamesTourContentBody extends ConsumerWidget {
  final GamesScreenModel gamesScreenModel;
  final GamesListViewMode gamesListViewMode;

  const GamesTourContentBody({
    super.key,
    required this.gamesScreenModel,
    required this.gamesListViewMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupedData = ref.watch(gamesTourGroupedProvider);
    if (groupedData.isLoading) {
      return const TourLoadingWidget();
    }

    final presentation = ref.watch(gamesTourListPresentationProvider);
    final gamesByRound = presentation.gamesByRound;

    final isSearchMode = gamesScreenModel.isSearchMode;
    final scopeId = ref.watch(gamesTourScrollScopeProvider);

    final orderedGamesData = gamesScreenModel.copyWith(
      gamesTourModels: presentation.layout.orderedGames,
    );

    final itemScrollController = ref.watch(gamesTourScrollProvider(scopeId));
    final itemPositionsListener =
        ref
            .read(gamesTourScrollProvider(scopeId).notifier)
            .itemPositionsListener;

    return GamesListView(
      key: ValueKey(
        'games_list_${gamesListViewMode.name}_search_$isSearchMode',
      ),
      gamesByRound: gamesByRound,
      gamesData: orderedGamesData,
      gamesListViewMode: gamesListViewMode,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      isSearchMode: isSearchMode,
      layout: presentation.layout,
      onReturnFromChessboard: (returnedIndex) {
        // The scrolling is already handled in GamesListView
        // This callback can be used for additional logic if needed
      },
    );
  }
}
