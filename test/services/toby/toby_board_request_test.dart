import 'dart:math' as math;

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/toby/toby_board_request.dart';
import 'package:chessever2/services/toby/toby_prediction.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerCard _player(String name, int rating) => PlayerCard(
  name: name,
  federation: '',
  title: '',
  rating: rating,
  countryCode: '',
  team: null,
);

GamesTourModel _game({int white = 0, int black = 0, String? speed}) =>
    GamesTourModel(
      gameId: 'toby-game',
      whitePlayer: _player('White', white),
      blackPlayer: _player('Black', black),
      whiteTimeDisplay: '',
      blackTimeDisplay: '',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.unknown,
      roundId: '',
      tourId: '',
      timeControl: speed,
    );

Position _after(List<String> ucis) {
  Position position = Chess.initial;
  for (final uci in ucis) {
    position = position.play(position.normalizeMove(NormalMove.fromUci(uci)));
  }
  return position;
}

const _pgn = '''
[Event "Tata Steel Masters"]
[Site "Wijk aan Zee"]
[White "A"]
[Black "B"]
[WhiteElo "2650"]
[BlackElo "2610"]
[TimeControl "5400+30"]
[Result "*"]

1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O *
''';

void main() {
  group('the board request', () {
    test('reads the analysis line, PGN ratings and tags', () {
      final chessGame = ChessGame.fromPgn('g', _pgn);
      final ucis = ['e2e4', 'e7e5', 'g1f3', 'b8c6'];
      final state = ChessBoardStateNew(
        game: _game(speed: 'standard'),
        isAnalysisMode: true,
        analysisState: AnalysisBoardState(
          game: chessGame,
          movePointer: const [3],
          position: _after(ucis),
        ),
      );
      final request = buildTobyRequestFromBoardState(state)!;
      expect(request.startFen, isNull);
      expect(request.moves, ucis);
      expect(request.whiteRating, 2650);
      expect(request.blackRating, 2610);
      expect(request.timeControl, '5400+30');
      expect(request.category, 'standard');
      expect(request.site, 'Wijk aan Zee');
      expect(request.event, 'Tata Steel Masters');
      expect(request.isSupported, isTrue);
    });

    test('castling goes out in Toby\'s king-step form', () {
      final chessGame = ChessGame.fromPgn('g', _pgn);
      final state = ChessBoardStateNew(
        game: _game(white: 2700, black: 2500),
        isAnalysisMode: true,
        analysisState: AnalysisBoardState(
          game: chessGame,
          movePointer: const [6],
          position: _after([
            'e2e4',
            'e7e5',
            'g1f3',
            'b8c6',
            'f1c4',
            'f8c5',
            'e1g1',
          ]),
        ),
      );
      final request = buildTobyRequestFromBoardState(state)!;
      expect(request.moves.last, 'e1g1');
      // The game's own ratings win over the PGN tags.
      expect(request.whiteRating, 2700);
      expect(request.blackRating, 2500);
    });

    test('falls back to the played mainline when there is no tree', () {
      final ucis = ['d2d4', 'g8f6'];
      final state = ChessBoardStateNew(
        game: _game(white: 1900),
        allMoves: [for (final uci in ucis) NormalMove.fromUci(uci)],
        currentMoveIndex: 1,
        position: _after(ucis),
      );
      final request = buildTobyRequestFromBoardState(state)!;
      expect(request.moves, ucis);
      expect(request.whiteRating, 1900);
      expect(request.blackRating, isNull);
    });

    test('threats mode, other variants and lines that miss the board are '
        'not read', () {
      final ucis = ['e2e4'];
      final base = ChessBoardStateNew(
        game: _game(),
        allMoves: [for (final uci in ucis) NormalMove.fromUci(uci)],
        currentMoveIndex: 0,
        position: _after(ucis),
      );
      expect(buildTobyRequestFromBoardState(base), isNotNull);
      expect(
        buildTobyRequestFromBoardState(base.copyWith(isThreatsMode: true)),
        isNull,
      );
      expect(
        buildTobyRequestFromBoardState(base, targetFen: _after(['d2d4']).fen),
        isNull,
      );
      final chess960 = ChessGame.fromPgn(
        'g',
        '[Variant "Chess960"]\n[Result "*"]\n\n1. e4 *\n',
      );
      expect(
        buildTobyRequestFromBoardState(
          base.copyWith(
            analysisState: base.analysisState.copyWith(game: chess960),
          ),
        ),
        isNull,
      );
    });

    test('replay normalises castling and rejects illegal lines', () {
      final start = Chess.initial.fen;
      final line = ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5', 'e1h1'];
      final target = _after(line).fen;
      expect(replayTobyLine(start, line, target)!.last, 'e1g1');
      expect(replayTobyLine(start, ['e2e5'], target), isNull);
      expect(replayTobyLine(start, ['e2e4'], target), isNull);
    });
  });

  group('readings as engine lines', () {
    test('the pseudo evaluation fills the bar to White\'s expected score', () {
      double fill(double pawns) => 1 / (1 + math.exp(-pawns / 3));
      for (final wdl in const [
        TobyWdl(white: 0.30, draw: 0.55, black: 0.15),
        TobyWdl(white: 0.05, draw: 0.20, black: 0.75),
        TobyWdl(white: 0.5, draw: 0, black: 0.5),
      ]) {
        expect(
          fill(tobyPseudoEvaluation(wdl)),
          closeTo(wdl.white + wdl.draw / 2, 1e-9),
        );
      }
      expect(
        tobyPseudoEvaluation(const TobyWdl(white: 1, draw: 0, black: 0)),
        9.9,
      );
      expect(
        tobyPseudoEvaluation(const TobyWdl(white: 0, draw: 0, black: 1)),
        -9.9,
      );
    });

    test('the badge shows a whole-number chance', () {
      expect(tobyEngineLineChance(0.344), '34%');
      expect(tobyEngineLineChance(0.345), '35%');
      expect(tobyEngineLineChance(0.004), '<1%');
      expect(tobyEngineLineChance(0), '0%');
      expect(tobyEngineLineChance(1), '100%');
    });

    test('lines take the configured count, move outcome first', () {
      final reading = TobyReading.fromJson({
        'stage': 'final',
        'sideToMove': 'white',
        'moves': [
          {
            'uci': 'e2e4',
            'san': 'e4',
            'probability': 0.45,
            'wdl': {'white': 0.31, 'draw': 0.46, 'black': 0.23},
          },
          {'uci': 'd2d4', 'san': 'd4', 'probability': 0.38, 'wdl': null},
          {'uci': 'g1f3', 'san': 'Nf3', 'probability': 0.0005},
        ],
        'positionWdl': {'white': 0.2, 'draw': 0.5, 'black': 0.3},
        'otherProbability': 0.1695,
        'otherMoveCount': 17,
      })!;
      final lines = tobyEngineLines(reading, 2);
      expect(lines.map((line) => line.uci), ['e2e4', 'd2d4']);
      expect(lines.map((line) => line.label), ['45%', '38%']);
      expect(lines[0].whiteCp, greaterThan(0));
      // No outcome of its own: the position's (White slightly worse).
      expect(lines[1].whiteCp, lessThan(0));
      expect(tobyEngineLines(reading, 5).last.label, '<1%');
    });

    test('a line\'s badge text joins its identity', () {
      final move = NormalMove.fromUci('e2e4');
      final plain = AnalysisLine(moves: [move], sanMoves: const ['e4']);
      final labelled = plain.copyWith(evalLabel: '34%');
      expect(labelled == plain, isFalse);
      expect(labelled.displayEval, '34%');
      expect(labelled.copyWith(evaluation: 1).evalLabel, '34%');
    });
  });

  group('the engine setting', () {
    test('is device-local and defaults to Stockfish', () {
      expect(const EngineSettings().engineSource, EngineSource.stockfish);
      final cloud = const EngineSettings();
      expect(
        applyDeviceLocalEngineSettings(cloud, {
          'engineSource': 'toby',
        }).usesToby,
        isTrue,
      );
      expect(
        applyDeviceLocalEngineSettings(
          cloud.copyWith(engineSource: EngineSource.toby),
          const {},
        ).usesToby,
        isTrue,
      );
      expect(engineSourceFromName('nonsense'), EngineSource.stockfish);
    });

  });
}
