import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Wrapper widget for grid mode chess boards that subscribes to live updates.
/// Similar to GameCardWrapperWidget but for the grid view.
class GridGameCardWrapperWidget extends ConsumerWidget {
  final GamesTourModel game;

  /// Callback that receives the live-updated games list for navigation.
  /// The list will have the current game replaced with the live-updated version.
  final void Function(List<GamesTourModel> updatedGames) onChangedWithLiveGames;
  final List<GamesTourModel> orderedGames;
  final int gameIndex;
  final List<String> pinnedIds;
  final void Function(GamesTourModel game) onPinToggle;
  final Side? fixedBottomSide;
  final bool allowStockfishFallback;
  final bool streamEnabled;
  final LiveGamesBatchKey? liveBatchKey;

  const GridGameCardWrapperWidget({
    super.key,
    required this.game,
    required this.onChangedWithLiveGames,
    required this.orderedGames,
    required this.gameIndex,
    required this.pinnedIds,
    required this.onPinToggle,
    this.fixedBottomSide,
    this.allowStockfishFallback = true,
    this.streamEnabled = true,
    this.liveBatchKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch live game updates for ongoing games
    // Use gameId as the stable key to prevent provider recreation
    final liveGame = watchLiveGamePosition(
      ref,
      game,
      batchKey: liveBatchKey,
      streamEnabled: streamEnabled,
    );
    final effectiveAllowStockfishFallback =
        streamEnabled &&
        allowStockfishFallback &&
        ref.watch(shouldStreamProvider);

    // Build updated games list with the live game data
    List<GamesTourModel> getUpdatedGamesList() {
      final games = List<GamesTourModel>.from(orderedGames);
      if (gameIndex >= 0 && gameIndex < games.length) {
        games[gameIndex] = liveGame;
      }
      return games;
    }

    return GridChessBoardFromFENNew(
      key: ValueKey('grid_game_${liveGame.gameId}'),
      gamesTourModel: liveGame,
      onChanged: () => onChangedWithLiveGames(getUpdatedGamesList()),
      pinnedIds: pinnedIds,
      onPinToggle: onPinToggle,
      fixedBottomSide: fixedBottomSide,
      allowStockfishFallback: effectiveAllowStockfishFallback,
      liveBatchKey: liveBatchKey,
    );
  }
}
