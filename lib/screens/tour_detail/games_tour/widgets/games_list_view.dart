import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class GamesListView extends ConsumerWidget {
  final List<GamesAppBarModel> rounds;
  final Map<String, List<GamesTourModel>> gamesByRound;
  final GamesScreenModel gamesData;
  final bool isChessBoardVisible;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final void Function(int)? onReturnFromChessboard;

  const GamesListView({
    super.key,
    required this.rounds,
    required this.gamesByRound,
    required this.gamesData,
    required this.isChessBoardVisible,
    required this.itemScrollController,
    required this.itemPositionsListener,
    this.onReturnFromChessboard,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reversedRounds = rounds.reversed.toList();
    final items = _buildItems(
      reversedRounds,
      gamesByRound,
      gamesData,
      isChessBoardVisible,
    );

    return ScrollablePositionedList.builder(
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
      padding: EdgeInsets.only(
        left: 20.sp,
        right: 20.sp,
        top: 16.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom,
      ),
    );
  }

  void _scrollToGameIndex(int gameIndex) {
    // Calculate the position in the list for the given game index
    // We need to account for round headers and games before this index
    int listIndex = 0;
    int currentGameIndex = 0;

    final reversedRounds = rounds.reversed.toList();

    for (final round in reversedRounds) {
      // Add 1 for the round header
      listIndex++;

      final roundGames = gamesByRound[round.id] ?? [];
      for (int i = 0; i < roundGames.length; i++) {
        if (currentGameIndex == gameIndex) {
          // Found the target game, scroll to this position
          itemScrollController.scrollTo(
            index: listIndex,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
          return;
        }
        listIndex++;
        currentGameIndex++;
      }
    }
  }

  List<Widget> _buildItems(
    List<GamesAppBarModel> reversedRounds,
    Map<String, List<GamesTourModel>> gamesByRound,
    GamesScreenModel gamesData,
    bool isChessBoardVisible,
  ) {
    final items = <Widget>[];
    for (final round in reversedRounds) {
      items.add(
        RoundHeader(round: round, roundGames: gamesByRound[round.id] ?? []),
      );
      final roundGames = gamesByRound[round.id] ?? [];
      for (int i = 0; i < roundGames.length; i++) {
        final game = roundGames[i];
        final globalGameIndex = gamesData.gamesTourModels.indexWhere(
          (g) => g.gameId == game.gameId,
        );
        items.add(
          Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: GameCardWrapperWidget(
              game: game,
              gamesData: gamesData,
              gameIndex: globalGameIndex,
              isChessBoardVisible: isChessBoardVisible,
              onReturnFromChessboard: (returnedIndex) {
                _scrollToGameIndex(returnedIndex);
                onReturnFromChessboard?.call(returnedIndex);
              },
            ),
          ),
        );
      }
    }
    return items;
  }
}
