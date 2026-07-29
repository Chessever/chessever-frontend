import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/screens/chessboard/game_review/evaluation_graph_markers.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:flutter_test/flutter_test.dart';

GameReportLine _line({int? cp, int? mate}) => GameReportLine(
  moves: const ['e7e5'],
  depth: 12,
  centipawns: cp,
  mate: mate,
);

GameReportPosition _position({int? cp, int? mate}) =>
    GameReportPosition(fen: '8/8/8/8/8/8/8/8 w - - 0 1', lines: [_line(cp: cp, mate: mate)]);

GameReportMove _move({
  required int ply,
  required bool isWhite,
  GameMoveClassification? classification,
  int? cp,
}) => GameReportMove(
  ply: ply,
  san: isWhite ? 'e4' : 'e5',
  uci: isWhite ? 'e2e4' : 'e7e5',
  isWhite: isWhite,
  classification: classification,
  evaluation: _line(cp: cp ?? 0),
);

void main() {
  group('buildEvaluationGraphClassificationMarkers', () {
    test('returns one marker per non-null classification in ply order', () {
      final positions = [
        _position(cp: 0), // start
        _position(cp: 20), // after e4
        _position(cp: 15), // after e5
        _position(cp: 40), // after Nf3
        _position(cp: -120), // after blunder
        _position(cp: 250), // after punish
      ];
      final moves = [
        _move(
          ply: 1,
          isWhite: true,
          classification: GameMoveClassification.bookMove,
          cp: 20,
        ),
        _move(
          ply: 2,
          isWhite: false,
          classification: null, // unclassified — no marker
          cp: 15,
        ),
        _move(
          ply: 3,
          isWhite: true,
          classification: GameMoveClassification.bestMove,
          cp: 40,
        ),
        _move(
          ply: 4,
          isWhite: false,
          classification: GameMoveClassification.blunder,
          cp: -120,
        ),
        _move(
          ply: 5,
          isWhite: true,
          classification: GameMoveClassification.brilliant,
          cp: 250,
        ),
      ];

      final markers = buildEvaluationGraphClassificationMarkers(
        moves: moves,
        positions: positions,
      );

      // Book moves are classified on the report but never dotted on the graph.
      expect(markers, hasLength(3));
      expect(
        markers.map((m) => m.classification).toList(),
        [
          GameMoveClassification.bestMove,
          GameMoveClassification.blunder,
          GameMoveClassification.brilliant,
        ],
      );
      expect(markers.map((m) => m.ply).toList(), [3, 4, 5]);
    });

    test('omits book-move classifications from graph markers', () {
      final positions = [
        _position(cp: 0),
        _position(cp: 20),
        _position(cp: 15),
        _position(cp: 40),
      ];
      final moves = [
        _move(
          ply: 1,
          isWhite: true,
          classification: GameMoveClassification.bookMove,
        ),
        _move(
          ply: 2,
          isWhite: false,
          classification: GameMoveClassification.bookMove,
        ),
        _move(
          ply: 3,
          isWhite: true,
          classification: GameMoveClassification.bestMove,
        ),
      ];

      final markers = buildEvaluationGraphClassificationMarkers(
        moves: moves,
        positions: positions,
      );

      expect(markers, hasLength(1));
      expect(markers.single.classification, GameMoveClassification.bestMove);
      expect(markers.single.ply, 3);
      expect(
        markers.any((m) => m.classification == GameMoveClassification.bookMove),
        isFalse,
      );
    });

    test('colors resolve through shared classificationColor palette', () {
      // bookMove is intentionally omitted from graph markers (see above).
      final classifications = [
        GameMoveClassification.inaccuracy,
        GameMoveClassification.mistake,
        GameMoveClassification.blunder,
        GameMoveClassification.bestMove,
        GameMoveClassification.brilliant,
        GameMoveClassification.goodMove,
        GameMoveClassification.missedWin,
      ];
      final positions = [
        _position(cp: 0),
        for (var i = 0; i < classifications.length; i++)
          _position(cp: 10 * (i + 1)),
      ];
      final moves = [
        for (var i = 0; i < classifications.length; i++)
          _move(
            ply: i + 1,
            isWhite: i.isEven,
            classification: classifications[i],
            cp: 10 * (i + 1),
          ),
      ];

      final markers = buildEvaluationGraphClassificationMarkers(
        moves: moves,
        positions: positions,
      );

      expect(markers, hasLength(classifications.length));
      for (var i = 0; i < classifications.length; i++) {
        expect(
          markers[i].color,
          classificationColor(classifications[i]),
          reason: '${classifications[i].name} must use shared palette',
        );
        expect(markers[i].classification, classifications[i]);
      }
    });

    test('win% and ply match shared graph scale (position after the move)', () {
      final positions = [
        _position(cp: 0),
        _position(cp: 100),
        _position(cp: -200),
        _position(mate: 2),
      ];
      final moves = [
        _move(
          ply: 1,
          isWhite: true,
          classification: GameMoveClassification.inaccuracy,
          cp: 100,
        ),
        _move(
          ply: 2,
          isWhite: false,
          classification: GameMoveClassification.mistake,
          cp: -200,
        ),
        _move(
          ply: 3,
          isWhite: true,
          classification: GameMoveClassification.bestMove,
          cp: 999,
        ),
      ];

      final markers = buildEvaluationGraphClassificationMarkers(
        moves: moves,
        positions: positions,
      );

      expect(markers, hasLength(3));
      for (final marker in markers) {
        final expectedWin = gameReportWinPercentage(
          positions[marker.ply].bestLine,
        );
        expect(marker.winPercentage, expectedWin);
        // X-scale sample index is the after-move position, not the move index.
        expect(marker.ply, greaterThan(0));
        expect(marker.ply, lessThan(positions.length));
      }
      expect(markers[0].ply, 1);
      expect(markers[0].winPercentage, gameReportWinPercentage(positions[1].bestLine));
      expect(markers[1].ply, 2);
      expect(markers[1].winPercentage, gameReportWinPercentage(positions[2].bestLine));
      expect(markers[2].ply, 3);
      expect(markers[2].winPercentage, gameReportWinPercentage(positions[3].bestLine));
      expect(markers[2].winPercentage, 100); // mate in 2 for White
    });

    test('skips moves whose ply is out of range of positions', () {
      final positions = [
        _position(cp: 0),
        _position(cp: 20),
      ];
      final moves = [
        _move(
          ply: 1,
          isWhite: true,
          classification: GameMoveClassification.bestMove,
        ),
        _move(
          ply: 99, // no matching position sample
          isWhite: false,
          classification: GameMoveClassification.blunder,
        ),
      ];

      final markers = buildEvaluationGraphClassificationMarkers(
        moves: moves,
        positions: positions,
      );

      expect(markers, hasLength(1));
      expect(markers.single.classification, GameMoveClassification.bestMove);
      expect(markers.single.ply, 1);
    });

    test('empty inputs yield no markers', () {
      expect(
        buildEvaluationGraphClassificationMarkers(
          moves: const [],
          positions: [_position(cp: 0)],
        ),
        isEmpty,
      );
      expect(
        buildEvaluationGraphClassificationMarkers(
          moves: [
            _move(
              ply: 1,
              isWhite: true,
              classification: GameMoveClassification.bestMove,
            ),
          ],
          positions: const [],
        ),
        isEmpty,
      );
    });
  });
}
