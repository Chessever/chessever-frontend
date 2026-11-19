import 'dart:async';

import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:flutter_test/flutter_test.dart';

// SYNTHETIC policy scores on the actual legal Rc7/Qh3 board, never claimed
// to be official analysis or new engine measurements. Both colors are tested.
String mirrorFen(String fen) {
  final f = fen.split(' ');
  f[0] = f[0]
      .split('/')
      .reversed
      .map(
        (r) => r
            .split('')
            .map(
              (c) => c == c.toUpperCase() ? c.toLowerCase() : c.toUpperCase(),
            )
            .join(),
      )
      .join('/');
  f[1] = f[1] == 'w' ? 'b' : 'w';
  return f.join(' ');
}

String mirrorUci(String u) => u
    .split('')
    .map((c) => int.tryParse(c) == null ? c : '${9 - int.parse(c)}')
    .join();

({ChessGame game, List<GameReportPosition> positions}) controlled(bool mirror) {
  const start = '5rk1/8/bp2pn1p/p2pNppq/3P1P2/1P3N2/P2Q1PKP/2R5 w - - 0 31';
  final fen = mirror ? mirrorFen(start) : start;
  final game = ChessGame.fromPgn(
    'native-critical',
    '[SetUp "1"]\n[FEN "$fen"]\n\n'
        '${mirror ? '31... Rc2 32. Qh6+' : '31. Rc7 Qh3+'} *',
  );
  final sign = mirror ? -1 : 1;
  GameReportLine l(String pv, int cp) => GameReportLine(
    moves: pv.split(' ').map((u) => mirror ? mirrorUci(u) : u).toList(),
    depth: 18,
    centipawns: cp * sign,
  );
  final fens = gameReportFens(game);
  final positions = [
    GameReportPosition(
      fen: fens[0],
      search: const GameReportSearchEvidence(
        engineId: 'synthetic-native',
        searchId: 'pre',
        complete: true,
      ),
      lines: [l('d2e3', 0), l('f3g1', 0), l('c1c7', -800)],
    ),
    GameReportPosition(
      fen: fens[1],
      search: const GameReportSearchEvidence(
        engineId: 'synthetic-native',
        searchId: 'root',
        complete: true,
      ),
      lines: [l('h5h3 g2h1 h3f1 f3g1 f6e4', -800), l('f6e4', 0), l('g5g4', 27)],
    ),
    GameReportPosition(
      fen: fens[2],
      search: const GameReportSearchEvidence(
        engineId: 'synthetic-native',
        searchId: 'after',
        complete: true,
      ),
      lines: [l('g2h1 h3f1 f3g1 f6e4', -800)],
    ),
  ];
  return (game: game, positions: positions);
}

GameReportPosition changed(
  GameReportPosition p, {
  int? cp,
  int? depth,
  String? fen,
  bool? complete,
  bool noSearch = false,
  List<GameReportLine>? lines,
}) => GameReportPosition(
  fen: fen ?? p.fen,
  search: noSearch
      ? null
      : GameReportSearchEvidence(
          engineId: p.search!.engineId,
          searchId: p.search!.searchId,
          complete: complete ?? p.search!.complete,
        ),
  lines:
      lines ??
      [
        for (final l in p.lines)
          GameReportLine(
            moves: l.moves,
            depth: depth ?? l.depth,
            centipawns: cp ?? l.centipawns,
            mate: l.mate,
          ),
      ],
);

