import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/provider/analysis_view_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pgn = '''
[Event "Annotated game"]
[White "White player"]
[Black "Black player"]
[Result "1-0"]

{Starting comment} 1. e4!! {Text [%clk 0:10:00] [%eval 0.3]
[%cal Ge2e4] [%csl Re4] [%chessever_annotation brilliant]}
e5?? (1... c5!? {Sicilian} 2. Nf3 (2. Nc3 {Nested}))
2. Nf3 \$240 {More text} Nc6 \$14 1-0
''';

  test('clear strips all PGN analysis and preserves mainline and headers', () {
    final original = ChessGame.fromPgn('clear', pgn);
    expect(original.mainline.any((move) => move.variations != null), isTrue);
    final cleared = original.withoutAnalysis();
    expect(cleared.mainline.map((move) => move.san), [
      'e4',
      'e5',
      'Nf3',
      'Nc6',
    ]);
    expect(cleared.metadata, original.metadata);
    expect(cleared.startingFen, original.startingFen);
    expect(
      cleared.mainline.map((move) => move.fen),
      original.mainline.map((move) => move.fen),
    );
    for (final move in cleared.mainline) {
      expect(move.variations, isNull);
      expect(move.comments, isNull);
      expect(move.nags, isNull);
      expect(move.clockTime, isNull);
      expect(move.eval, isNull);
    }
    final exported = exportGameToPgn(cleared);
    expect(exported.split('\n\n').last.trim(), '1. e4 e5 2. Nf3 Nc6 1-0');
    expect(original.mainline.first.nags, isNotEmpty);
    expect(original.mainline.first.comments, isNotEmpty);
    expect(ChessGame.fromJson(cleared.toJson()).analysisCleared, isTrue);
    expect(cleared.withoutAnalysis().toJson(), cleared.toJson());
  });

  test(
    'clear preserves custom starting position, black move number and check',
    () {
      final original = ChessGame.fromPgn('custom', '''
[SetUp "1"]
[FEN "4k3/8/8/8/8/8/8/R3K3 b Q - 0 23"]
[Result "*"]

23... Kd7?! {Comment} 24. Ra7+! *
''');
      final cleared = original.withoutAnalysis();
      expect(cleared.mainline.map((move) => move.san), ['Kd7', 'Ra7+']);
      final roundTrip = ChessGame.fromPgn('custom', exportGameToPgn(cleared));
      expect(roundTrip.startingFen, original.startingFen);
      expect(roundTrip.mainline.first.num, 23);
      expect(roundTrip.mainline.first.turn, ChessColor.black);
      expect(roundTrip.mainline.last.fen, original.mainline.last.fen);
      expect(
        original.copyWith(mainline: []).withoutAnalysis().mainline,
        isEmpty,
      );
    },
  );

  test(
    'clear is one-shot; later moves keep annotations and restore backup',
    () {
      final original = ChessGame.fromPgn('live', pgn);
      final navigator = ChessGameNavigator(original.withoutAnalysis())
        ..goToTail();
      addTearDown(navigator.dispose);
      final updated = ChessGame.fromPgn(
        'live',
        pgn.replaceFirst(
          'Nc6 \$14 1-0',
          'Nc6 \$14 3. Bb5! {New annotation} 1-0',
        ),
      );
      navigator.updateWithLatestGame(updated, goToTail: true);
      expect(navigator.state.game.analysisCleared, isTrue);
      expect(navigator.state.movePointer, [4]);
      expect(navigator.state.game.mainline.first.nags, isNull);
      expect(navigator.state.game.mainline.last.nags, contains(1));
      expect(
        navigator.state.game.analysisBackup!.game.toJson(),
        original.toJson(),
      );
      final saved = ChessGame.fromJson(navigator.state.game.toJson());
      expect(saved.analysisBackup!.game.toJson(), original.toJson());
    },
  );

  test(
    'saved clear keeps cached reports hidden until explicitly requested',
    () {
      final controller = AnalysisViewSessionController();
      addTearDown(controller.dispose);
      final saved = ChessGame.fromJson(
        ChessGame.fromPgn('saved', pgn).withoutAnalysis().toJson(),
      );
      expect(
        controller.state.showReport(
          rawPgn: false,
          analysisCleared: saved.analysisCleared,
        ),
        isFalse,
      );
      expect(
        controller.state.showSourceAnnotations(
          rawPgn: false,
          analysisCleared: saved.analysisCleared,
        ),
        isFalse,
      );
      controller.requestReport();
      expect(
        controller.state.showReport(
          rawPgn: false,
          analysisCleared: saved.analysisCleared,
        ),
        isTrue,
      );
      controller.clear();
      expect(controller.state.showReport(rawPgn: false), isFalse);
    },
  );
}
