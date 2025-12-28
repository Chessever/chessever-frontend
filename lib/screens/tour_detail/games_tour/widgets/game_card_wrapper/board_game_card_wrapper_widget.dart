import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Wrapper widget for board mode chess boards that subscribes to live updates.
/// Similar to GridGameCardWrapperWidget but for the larger board view.
class BoardGameCardWrapperWidget extends ConsumerWidget {
  final GamesTourModel game;
  /// Callback that receives the live-updated games list for navigation.
  /// The list will have the current game replaced with the live-updated version.
  final void Function(List<GamesTourModel> updatedGames) onChangedWithLiveGames;
  final List<GamesTourModel> orderedGames;
  final int gameIndex;
  final List<String> pinnedIds;
  final void Function(GamesTourModel game) onPinToggle;

  const BoardGameCardWrapperWidget({
    super.key,
    required this.game,
    required this.onChangedWithLiveGames,
    required this.orderedGames,
    required this.gameIndex,
    required this.pinnedIds,
    required this.onPinToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch live game updates for ongoing games
    // Use gameId as the stable key to prevent provider recreation
    final liveGame = ref.watch(
      liveGameCardProvider((gameId: game.gameId, baseGame: game)),
    );

    // Build updated games list with the live game data
    List<GamesTourModel> getUpdatedGamesList() {
      final games = List<GamesTourModel>.from(orderedGames);
      if (gameIndex >= 0 && gameIndex < games.length) {
        games[gameIndex] = liveGame;
      }
      return games;
    }

    return ChessBoardFromFENNew(
      key: ValueKey('board_game_${liveGame.gameId}'),
      gamesTourModel: liveGame,
      onChanged: () => onChangedWithLiveGames(getUpdatedGamesList()),
      pinnedIds: pinnedIds,
      onPinToggle: onPinToggle,
    );
  }
}
