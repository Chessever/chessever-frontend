import 'package:dartchess/dartchess.dart';

/// A replayed continuation line: SAN labels plus the FEN after each ply.
///
/// Built from the `continuation` UCI slice the gamebase API attaches to
/// position-games rows when `notationPlies` is requested (Trello #984).
class ContinuationLine {
  const ContinuationLine({required this.sans, required this.fens});

  /// SAN for each successfully replayed continuation ply.
  final List<String> sans;

  /// `fens[0]` is the anchor position; `fens[i]` is the position after
  /// applying `sans[0..i-1]`. Always `sans.length + 1` entries.
  final List<String> fens;

  bool get isEmpty => sans.isEmpty;
  bool get isNotEmpty => sans.isNotEmpty;
}

/// Replays [ucis] from [anchorFen], converting each ply to SAN and collecting
/// the FEN after every move. Stops at the first move that fails to parse or is
/// illegal, returning the prefix replayed so far. Mirrors the tolerant
/// behavior of `uciToSanAndFen` in `move_statistics_panel.dart`.
ContinuationLine buildContinuationLine(String anchorFen, List<String> ucis) {
  Position position;
  try {
    position = Chess.fromSetup(Setup.parseFen(anchorFen));
  } catch (_) {
    return ContinuationLine(sans: const [], fens: [anchorFen]);
  }

  final sans = <String>[];
  final fens = <String>[anchorFen];
  for (final uci in ucis) {
    final trimmed = uci.trim().toLowerCase();
    if (trimmed.length < 4) break;
    try {
      final from = Square.fromName(trimmed.substring(0, 2));
      final to = Square.fromName(trimmed.substring(2, 4));
      Role? promotion;
      if (trimmed.length > 4) {
        promotion = Role.fromChar(trimmed[4]);
      }
      final move = NormalMove(from: from, to: to, promotion: promotion);
      final (next, san) = position.makeSan(move);
      position = next;
      sans.add(san);
      fens.add(position.fen);
    } catch (_) {
      break;
    }
  }
  return ContinuationLine(sans: sans, fens: fens);
}

/// Label for continuation chip [index]: white plies get a `N.` prefix; a
/// leading black ply gets `N…` so the strip reads like real notation.
String continuationChipLabel(String anchorFen, int index, String san) {
  final parts = anchorFen.trim().split(RegExp(r'\s+'));
  final whiteToMove = parts.length > 1 ? parts[1] == 'w' : true;
  final baseMoveNumber =
      parts.length > 5 ? (int.tryParse(parts[5]) ?? 1) : 1;
  final isWhitePly = whiteToMove ? index.isEven : index.isOdd;
  final moveNumber = baseMoveNumber + ((whiteToMove ? index : index + 1) ~/ 2);
  if (isWhitePly) return '$moveNumber. $san';
  if (index == 0) return '$moveNumber… $san';
  return san;
}
