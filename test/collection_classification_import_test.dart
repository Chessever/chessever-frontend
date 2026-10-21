import 'dart:io';

import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_report_from_pgn.dart';
import 'package:chessever2/screens/chessboard/notation/notation_token_builder.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collection PGN restores Oparin-Shankland report badges', () {
    final pgn = File(
      'test/fixtures/oparin_shankland_2026_collection.pgn',
    ).readAsStringSync();
    final collectionGame = collectionGameModel('oparin-shankland', pgn);
    final game = ChessGame.fromPgn(collectionGame.gameId, collectionGame.pgn!);
    expect(game.mainline, hasLength(155));

    final annotations = pgnClassificationAnnotations(game);
    for (final index in [80, 96, 110]) {
      expect(
        annotations[index]?.type,
        LichessMoveAnnotationType.missedWin,
        reason: 'the broken heart on ${game.mainline[index].san}',
      );
    }
    for (final index in [26, 49, 71, 81, 101]) {
      expect(
        annotations[index]?.type,
        LichessMoveAnnotationType.inaccuracy,
        reason: 'the report inaccuracy on ${game.mainline[index].san}',
      );
    }
    expect(annotations[139]?.type, LichessMoveAnnotationType.blunder);
    expect(annotations[0]?.type, LichessMoveAnnotationType.bookMove);
    expect(game.mainline[80].nags, contains(243));
    expect(game.mainline[71].nags, containsAll([6, 244]));
    expect(game.mainline[80].eval, '0.88');
    expect(game.mainline[80].clockTime, '00:28:37');
    expect(game.mainline[26].variations, isNotEmpty);

    expect(
      resolveBoardMoveBadge(
        analysisGame: game,
        movePointer: const [80],
        isPvPreviewActive: false,
        userMoveNags: const {},
        showReportAnnotations: true,
        showSourceAnnotations: true,
        showLocalAnnotations: true,
        lichessAnnotationsFor: (_) => const {},
        reviewStateFor: () => null,
      ).moveClass,
      MoveClass.missedWin,
    );
    for (final index in [71, 80]) {
      final annotation = resolveNotationClassification(
        rawPgnMode: false,
        isMainline: true,
        moveIndex: index,
        annotations: annotations,
        nags: mergeMoveNags(
          pgnNags: game.mainline[index].nags,
          userNags: const [],
        ),
      );
      expect(annotation, annotations[index]);
      expect(annotation!.useClassificationIcon, isTrue);
    }

    final report = gameAnalysisReportFromPgn(game);
    expect(report, isNotNull);
    expect(report!.moves[80].classification, GameMoveClassification.missedWin);
  });

  test(
    'a classification carried only in the header reaches badge resolution',
    () {
      final game = ChessGame.fromPgn('minimal', '''
[ChessEverClassification "1=243 2=244"]

1. e4 e5 *
''');
      expect(
        pgnClassificationAnnotations(game)[0]?.type,
        LichessMoveAnnotationType.missedWin,
      );
      expect(
        pgnClassificationAnnotations(game)[1]?.type,
        LichessMoveAnnotationType.inaccuracy,
      );
    },
  );

  test('all eight header classes become the existing native badge codes', () {
    for (final entry in kChesseverClassificationNags.entries) {
      final game = ChessGame.fromPgn('classes', '''
[ChessEverClassification "1=${entry.value}"]

1. e4 *
''');
      expect(classificationFromNags(game.mainline.single.nags), entry.key);
      expect(game.metadata, isNot(contains('ChessEverClassification')));
      final exported = exportGameToPgn(game);
      expect(exported, isNot(contains('ChessEverClassification')));
      final reopened = ChessGame.fromPgn('reopened', exported);
      expect(classificationFromNags(reopened.mainline.single.nags), entry.key);
    }
  });

  test('native annotations take priority and are never duplicated', () {
    final game = ChessGame.fromPgn('native', r'''
[ChessEverClassification "1=243 2=247"]

1. e4 $6 $244 e5 $247 *
''');
    expect(game.mainline[0].nags, [6, 244]);
    expect(game.mainline[1].nags, [247]);
  });

  test('malformed, duplicate and unknown entries do not shift valid plies', () {
    final game = ChessGame.fromPgn('tolerant', '''
[chesseverclassification "bad 0=243 1=999 1=243 1=244,2=244 3=wat 99=247 v1=240 2v0.0=240"]

1. e4 e5 2. Nf3 *
''');
    expect(game.mainline[0].nags, [243]);
    expect(game.mainline[1].nags, [244]);
    expect(game.mainline[2].nags, isNull);
    expect(game.metadata.keys, isNot(contains('chesseverclassification')));
  });

  test('FEN starts use the move sequence rather than the fullmove number', () {
    final game = ChessGame.fromPgn('black-start', '''
[SetUp "1"]
[FEN "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 12"]
[ChessEverClassification "1=247 2=244"]

12... e5 13. Nf3 *
''');
    expect(game.mainline.map((move) => move.san), ['e5', 'Nf3']);
    expect(game.mainline[0].nags, [247]);
    expect(game.mainline[1].nags, [244]);
  });

  test('nested and sibling variations keep their header addresses', () {
    final game = ChessGame.fromPgn('variations', '''
[ChessEverClassification "2=247 2v1.1=243 2v1.2=244 2v1.2v1.1=240 2v2.1=245 3=242"]

1. e4 e5 (1... c5 2. Nf3 (2. Nc3) d6) (1... e6 2. d4) 2. Nf3 *
''');
    expect(game.mainline[1].nags, [247]);
    expect(game.mainline[2].nags, [242]);
    final variations = game.mainline[0].variations!;
    expect(variations[0][0].nags, [243]);
    expect(variations[0][1].nags, [244]);
    expect(variations[0][0].variations![0][0].nags, [240]);
    expect(variations[1][0].nags, [245]);
    expect(variations[1][1].nags, isNull);
  });

  test(
    'saved copies from before header support are restored on JSON import',
    () {
      final old = ChessGame.fromPgn(
        'saved',
        '1. e4 e5 *',
      ).copyWith(metadata: {'ChessEverClassification': '1=243 2=244'});
      final reopened = ChessGame.fromJson(old.toJson());
      expect(reopened.mainline[0].nags, [243]);
      expect(reopened.mainline[1].nags, [244]);
      expect(reopened.metadata, isNot(contains('ChessEverClassification')));
    },
  );

  test('cleared analysis stays clear after JSON and PGN round trips', () {
    final game = ChessGame.fromPgn('clear', '''
[ChessEverClassification "1=243"]

1. e4 *
''');
    final cleared = game.withoutAnalysis();
    final reopened = ChessGame.fromJson(cleared.toJson());
    expect(chesseverClassificationsFromMainline(reopened), isEmpty);
    expect(reopened.analysisBackup!.game.mainline.single.nags, [243]);
    expect(
      chesseverClassificationsFromMainline(
        ChessGame.fromPgn('cleared-pgn', exportGameToPgn(reopened)),
      ),
      isEmpty,
    );

    final old = cleared.copyWith(
      metadata: {'ChessEverClassification': '1=243'},
    );
    expect(ChessGame.fromJson(old.toJson()).mainline.single.nags, isNull);
  });
}