void main() {
  for (final mirror in [false, true]) {
    test(
      'native three-position critical punishment qualifies, mirror=$mirror',
      () {
        final c = controlled(mirror);
        expect(c.game.mainline.length, 2);
        for (final p in c.positions) {
          expect(
            gameReportSnapshotIsCoherent(p, minDepth: 18, requireNative: true),
            true,
          );
        }
        expect(
          nativeCriticalPunishmentReason(
            index: 1,
            game: c.game,
            positions: c.positions,
            previous: GameMoveClassification.blunder,
          ),
          'verified_native_critical_punishment',
        );
        final report = buildGameAnalysisReport(
          game: c.game,
          fingerprint: 'synthetic',
          positions: c.positions,
        );
        expect(report.moves[0].classification, GameMoveClassification.blunder);
        expect(
          report.moves[1].classification,
          GameMoveClassification.brilliant,
        );
        expect(
          report.count(GameMoveClassification.brilliant, white: mirror),
          1,
        );
      },
    );
    for (final problem in [
      'already_winning',
      'low_pre_depth',
      'missing_native',
      'wrong_pre_fen',
      'unsound',
      'lost_defense',
      'multiple_winning',
      'incomplete',
      'mixed_depths',
      'illegal_pv',
      'short_pv',
      'no_previous_blunder',
    ]) {
      test('native rejects $problem, mirror=$mirror', () {
        final c = controlled(mirror);
        final p = [...c.positions];
        final sign = mirror ? -1 : 1;
        if (problem == 'already_winning') p[0] = changed(p[0], cp: -800 * sign);
        if (problem == 'low_pre_depth') p[0] = changed(p[0], depth: 15);
        if (problem == 'missing_native') p[0] = changed(p[0], noSearch: true);
        if (problem == 'wrong_pre_fen') p[0] = changed(p[0], fen: p[1].fen);
        if (problem == 'unsound') p[2] = changed(p[2], cp: -300 * sign);
        if (problem == 'lost_defense') {
          p[1] = changed(p[1], cp: 600 * sign);
          p[2] = changed(p[2], cp: 600 * sign);
        }
        if (problem == 'incomplete') p[1] = changed(p[1], complete: false);
        if ([
          'multiple_winning',
          'mixed_depths',
          'illegal_pv',
          'short_pv',
        ].contains(problem)) {
          p[1] = changed(
            p[1],
            lines: [
              for (var i = 0; i < p[1].lines.length; i++)
                GameReportLine(
                  moves: problem == 'illegal_pv' && i == 0
                      ? [p[1].lines[i].moves.first, 'a1a8']
                      : problem == 'short_pv' && i == 0
                      ? p[1].lines[i].moves.take(2).toList()
                      : p[1].lines[i].moves,
                  depth: problem == 'mixed_depths' && i == 1 ? 16 : 18,
                  centipawns: problem == 'multiple_winning' && i == 1
                      ? -500 * sign
                      : p[1].lines[i].centipawns,
                ),
            ],
          );
        }
        final reason = nativeCriticalPunishmentReason(
          index: 1,
          game: c.game,
          positions: p,
          previous: problem == 'no_previous_blunder'
              ? null
              : GameMoveClassification.blunder,
        );
        expect(reason, isNot('verified_native_critical_punishment'));
        final report = buildGameAnalysisReport(
          game: c.game,
          fingerprint: 'synthetic',
          positions: p,
        );
        final verdict = problem == 'no_previous_blunder'
            ? classifyGameReportMove(
                index: 1,
                game: c.game,
                positions: p,
                winPercentages: p
                    .map((p) => gameReportWinPercentage(p.bestLine))
                    .toList(),
              )
            : report.moves[1].classification;
        expect(verdict, isNot(GameMoveClassification.brilliant));
      });
    }
    for (final problem in ['depth', 'provenance', 'winning_alternative']) {
      test(
        'winning-boundary reply cannot bypass native $problem, mirror=$mirror',
        () async {
          final c = controlled(mirror);
          final sign = mirror ? -1 : 1;
          final p = [...c.positions];
          p[0] = changed(
            p[0],
            depth: problem == 'depth' ? 14 : 18,
            noSearch: problem == 'provenance',
          );
          p[1] = changed(
            p[1],
            lines: [
              for (var n = 0; n < p[1].lines.length; n++)
                GameReportLine(
                  moves: p[1].lines[n].moves,
                  depth: 18,
                  centipawns: n == 0
                      ? -595 * sign
                      : problem == 'winning_alternative' && n == 1
                      ? -500 * sign
                      : p[1].lines[n].centipawns,
                ),
            ],
          );
          p[2] = changed(p[2], cp: -600 * sign);
          expect(
            buildGameAnalysisReport(
              game: c.game,
              fingerprint: 'boundary',
              positions: p,
            ).moves[1].classification,
            isNot(GameMoveClassification.brilliant),
          );
          if (problem != 'winning_alternative') {
            var calls = 0;
            final fixed = await confirmGameReportConsistency(
              game: c.game,
              positions: p,
              isCancelled: () => false,
              evaluate: (request) async {
                calls++;
                return c.positions.firstWhere(
                  (position) => position.fen == request.fen,
                );
              },
            );
            expect(calls, greaterThan(0));
            expect(
              buildGameAnalysisReport(
                game: c.game,
                fingerprint: 'confirmed-boundary',
                positions: fixed,
              ).moves[1].classification,
              isNot(GameMoveClassification.brilliant),
            );
          }
        },
      );
    }
    test(
      'already-won conversion cannot fall through ordinary Brilliant, mirror=$mirror',
      () {
        final c = controlled(mirror);
        final sign = mirror ? -1 : 1;
        final p = [...c.positions];
        p[0] = changed(p[0], cp: -400 * sign);
        p[1] = changed(
          p[1],
          lines: [
            for (var i = 0; i < p[1].lines.length; i++)
              GameReportLine(
                moves: p[1].lines[i].moves,
                depth: 18,
                centipawns: i == 0 ? -650 * sign : p[1].lines[i].centipawns,
              ),
          ],
        );
        p[2] = changed(p[2], cp: -650 * sign);
        expect(
          buildGameAnalysisReport(
            game: c.game,
            fingerprint: 'synthetic',
            positions: p,
          ).moves[1].classification,
          isNot(GameMoveClassification.brilliant),
        );
      },
    );
    test('native forced recapture retains semantic veto, mirror=$mirror', () {
      const start = '7k/8/8/8/8/bq6/8/R6K w - - 0 31';
      final game = ChessGame.fromPgn(
        'recapture',
        '[SetUp "1"]\n[FEN "${mirror ? mirrorFen(start) : start}"]\n\n'
            '${mirror ? '31... Rxa6 32. Qxa6' : '31. Rxa3 Qxa3'} *',
      );
      final fens = gameReportFens(game);
      final sign = mirror ? -1 : 1;
      GameReportLine l(String u, int cp) => GameReportLine(
        moves: [mirror ? mirrorUci(u) : u],
        depth: 18,
        centipawns: cp * sign,
      );
      final p = [
        for (var i = 0; i < fens.length; i++)
          GameReportPosition(
            fen: fens[i],
            search: GameReportSearchEvidence(
              engineId: 'synthetic',
              searchId: '$i',
              complete: true,
            ),
            lines: i == 0
                ? [l('h1g1', 0)]
                : i == 1
                ? [l('b3a3', -800), l('b3b4', 0)]
                : [l('h1g1', -800)],
          ),
      ];
      expect(
        nativeCriticalPunishmentReason(
          index: 1,
          game: game,
          positions: p,
          previous: GameMoveClassification.blunder,
        ),
        'routine_or_forced',
      );
      expect(
        buildGameAnalysisReport(
          game: game,
          fingerprint: 'synthetic',
          positions: p,
        ).moves[1].classification,
        isNot(GameMoveClassification.brilliant),
      );
    });
    test(
      'low-depth balanced prehistory is confirmed rather than trusted, mirror=$mirror',
      () async {
        final c = controlled(mirror);
        final positions = [...c.positions]
          ..[0] = changed(c.positions[0], depth: 15);
        final calls = <String>[];
        final result = await confirmGameReportConsistency(
          game: c.game,
          positions: positions,
          isCancelled: () => false,
          evaluate: (r) async {
            calls.add(r.fen);
            return c.positions.firstWhere((p) => p.fen == r.fen);
          },
        );
        expect(calls, contains(c.positions[0].fen));
        expect(
          nativeCriticalPunishmentReason(
            index: 1,
            game: c.game,
            positions: result,
            previous: GameMoveClassification.blunder,
          ),
          'verified_native_critical_punishment',
        );
      },
    );
  }
  test(
    'cancellation while search is stalled stops promptly and drops late result',
    () async {
      final c = controlled(false);
      final p = [...c.positions]..[0] = changed(c.positions[0], depth: 15);
      final started = Completer<void>();
      final pending = Completer<GameReportPosition>();
      var cancel = false, stopped = false;
      final run = confirmGameReportConsistency(
        game: c.game,
        positions: p,
        isCancelled: () => cancel,
        cancelSearch: () async {
          stopped = true;
        },
        evaluate: (r) {
          started.complete();
          return pending.future;
        },
      );
      await started.future;
      cancel = true;
      final result = await run.timeout(const Duration(milliseconds: 500));
      expect(stopped, true);
      pending.complete(c.positions[1]);
      expect(result[0].bestLine.depth, 15);
    },
  );
}
