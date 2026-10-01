import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart'
    show classificationFromNags, legacyClassificationFromComments;
import 'package:dartchess/dartchess.dart';

/// Eligibility shared by Discovery Reports and Feed, including old reports.
/// An eval and a report verdict must belong to the same played move. Ordinary
/// glyphs, variations, quoted markers and multi-game files do not qualify.
bool hasSavedGameReport(Object? pgn) {
  // Match the Reports page's indexed candidate predicates before parsing.
  if (pgn is! String ||
      !pgn.contains('[%eval ') ||
      !(pgn.contains(r'$24') ||
          pgn.toLowerCase().contains('chessever_annotation'))) {
    return false;
  }
  final parsed = PgnGame.parseMultiGamePgn(pgn);
  if (parsed.length != 1) return false;
  return parsed.single.moves.mainline().any((move) {
    final classification =
        classificationFromNags(move.nags) ??
        legacyClassificationFromComments(move.comments);
    return classification != null &&
        (move.comments?.any(
              (comment) => PgnComment.fromPgn(comment).eval != null,
            ) ??
            false);
  });
}
