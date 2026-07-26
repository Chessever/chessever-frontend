import 'dart:convert';
import 'dart:io';

import 'package:chessever2/screens/chessboard/game_review/lichess_judgment.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replays real lichess analyses through our port and demands the same symbols.
///
/// The fixture is what lichess itself published for five analysed games —
/// per-ply evaluation, whether it kept an engine line, and the judgment it
/// awarded — captured from `lichess.org/game/export/{id}?evals=true`. So this is
/// not a test of what we think the rules are; it is a test against lichess's own
/// output, move by move, including a game that ends in mate and one that spends
/// twenty-eight plies inside mate scores.
///
/// A single mismatch means the port has drifted from
/// `lila/modules/tree/src/main/Advice.scala`. Re-read the Scala; do not adjust a
/// threshold to make this pass.
///
/// One thing here is lichess's and not ours: the first move is measured against a
/// fixed +0.15, because that is the baseline fishnet leaves lila
/// (`Info.start` / `evals.initial`). Game Review has a real evaluation of the
/// starting position and uses it — see `lichessJudgementForReportMove`. This test
/// replays lichess's pipeline, so it uses lichess's baseline.
void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/lichess_published_judgments.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final games = (fixture['games'] as List).cast<Map<String, dynamic>>();

  test('the fixture is the one that was captured', () {
    expect(games, hasLength(5));
    expect(
      games.fold<int>(0, (sum, game) => sum + (game['plies'] as List).length),
      452,
      reason: 'a truncated fixture would let a drifted port pass quietly',
    );
  });

  group('every judgment lichess published', () {
    for (final game in games) {
      final id = game['id'] as String;
      final plies = (game['plies'] as List).cast<List<dynamic>>();

      test('$id (${game['status']}, ${plies.length} plies)', () {
        for (var i = 0; i < plies.length; i++) {
          final expected = plies[i][3] as String?;
          final actual = _judge(plies, i)?.glyph;
          expect(
            actual,
            expected,
            reason:
                'https://lichess.org/$id ply ${i + 1}: '
                'lichess said ${expected ?? 'nothing'}, we said '
                '${actual ?? 'nothing'} '
                '(${_describe(plies, i)})',
          );
        }
      });
    }
  });

  test('the whole set is judged, not quietly skipped', () {
    var ours = 0;
    var theirs = 0;
    for (final game in games) {
      final plies = (game['plies'] as List).cast<List<dynamic>>();
      for (var i = 0; i < plies.length; i++) {
        if (plies[i][3] != null) theirs++;
        if (_judge(plies, i) != null) ours++;
      }
    }
    expect(theirs, fixture['totalJudgments']);
    expect(ours, theirs);
  });
}

/// `[eval, mate, hasVariation, judgmentGlyph]`, White-relative.
EngineScore? _scoreAt(List<List<dynamic>> plies, int index) =>
    EngineScore.fromLine(
      centipawns: plies[index][0] as int?,
      mate: plies[index][1] as int?,
    );

LichessJudgement? _judge(List<List<dynamic>> plies, int index) {
  final hasVariation = (plies[index][2] as int) == 1;
  return lichessAdvice(
    // lila's own starting baseline; see the note above.
    previous:
        index == 0 ? const CpScore(15) : _scoreAt(plies, index - 1),
    current: _scoreAt(plies, index),
    // Ply 1 is White's, so an even index means White moved.
    moverIsWhite: index.isEven,
    // hasVariation is exactly "the engine wanted something else".
    engineBestUci: hasVariation ? 'd2d4' : 'e2e4',
    playedUci: 'e2e4',
  );
}

String _describe(List<List<dynamic>> plies, int index) {
  String show(int i) =>
      plies[i][1] != null ? 'mate ${plies[i][1]}' : 'cp ${plies[i][0]}';
  final from = index == 0 ? 'cp 15' : show(index - 1);
  return '$from -> ${show(index)}, hasVariation ${plies[index][2] == 1}';
}
