import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/services/toby/toby_prediction.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

TobyWdl score(double white) => TobyWdl(white: white, draw: 0, black: 1 - white);

void main() {
  final request = TobyRequest(moves: ['e2e4']);
  final position = Chess.initial.play(Move.parse('e2e4')!);
  final candidates = [
    TobyCandidate(uci: 'a7a6', san: 'a6', probability: .6, wdl: score(.65)),
    TobyCandidate(uci: 'e7e5', san: 'e5', probability: .3, wdl: score(.40)),
    const TobyCandidate(uci: 'c7c5', san: 'c5', probability: .1),
  ];

  Map<String, GameMoveClassification> grade({
    bool finalStage = true,
    bool withPosition = true,
    bool hiddenBetterMove = false,
    Side sideToMove = Side.black,
  }) => gradeTobyMoves(
    request: request,
    position: position,
    visibleUcis: candidates.map((candidate) => candidate.uci),
    reading: TobyReading(
      isFinal: finalStage,
      sideToMove: sideToMove,
      candidates: candidates,
      otherProbability: 0,
      otherMoveCount: 0,
      positionWdl: withPosition ? score(.40) : null,
      allOutcomes: [
        for (final candidate in candidates)
          if (candidate.wdl case final wdl?) (uci: candidate.uci, wdl: wdl),
        if (hiddenBetterMove) (uci: 'd7d5', wdl: score(.15)),
      ],
    ),
  );

  test('Black uses its own score, not White score or likelihood rank', () {
    expect(grade(), {
      'a7a6': GameMoveClassification.blunder,
      'e7e5': GameMoveClassification.bestMove,
    });
  });

  test('an evaluated move outside the displayed rows still affects praise', () {
    expect(grade(hiddenBetterMove: true), {
      'a7a6': GameMoveClassification.blunder,
    });
  });

  test('no grades without final odds from the current side', () {
    expect(grade(finalStage: false), isEmpty);
    expect(grade(withPosition: false), isEmpty);
    expect(grade(sideToMove: Side.white), isEmpty);
  });
}
