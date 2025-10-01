import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GameCardWrapperWidget extends ConsumerWidget {
  final GamesTourModel game;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final bool isChessBoardVisible;
  final void Function(int)? onReturnFromChessboard;

  const GameCardWrapperWidget({
    super.key,
    required this.game,
    required this.gamesData,
    required this.gameIndex,
    required this.isChessBoardVisible,
    this.onReturnFromChessboard,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keyValue = 'game_${game.gameId}';

    return isChessBoardVisible
        ? ChessBoardFromFENNew(
          key: ValueKey(keyValue),
          gamesTourModel: game,
          onChanged:
              () => ref
                  .read(gameCardWrapperProvider)
                  .navigateToChessBoard(
                    context: context,
                    orderedGames: gamesData.gamesTourModels,
                    gameIndex: gameIndex,
                    onReturnFromChessboard: onReturnFromChessboard,
                  ),
          pinnedIds: gamesData.pinnedGamedIs,
          onPinToggle:
              (_) async => await ref
                  .read(gamesTourScreenProvider.notifier)
                  .togglePinGame(game.gameId),
        )
        : GameCard(
          key: ValueKey(keyValue),
          gamesTourModel: game,
          pinnedIds: gamesData.pinnedGamedIs,
          onPinToggle:
              (_) async => await ref
                  .read(gamesTourScreenProvider.notifier)
                  .togglePinGame(game.gameId),
          onTap:
              () =>
                  () => ref
                      .read(gameCardWrapperProvider)
                      .navigateToChessBoard(
                        context: context,
                        orderedGames: gamesData.gamesTourModels,
                        gameIndex: gameIndex,
                        onReturnFromChessboard: onReturnFromChessboard,
                      ),
        );
  }
}
