import 'dart:io';

import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_report_from_pgn.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/utils/chessever_report_stamp.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real broadcast game as the analysis service's prewarm left it before
/// reports were stamped: every ply scored, ChessEver classes as `$240`–`$247`,
/// nothing proving who wrote them.
ChessGame _unstampedPrewarm() => ChessGame.fromPgn(
  'chess.com:188037485477',
  File(
    'test/fixtures/prewarmed_report_nakamura_bok_2026.pgn',
  ).readAsStringSync(),
);

ChessGame _bare(ChessGame game) => game.copyWith(
  mainline: <ChessMove>[
    for (final move in game.mainline)
      ChessMove(
        num: move.num,
        fen: move.fen,
        san: move.san,
        uci: move.uci,
        turn: move.turn,
        clockTime: move.clockTime,
      ),
  ],
);

GameAnalysisReport _reportOf(ChessGame source) =>
    gameAnalysisReportFromPgn(withChesseverReportStamp(source))!;

/// The game exactly as the report writer now produces it, after a round trip
/// through PGN text.
ChessGame _writtenByOurReport() {
  final source = _unstampedPrewarm();
  final pgn = exportGameToPgn(
    mergeGameReportAnnotationsForExport(_bare(source), _reportOf(source)),
  );
  return ChessGame.fromPgn(source.gameId, pgn);
}

ChessGame _withMove(ChessGame game, int index, ChessMove move) => game.copyWith(
  mainline: <ChessMove>[
    for (var i = 0; i < game.mainline.length; i++)
      i == index ? move : game.mainline[i],
  ],
);

void main() {
  test('a report our writer produced is restored exactly', () {
    final game = _writtenByOurReport();
    expect(carriesVerifiedChesseverReport(game), isTrue);
    final report = gameAnalysisReportFromPgn(game)!;
    expect(report.moves, hasLength(99));
    int count(GameMoveClassification c) =>
        report.moves.where((move) => move.classification == c).length;
    expect(count(GameMoveClassification.bookMove), 14);
    expect(count(GameMoveClassification.goodMove), 6);
    expect(count(GameMoveClassification.bestMove), 2);
    expect(count(GameMoveClassification.inaccuracy), 6);
    expect(count(GameMoveClassification.mistake), 3);
    expect(report.moves[20].classification, GameMoveClassification.inaccuracy);
    expect(report.moves[20].evaluation.centipawns, -50);
  });

  test('an unstamped PGN is never read as our report', () {
    expect(gameAnalysisReportFromPgn(_unstampedPrewarm()), isNull);
  });

  test('a reader verdict baked into the PGN is the reader\'s', () {
    final ours = _writtenByOurReport();
    // The reader marks 8. h3 as `!`: mobile bakes the matching ChessEver code
    // in beside it, indistinguishable from a report's in the moves.
    final edited = mergeUserMoveNagsForExport(ours, {
      '14': const [1],
    });
    expect(edited.metadata.containsKey(kChesseverReportStampTag), isFalse);
    expect(gameAnalysisReportFromPgn(edited), isNull);
    expect(
      gameAnalysisReportFromPgn(
        ChessGame.fromPgn('reopened', exportGameToPgn(edited)),
      ),
      isNull,
    );
  });

  test('the full export with reader verdicts is not stamped', () {
    final source = _unstampedPrewarm();
    final game = hydrateGameAnnotationsForExport(
      _bare(source),
      report: _reportOf(source),
      userMoveNags: const {
        '14': [247],
      },
    );
    expect(game.metadata.containsKey(kChesseverReportStampTag), isFalse);
  });

  test('a desktop user-verdict marker is never ours', () {
    final ours = _writtenByOurReport();
    final move = ours.mainline[14];
    final marked = _withMove(
      ours,
      14,
      move.copyWith(nags: [...?move.nags, 1, kChesseverUserQualityOverrideNag]),
    );
    expect(gameAnalysisReportFromPgn(marked), isNull);
  });

  test('an edited class, score or move breaks the stamp', () {
    final ours = _writtenByOurReport();
    final h3 = ours.mainline[14];
    expect(
      gameAnalysisReportFromPgn(
        _withMove(ours, 14, h3.copyWith(nags: const [247])),
      ),
      isNull,
    );
    expect(
      gameAnalysisReportFromPgn(_withMove(ours, 14, h3.copyWith(eval: '1.50'))),
      isNull,
    );
    expect(
      gameAnalysisReportFromPgn(
        ours.copyWith(
          mainline: ours.mainline.sublist(0, ours.mainline.length - 1),
        ),
      ),
      isNull,
    );
  });

  test('annotating around the report keeps it ours', () {
    final ours = _writtenByOurReport();
    final h3 = ours.mainline[14];
    final annotated = ChessGame.fromPgn(
      'annotated',
      exportGameToPgn(
        _withMove(
          ours,
          14,
          h3.copyWith(
            nags: [...?h3.nags, 14],
            comments: [...?h3.comments, 'Prophylaxis.'],
          ),
        ),
      ),
    );
    expect(gameAnalysisReportFromPgn(annotated), isNotNull);
  });

  test('a stamp pasted onto another game proves nothing', () {
    final stamp = _writtenByOurReport().metadata[kChesseverReportStampTag];
    final other = ChessGame.fromPgn(
      'other',
      '[Result "1-0"]\n[$kChesseverReportStampTag "$stamp"]\n\n'
          '1. e4 \$247 { [%eval 0.30] } 1... e5 \$247 { [%eval 0.25] } 1-0',
    );
    expect(gameAnalysisReportFromPgn(other), isNull);
  });

  test('the writer only stamps a report that covered every move', () {
    final source = _unstampedPrewarm();
    final full = _reportOf(source);
    final partial = GameAnalysisReport(
      fingerprint: full.fingerprint,
      positions: full.positions,
      moves: full.moves.sublist(0, full.moves.length - 1),
      whiteAccuracy: full.whiteAccuracy,
      blackAccuracy: full.blackAccuracy,
      generatedAt: full.generatedAt,
    );
    expect(
      mergeGameReportAnnotationsForExport(
        _bare(source),
        partial,
      ).metadata.containsKey(kChesseverReportStampTag),
      isFalse,
    );
  });

  test('the stamp payload is the cross-app contract', () {
    // Pinned identically in the desktop app and the analysis service.
    final game = ChessGame.fromPgn(
      'vector',
      '[Result "*"]\n\n'
          '1. e4 \$247 { [%eval 0.30] } 1... e5 \$247 { [%eval 0.25] } '
          '2. Nf3 { [%eval 0.20] } 2... Nc6 \$6 \$244 { [%eval #-3] } *',
    );
    expect(
      chesseverReportStampPayload(game),
      'chessever-report-stamp v1\n'
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq\n'
      'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq\t247\t0.30\n'
      'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq\t247\t0.25\n'
      'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq\t-\t0.20\n'
      'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq\t244\t#-3\n',
    );
    expect(
      chesseverReportStampFor(game),
      'v1 e5f1e86020d08b05e01b6799e167800947e9b28c2337bbf53c197e99b7260c91',
    );
  });
}
