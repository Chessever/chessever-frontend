import 'dart:convert';
import 'dart:io';

import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/server_game_report.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// The wire contract with the `chessever-analysis` Worker.
///
/// `test/fixtures/server_game_report.json` is a real response captured from the
/// service, not a hand-written approximation — a fixture someone wrote from the
/// docs would keep passing after the server changed shape, which is the one
/// failure this test exists to catch.
void main() {
  late Map<String, dynamic> payload;
  late ChessGame game;

  const pgn = '1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0';

  setUp(() {
    payload =
        jsonDecode(
              File('test/fixtures/server_game_report.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    game = ChessGame.fromPgn('test', pgn);
  });

  test('a real server response rebuilds into a report', () {
    final report = gameAnalysisReportFromServerJson(payload, game: game);

    expect(report.fingerprint, gameReportFingerprint(game));
    expect(report.moves, hasLength(game.mainline.length));
    // One evaluation per position, starting position included.
    expect(report.positions, hasLength(game.mainline.length + 1));
    expect(report.whiteAccuracy, closeTo(88.27, 0.01));
    expect(report.blackAccuracy, closeTo(21.81, 0.01));
    expect(report.whiteEstimatedRating, 1920);
    expect(report.blackEstimatedRating, 362);
  });

  test('classifications survive the round trip by name', () {
    final report = gameAnalysisReportFromServerJson(payload, game: game);
    final byPly = {for (final move in report.moves) move.ply: move};

    // The opening is theory, Qh5 is punished, and Nf6 walks into mate.
    expect(byPly[1]!.classification, GameMoveClassification.bookMove);
    expect(byPly[4]!.classification, GameMoveClassification.bookMove);
    expect(byPly[5]!.classification, GameMoveClassification.inaccuracy);
    expect(byPly[6]!.classification, GameMoveClassification.blunder);
    // Null is a real value: the mating move itself earns no named category.
    expect(byPly[7]!.classification, isNull);
  });

  test('mate scores and centipawns are kept apart', () {
    final report = gameAnalysisReportFromServerJson(payload, game: game);
    final byPly = {for (final move in report.moves) move.ply: move};

    expect(byPly[1]!.evaluation.centipawns, 32);
    expect(byPly[1]!.evaluation.mate, isNull);
    expect(byPly[1]!.evaluation.depth, 14);

    // A forced mate has no centipawn value, and reading one as the other would
    // put a mate on the evaluation graph as a ~0.01 pawn edge.
    expect(byPly[6]!.evaluation.mate, 1);
    expect(byPly[6]!.evaluation.centipawns, isNull);
  });

  test('a report for a different game is refused, not adapted', () {
    // Everything downstream — badges, graph, PGN export — is keyed on the
    // fingerprint, so accepting a mismatch would paint one game's verdicts onto
    // another rather than fail.
    final otherGame = ChessGame.fromPgn('other', '1. d4 d5 2. c4 e6 *');

    expect(
      () => gameAnalysisReportFromServerJson(payload, game: otherGame),
      throwsA(isA<ServerGameReportException>()),
    );
  });

  test('a truncated report is refused', () {
    final short = Map<String, dynamic>.from(payload);
    short['moves'] = (payload['moves'] as List).sublist(0, 3);

    expect(
      () => gameAnalysisReportFromServerJson(short, game: game),
      throwsA(isA<ServerGameReportException>()),
    );
  });

  test('the response carries the report back in the PGN', () {
    // How a report already travels between ChessEver clients: the ChessEver
    // `$240`-`$247` NAG beside the standard glyph.
    final returnedPgn = payload['pgn'] as String;
    expect(returnedPgn, contains(r'$247')); // book
    expect(returnedPgn, contains(r'$246')); // blunder
  });
}
