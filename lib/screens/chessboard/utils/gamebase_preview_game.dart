import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

/// Round-id markers stamped on archive rows that arrive without `fen` or
/// `lastMove` and with a header-only PGN.
///
/// Cards for these rows cannot derive a position from the model alone, so the
/// board/eval-bar path fetches the game from Gamebase and replays its moves to
/// the final position.
const Set<String> kGamebasePreviewRoundMarkers = <String>{
  'gamebase_search',
  'twic_profile',
  'twic_event',
  // `/api/miniatures` returns metadata only — no moves, no FEN. Without this
  // marker the miniature card keeps the start position, so its evaluation bar
  // rates the starting position instead of the finish.
  kGamebaseMiniaturesRoundId,
};

/// Whether [game] needs a Gamebase fetch before its final position is known.
bool isGamebasePreviewGame(GamesTourModel game) {
  return kGamebasePreviewRoundMarkers.contains(
    game.roundId.trim().toLowerCase(),
  );
}
