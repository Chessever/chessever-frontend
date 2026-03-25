import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GameCardWrapperWidget extends ConsumerWidget {
  final GamesTourModel game;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final bool isChessBoardVisible;
  final Future<void> Function(GamesTourModel game)? onPinToggle;
  final void Function(int)? onReturnFromChessboard;
  final ChessboardView viewSource;

  const GameCardWrapperWidget({
    super.key,
    required this.game,
    required this.gamesData,
    required this.gameIndex,
    required this.isChessBoardVisible,
    this.onPinToggle,
    this.onReturnFromChessboard,
    this.viewSource = ChessboardView.tour,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch live game updates for ongoing games
    // Use gameId as the stable key to prevent provider recreation
    final liveGame = watchLiveGame(ref, game);
    final keyValue = 'game_${liveGame.gameId}';

    // Build updated games list with the live game data for navigation
    List<GamesTourModel> getUpdatedGamesList() {
      final games = List<GamesTourModel>.from(gamesData.gamesTourModels);
      if (gameIndex >= 0 && gameIndex < games.length) {
        games[gameIndex] = liveGame;
      }
      return games;
    }

    Future<void> handlePinToggle(GamesTourModel game) async {
      if (onPinToggle != null) {
        await onPinToggle!(game);
        return;
      }

      await ref
          .read(gamesTourScreenProvider.notifier)
          .togglePinGame(game.gameId, sourceTourId: game.tourId);
    }

    return isChessBoardVisible
        ? ChessBoardFromFENNew(
          key: ValueKey(keyValue),
          gamesTourModel: liveGame,
          onChanged:
              () => ref
                  .read(gameCardWrapperProvider)
                  .navigateToChessBoard(
                    context: context,
                    orderedGames: getUpdatedGamesList(),
                    gameIndex: gameIndex,
                    onReturnFromChessboard: onReturnFromChessboard,
                    viewSource: viewSource,
                  ),
          pinnedIds: gamesData.pinnedGamedIs,
          onPinToggle: handlePinToggle,
        )
        : GameCard(
          key: ValueKey(keyValue),
          matchComparison: MatchWithComparison(
            game: liveGame,
            comparison: MatchComparison.sameOrder,
          ),
          pinnedIds: gamesData.pinnedGamedIs,
          onPinToggle: handlePinToggle,
          onTap:
              () => ref
                  .read(gameCardWrapperProvider)
                  .navigateToChessBoard(
                    context: context,
                    orderedGames: getUpdatedGamesList(),
                    gameIndex: gameIndex,
                    onReturnFromChessboard: onReturnFromChessboard,
                    viewSource: viewSource,
                  ),
        );
  }
}
