import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/feed/logic/feed_exploration.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:dartchess/dartchess.dart';

/// A read-only board handoff captured synchronously when Analyze is tapped.
/// Keep a move pointer, not a FEN search, so repeated positions open on the
/// exact move. The full game and any explored continuation remain navigable.
SavedAnalysisData feedAnalysisSnapshot({
  required FeedItem item,
  required int shownPly,
  FeedExploration? exploration,
}) {
  final source = item.game;
  final pgn = source.pgn;
  final game = pgn != null && pgn.trim().isNotEmpty
      ? ChessGame.fromPgn(source.gameId, pgn)
      : ChessGame(
          gameId: source.gameId,
          startingFen: item.plies.first.fen,
          metadata: {
            'White': source.whitePlayer.name,
            'Black': source.blackPlayer.name,
            'Result': item.result ?? '*',
            if (item.eventLabel != null) 'Event': item.eventLabel,
          },
          mainline: [
            for (var i = 1; i < item.plies.length; i++)
              ChessMove(
                num: Setup.parseFen(item.plies[i - 1].fen).fullmoves,
                fen: item.plies[i].fen,
                san: item.plies[i].san!,
                uci: item.plies[i].uci!,
                turn: Setup.parseFen(item.plies[i].fen).turn == Side.white
                    ? ChessColor.white
                    : ChessColor.black,
              ),
          ],
        );
  final ply = (exploration?.forkPly ?? shownPly).clamp(0, game.mainline.length);
  var pointer = ply == 0 ? <int>[] : [ply - 1];
  var snapshot = ChessGameNavigatorState(game: game, movePointer: pointer);
  final navigator = ChessGameNavigator(game);
  navigator.addListener((state) => snapshot = state);
  try {
    navigator.goToMovePointerUnchecked(pointer);
    if (exploration != null) {
      for (var i = 0; i < exploration.moves.length; i++) {
        navigator.makeOrGoToMove(exploration.moves[i].move.uci);
        if (i == exploration.cursor) pointer = List.of(snapshot.movePointer);
      }
    }
    return SavedAnalysisData(
      sourceGameId: source.likeId,
      chessGame: snapshot.game,
      variationComments: const {},
      movePointer: pointer,
      isBoardFlipped: false,
      lastViewedPosition: ply - 1,
    );
  } finally {
    navigator.dispose();
  }
}
