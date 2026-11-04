/// Provenance for a ChessEver Game Analysis report carried inside a PGN.
///
/// ## The problem
///
/// A report travels in the moves: each analysed move gets its ChessEver class
/// as a `$240`–`$247` NAG and its score as `[%eval …]`. But none of that proves
/// *we* produced it. A user can mark a move Book from the NAG palette, a PGN
/// can arrive with another engine's `[%eval]` on every move, and a copied game
/// loses the in-app `$248` marker that records a user's verdict. Read naively,
/// any of those comes back as "ChessEver analysed this game", with an accuracy
/// we never computed. Our analysis and what a user added afterwards must never
/// be confused.
///
/// ## The stamp
///
/// The report writer, and only the report writer, adds one header tag:
///
///     [ChessEverReport "v1 <sha256 hex>"]
///
/// The digest covers exactly what the report wrote, in mainline order: the
/// position each move reaches, the move's ChessEver code (or none), and its
/// `[%eval]` text (or none), plus the starting position. So the stamp verifies
/// only while the report is untouched:
///
/// - a user verdict changes a move's code (and the overlay drops the stamp
///   outright, see [withoutChesseverReportStamp]);
/// - a foreign or edited score changes an `[%eval]`;
/// - a changed, added or removed move changes the positions;
/// - a stamp pasted onto another game describes other positions.
///
/// Comments, clocks, variations and non-verdict NAGs (`±`, `N`, …) are not
/// covered: they are not part of the report, and annotating around a report
/// does not make it any less ours.
///
/// It is an integrity check, not a signature. Anyone can compute it, so it does
/// not stop someone who deliberately forges one; it guarantees that nothing a
/// user adds or edits in the ordinary course is ever read back as our verdict.
///
/// Positions are identified by the first three FEN fields (placement, side to
/// move, castling rights) rather than by UCI or SAN: castling is written `e1h1`
/// by one library and `e1g1` by another, SAN tokens are stored as the source
/// wrote them, and en-passant/clock fields differ between FEN writers. Placement,
/// side and castling rights are identical however the move was entered or
/// parsed, and two different moves from one position never reach the same one.
///
/// Ported from the desktop app (`chessever_frontend_desktop`), whose copy is
/// vendored into the analysis service. The payload is byte-identical across
/// all three; `test/report_provenance_stamp_test.dart` pins a shared vector.
/// Changing the payload is a format change for every client and the server.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';

/// The header tag carrying the stamp.
const String kChesseverReportStampTag = 'ChessEverReport';

/// The only stamp version this build writes or accepts.
const String kChesseverReportStampVersion = 'v1';

/// The canonical text the stamp digests. Exposed for the cross-app parity
/// regression; nothing should parse it.
String chesseverReportStampPayload(ChessGame game) {
  final buffer =
      StringBuffer()
        ..write('chessever-report-stamp ')
        ..write(kChesseverReportStampVersion)
        ..write('\n')
        ..write(_positionKey(game.startingFen))
        ..write('\n');
  for (final move in game.mainline) {
    buffer
      ..write(_positionKey(move.fen))
      ..write('\t')
      ..write(_firstClassificationCode(move.nags)?.toString() ?? '-')
      ..write('\t')
      ..write(_evalText(move.eval) ?? '-')
      ..write('\n');
  }
  return buffer.toString();
}

/// The stamp value for [game] exactly as it stands.
String chesseverReportStampFor(ChessGame game) =>
    '$kChesseverReportStampVersion '
    '${sha256.convert(utf8.encode(chesseverReportStampPayload(game)))}';

/// Desktop's private marker for a verdict the user set. Mobile never writes it,
/// but a PGN arriving from desktop may carry it.
const int kChesseverUserQualityOverrideNag = 248;

/// Whether any mainline move carries a verdict the user set
/// ([kChesseverUserQualityOverrideNag]).
bool hasChesseverUserVerdict(ChessGame game) => game.mainline.any(
  (move) => move.nags?.contains(kChesseverUserQualityOverrideNag) ?? false,
);

/// Whether [game] carries a ChessEver report exactly as our analysis wrote it.
///
/// True only when the stamp is present, matches the game as it stands now, and
/// no move carries a user verdict. Anything else — no stamp, a stale stamp, a
/// user's mark — means the verdicts in this PGN are not (only) ours.
bool carriesVerifiedChesseverReport(ChessGame game) {
  if (game.mainline.isEmpty) return false;
  final stamp = game.metadata[kChesseverReportStampTag]?.toString().trim();
  if (stamp == null || stamp.isEmpty) return false;
  if (hasChesseverUserVerdict(game)) return false;
  return stamp == chesseverReportStampFor(game);
}

/// [game] with a stamp describing it as it stands, for the report writer.
///
/// Call only on a game whose every mainline verdict and score was just written
/// by a report. A game carrying a user verdict is returned without a stamp:
/// part of it is the user's, so no part of it may vouch for itself as ours.
ChessGame withChesseverReportStamp(ChessGame game) {
  if (game.mainline.isEmpty || hasChesseverUserVerdict(game)) {
    return withoutChesseverReportStamp(game);
  }
  return game.copyWith(
    metadata: <String, dynamic>{
      ...game.metadata,
      kChesseverReportStampTag: chesseverReportStampFor(game),
    },
  );
}

/// [game] without a stamp. Used wherever a verdict stops being only ours.
ChessGame withoutChesseverReportStamp(ChessGame game) {
  if (!game.metadata.containsKey(kChesseverReportStampTag)) return game;
  return game.copyWith(
    metadata: <String, dynamic>{
      for (final entry in game.metadata.entries)
        if (entry.key != kChesseverReportStampTag) entry.key: entry.value,
    },
  );
}

String _positionKey(String fen) =>
    fen.trim().split(RegExp(r'\s+')).take(3).join(' ');

int? _firstClassificationCode(List<int>? nags) {
  if (nags == null) return null;
  for (final nag in nags) {
    if (nag >= 240 && nag <= 247) return nag;
  }
  return null;
}

String? _evalText(String? eval) {
  final text = eval?.trim();
  return text == null || text.isEmpty ? null : text;
}
