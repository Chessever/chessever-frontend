import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Wrapper widget for grid mode chess boards that subscribes to live updates.
/// Similar to GameCardWrapperWidget but for the grid view.
class GridGameCardWrapperWidget extends ConsumerWidget {
  final GamesTourModel game;
  final VoidCallback onChanged;
  final List<String> pinnedIds;
  final void Function(GamesTourModel game) onPinToggle;

  const GridGameCardWrapperWidget({
    super.key,
    required this.game,
    required this.onChanged,
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

    return GridChessBoardFromFENNew(
      key: ValueKey('grid_game_${liveGame.gameId}'),
      gamesTourModel: liveGame,
      onChanged: onChanged,
      pinnedIds: pinnedIds,
      onPinToggle: onPinToggle,
    );
  }
}
