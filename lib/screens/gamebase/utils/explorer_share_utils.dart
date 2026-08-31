import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:chessever2/screens/gamebase/utils/explorer_move_line.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

class ExplorerSharePayload {
  const ExplorerSharePayload({
    required this.pgn,
    required this.tourGame,
    required this.snapshot,
  });

  final String pgn;
  final GamesTourModel tourGame;
  final GameShareSnapshot snapshot;
}

/// Builds a local-only share payload for the exact Explorer cursor position.
///
/// The exported line stops at [movePointer], so GIF sharing cannot animate past
/// the position currently shown on the board. Opening Explorer positions have
/// no canonical cloud identity and therefore intentionally produce no link.
ExplorerSharePayload buildExplorerSharePayload({
  required ChessGame game,
  required ChessMovePointer movePointer,
  required String currentFen,
}) {
  final visibleLine = pathFromPointer(game, movePointer)
      .map((move) => move.copyWith(variations: null, overrideVariations: true))
      .toList(growable: false);
  final shareGame = game.copyWith(mainline: visibleLine);
  final pgn = exportGameToPgn(shareGame).trim();

  PlayerCard player(String color) => PlayerCard(
    name: game.metadata[color]?.toString() ?? color,
    federation: '',
    title: '',
    rating: 0,
    countryCode: '',
    team: null,
    fideId: null,
  );

  final tourGame = GamesTourModel(
    gameId: game.gameId,
    source: GameSource.openingExplorer,
    whitePlayer: player('White'),
    blackPlayer: player('Black'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.unknown,
    roundId: 'opening_explorer',
    tourId: 'opening_explorer',
    tourSlug: 'Opening Explorer',
    fen: currentFen,
    lastMove: visibleLine.isEmpty ? null : visibleLine.last.uci,
    pgn: pgn,
  );

  return ExplorerSharePayload(
    pgn: pgn,
    tourGame: tourGame,
    snapshot: buildGameShareSnapshot(game: tourGame, pgn: pgn),
  );
}
