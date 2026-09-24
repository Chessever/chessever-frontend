import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/notation/notation_pointer.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The classified-move sound and landing animation announce exactly what the
/// board badges on the displayed move. Both resolve through
/// [resolveBoardMoveBadge], the same function that draws the badge, so these
/// pin the move class each badge source produces.
void main() {
  ChessGame game(String movetext) => ChessGame.fromPgn('fx', '''
[Event "Classification FX"]
[Result "*"]

$movetext *
''');

  MoveClass? classAt(
    ChessGame analysisGame,
    List<int> pointer, {
    Map<String, List<int>> userMoveNags = const {},
    Map<int, LichessMoveAnnotation> lichess = const {},
    bool showReport = true,
    bool showSource = true,
    bool showLocal = true,
    bool preview = false,
  }) {
    return resolveBoardMoveBadge(
      analysisGame: analysisGame,
      movePointer: pointer,
      isPvPreviewActive: preview,
      userMoveNags: userMoveNags,
      showReportAnnotations: showReport,
      showSourceAnnotations: showSource,
      showLocalAnnotations: showLocal,
      lichessAnnotationsFor: (_) => lichess,
      reviewStateFor: () => null,
    ).moveClass;
  }

  group('moveClassForBoardBadge', () {
    test('every report badge maps back through its verdict', () {
      for (final verdict in GameMoveClassification.values) {
        expect(
          moveClassForBoardBadge(
            annotationType: annotationTypeForClassification(verdict),
          ),
          moveClassFromClassification(verdict),
          reason: '$verdict',
        );
      }
    });

    test('forced has no class; of the glyph badges only !? does', () {
      expect(
        moveClassForBoardBadge(
          annotationType: LichessMoveAnnotationType.forced,
        ),
        isNull,
      );
      expect(moveClassForBoardBadge(glyphNag: 5), MoveClass.interesting);
      expect(moveClassForBoardBadge(glyphNag: 7), isNull);
      expect(moveClassForBoardBadge(glyphNag: 16), isNull);
      expect(moveClassForBoardBadge(), isNull);
    });
  });

  group('resolveBoardMoveBadge move class', () {
    test('PGN move glyphs, including !? and ?!', () {
      final g = game('1. e4!? e5?! 2. Nf3?? Nc6! 3. Bc4!! Bc5? 4. c3');
      expect(classAt(g, const [0]), MoveClass.interesting);
      expect(classAt(g, const [1]), MoveClass.inaccuracy);
      expect(classAt(g, const [2]), MoveClass.blunder);
      expect(classAt(g, const [3]), MoveClass.great);
      expect(classAt(g, const [4]), MoveClass.brilliant);
      expect(classAt(g, const [5]), MoveClass.mistake);
      expect(
        classAt(g, const [6]),
        isNull,
        reason: 'an unannotated move keeps its ordinary sound',
      );
    });

    test('a PGN-carried ChessEver verdict is announced like a report', () {
      final g = game(r'1. e4 $247 e5 2. Qh5 $243 Nc6 3. Bc4 $242');
      expect(classAt(g, const [0]), MoveClass.book);
      expect(classAt(g, const [2]), MoveClass.missedWin);
      expect(classAt(g, const [4]), MoveClass.best);
      expect(
        classAt(g, const [0], showReport: false),
        isNull,
        reason: 'with the report hidden the board shows no verdict badge',
      );
    });

    test('the reader\'s own glyph overrides the PGN verdict', () {
      final g = game(r'1. e4 $240 e5');
      expect(classAt(g, const [0]), MoveClass.brilliant);
      expect(
        classAt(
          g,
          const [0],
          userMoveNags: {
            NotationPointer.encode(const [0]): const [2],
          },
        ),
        MoveClass.mistake,
      );
    });

    test('Lichess analysis counts only while source symbols are shown', () {
      final g = game('1. e4 e5 2. Qh5 Ke7');
      const lichess = {
        3: LichessMoveAnnotation(
          type: LichessMoveAnnotationType.blunder,
          comment: '',
        ),
      };
      expect(classAt(g, const [3], lichess: lichess), MoveClass.blunder);
      expect(
        classAt(g, const [3], lichess: lichess, showSource: false),
        isNull,
      );
    });

    test('a classified variation move is announced', () {
      // A variation hangs off the move it branches from: 0-0-0 is the first
      // move of the first variation after mainline move 0.
      final g = game('1. e4 e5 (1... c5?? 2. Nf3) 2. Nf3');
      expect(classAt(g, const [0, 0, 0]), MoveClass.blunder);
      expect(classAt(g, const [0, 0, 1]), isNull);
    });

    test('nothing is announced when the board shows no badge', () {
      final g = game('1. e4?? e5');
      expect(
        classAt(g, const [0], preview: true),
        isNull,
        reason: 'a PV preview never inherits the base move\'s badge',
      );
      expect(
        classAt(g, const [0], showReport: false, showLocal: false),
        isNull,
        reason: 'raw PGN mode draws no badge, so it plays no class sound',
      );
      expect(classAt(g, const []), isNull, reason: 'the starting position');
    });
  });
}
