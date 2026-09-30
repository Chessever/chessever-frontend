import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:dartchess/dartchess.dart';

final RegExp _ecoCode = RegExp(r'^[A-E]\d{2}$');
final RegExp _sanNoise = RegExp(r'[+#!?]+$');

/// A playable ECO code on [game] ("C65"), or null for a missing code, the
/// `?` / Chess960 sentinels and anything else the catalogue cannot name.
String? feedEcoCode(GamesTourModel game) {
  final code = game.eco?.trim().toUpperCase() ?? '';
  return _ecoCode.hasMatch(code) ? code : null;
}

/// The position the post header's opening stands for, set up for the board
/// editor. Null when the opening cannot be placed: no playable ECO code, or a
/// game that did not start from the standard position.
///
/// Which line of the code: the catalogue record named like the game's own
/// opening, else the deepest record the game actually played through, else
/// the code's canonical line. When the game played the record's moves the
/// game's own position after them is used (its clocks and counters are the
/// real ones); otherwise the record's line is replayed from the start.
String? feedOpeningFen(GamesTourModel game, List<FeedPly> plies) {
  final code = feedEcoCode(game);
  if (code == null) return null;
  if (plies.isNotEmpty && !_isStandardStart(plies.first.fen)) return null;
  final records = EcoOpenings.recordsByCode[code] ?? const [];

  final played = [
    for (var i = 1; i < plies.length; i++)
      (plies[i].san ?? '').replaceAll(_sanNoise, ''),
  ];

  EcoOpeningRecord? pick;
  final name = game.openingName?.trim().toLowerCase() ?? '';
  if (name.isNotEmpty) {
    for (final record in records) {
      if (record.name.trim().toLowerCase() == name) {
        pick = record;
        break;
      }
    }
  }

  // The deepest record whose line the game walked through, move for move.
  EcoOpeningRecord? walked;
  var walkedDepth = 0;
  for (final record in records) {
    final tokens = _tokens(record);
    if (tokens.isEmpty || tokens.length > played.length) continue;
    if (!EcoOpenings.isMovePrefix(tokens, played)) continue;
    if (tokens.length > walkedDepth) {
      walked = record;
      walkedDepth = tokens.length;
    }
  }

  pick ??= walked ?? EcoOpenings.canonicalRecordForCode(code);
  if (pick == null) return null;
  final tokens = _tokens(pick);
  if (tokens.isEmpty) return null;
  if (tokens.length < plies.length &&
      EcoOpenings.isMovePrefix(tokens, played)) {
    return plies[tokens.length].fen;
  }
  return spaceFenAfter(tokens);
}

List<String> _tokens(EcoOpeningRecord record) => [
  for (final token in EcoOpenings.moveTokens(record.moves))
    token.replaceAll(_sanNoise, ''),
];

bool _isStandardStart(String fen) =>
    fen.trim().split(RegExp(r'\s+')).first == Chess.initial.board.fen;
