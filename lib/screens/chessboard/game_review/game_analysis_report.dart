import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

enum GameReportStatus { idle, running, completed, cancelled, failed }

enum GameMoveClassification {
  brilliant('Brilliant'),
  goodMove('Good Move'),
  bestMove('Best Move'),
  forced('Forced'),
  inaccuracy('Inaccuracy'),
  mistake('Mistake'),
  blunder('Blunder'),
  missedWin('Missed Win');

  const GameMoveClassification(this.label);
  final String label;
}

@immutable
class GameReportLine {
  const GameReportLine({
    required this.moves,
    required this.depth,
    this.centipawns,
    this.mate,
  });

  final List<String> moves;
  final int depth;
  final int? centipawns;
  final int? mate;
}

@immutable
class GameReportPosition {
  const GameReportPosition({required this.fen, required this.lines});

  final String fen;
  final List<GameReportLine> lines;

  GameReportLine get bestLine => lines.first;
}

@immutable
class GameReportMove {
  const GameReportMove({
    required this.ply,
    required this.san,
    required this.uci,
    required this.isWhite,
    required this.classification,
    required this.evaluation,
    this.bestAlternative,
  });

  final int ply;
  final String san;
  final String uci;
  final bool isWhite;
  final GameMoveClassification? classification;
  final GameReportLine evaluation;
  final String? bestAlternative;
}

@immutable
class GameAnalysisReport {
  const GameAnalysisReport({
    required this.fingerprint,
    required this.positions,
    required this.moves,
    required this.whiteAccuracy,
    required this.blackAccuracy,
    required this.generatedAt,
    this.whiteEstimatedRating,
    this.blackEstimatedRating,
  });

  final String fingerprint;
  final List<GameReportPosition> positions;
  final List<GameReportMove> moves;
  final double whiteAccuracy;
  final double blackAccuracy;
  final int? whiteEstimatedRating;
  final int? blackEstimatedRating;
  final DateTime generatedAt;

  int count(GameMoveClassification classification, {required bool white}) =>
      moves
          .where(
            (move) =>
                move.isWhite == white && move.classification == classification,
          )
          .length;
}

@immutable
class GameReportState {
  const GameReportState({
    this.status = GameReportStatus.idle,
    this.progress = 0,
    this.completedPositions = 0,
    this.totalPositions = 0,
    this.report,
    this.message,
  });

  final GameReportStatus status;
  final double progress;
  final int completedPositions;
  final int totalPositions;
  final GameAnalysisReport? report;
  final String? message;

  bool get isRunning => status == GameReportStatus.running;
}

typedef GameReportEvaluator =
    Future<EnhancedCloudEval> Function(
      String fen, {
      required int depth,
      required int multiPv,
      required String ownerId,
      void Function(int reachedDepth, int knodes)? onProgress,
    });

class GameAnalysisReportController extends ChangeNotifier {
  GameAnalysisReportController({
    StockfishSingleton? stockfish,
    GameReportEvaluator? evaluator,
  }) : _stockfish = stockfish ?? StockfishSingleton(),
       _evaluator = evaluator;

  static const int reportDepth = 16;
  static const int reportMultiPv = 3;
  static const double reportKnodeReference = 500;

  final StockfishSingleton _stockfish;
  final GameReportEvaluator? _evaluator;
  late final String _ownerId = StockfishSingleton.generateOwnerId(
    'gameReport',
    identityHashCode(this),
  );
  GameReportState _state = const GameReportState();
  int _generation = 0;
  bool _disposed = false;

  GameReportState get state => _state;

  void invalidate() {
    _generation++;
    if (_state.isRunning) {
      unawaited(_stockfish.cancelEvaluationsForOwner(_ownerId));
    }
    _setState(const GameReportState());
  }

  Future<void> cancel() async {
    if (!_state.isRunning) return;
    _generation++;
    await _stockfish.cancelEvaluationsForOwner(_ownerId);
    _setState(
      const GameReportState(
        status: GameReportStatus.cancelled,
        message: 'Analysis paused. It will restart when this game is active.',
      ),
    );
  }

  Future<void> analyze(
    ChessGame game, {
    int? whiteRating,
    int? blackRating,
  }) async {
    if (_state.isRunning || game.mainline.isEmpty) return;
    final generation = ++_generation;
    final fingerprint = gameReportFingerprint(game);
    final fens = gameReportFens(game);
    _setState(
      GameReportState(
        status: GameReportStatus.running,
        totalPositions: fens.length,
        message: 'Preparing Stockfish…',
      ),
    );

    final positions = <GameReportPosition>[];
    try {
      for (var i = 0; i < fens.length; i++) {
        if (_disposed || generation != _generation) return;
        final fen = fens[i];
        final terminal = terminalGameReportPosition(fen);
        GameReportPosition position;
        if (terminal != null) {
          position = terminal;
        } else {
          while (true) {
            if (_disposed || generation != _generation) return;
            try {
              position = await _evaluate(
                fen,
                depth: reportDepth,
                multiPv: reportMultiPv,
                ownerId: _ownerId,
                onProgress: (reached, knodes) {
                  if (knodes <= 0) return;
                  final within = 1 - 1 / (1 + knodes / reportKnodeReference);
                  _reportProgress(
                    generation: generation,
                    progress: (i + within) / fens.length,
                    completedPositions: i,
                    totalPositions: fens.length,
                    message: 'Analyzing position ${i + 1} of ${fens.length}',
                  );
                },
              );
              break;
            } on _ReportPositionPreempted {
              if (_disposed || generation != _generation) return;
              _reportProgress(
                generation: generation,
                progress: _state.progress,
                completedPositions: i,
                totalPositions: fens.length,
                message: 'Waiting for live position analysis…',
              );
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
          }
        }
        if (_disposed || generation != _generation) return;
        positions.add(position);
        final done = i + 1;
        _reportProgress(
          generation: generation,
          progress: done / fens.length,
          completedPositions: done,
          totalPositions: fens.length,
          message: 'Analyzing position $done of ${fens.length}',
        );
      }

      final report = buildGameAnalysisReport(
        game: game,
        fingerprint: fingerprint,
        positions: positions,
        whiteRating: whiteRating,
        blackRating: blackRating,
      );
      if (_disposed || generation != _generation) return;
      _setState(
        GameReportState(
          status: GameReportStatus.completed,
          progress: 1,
          completedPositions: fens.length,
          totalPositions: fens.length,
          report: report,
        ),
      );
    } catch (error) {
      if (generation == _generation) _fail('Game analysis failed: $error');
    }
  }

  Future<GameReportPosition> _evaluate(
    String fen, {
    required int depth,
    required int multiPv,
    required String ownerId,
    void Function(int reachedDepth, int knodes)? onProgress,
  }) async {
    final customEvaluator = _evaluator;
    final result =
        customEvaluator != null
            ? await customEvaluator(
              fen,
              depth: depth,
              multiPv: multiPv,
              ownerId: ownerId,
              onProgress: onProgress,
            )
            : await _stockfish.evaluatePosition(
              fen,
              depth: depth,
              maxDepth: depth,
              multiPV: multiPv,
              isCurrentPosition: false,
              allowCache: true,
              allowInDebug: true,
              ownerId: ownerId,
              onDepthUpdate: onProgress,
            );
    if (result.isCancelled) throw const _ReportPositionPreempted();
    final lines = <GameReportLine>[
      for (final pv in result.pvs)
        if (pv.moves.trim().isNotEmpty)
          GameReportLine(
            moves: List<String>.unmodifiable(
              pv.moves
                  .trim()
                  .split(RegExp(r'\s+'))
                  .where((move) => move.isNotEmpty),
            ),
            depth: result.depth,
            centipawns: pv.isMate ? null : pv.cp,
            mate: pv.isMate ? pv.mate : null,
          ),
    ];
    if (lines.isEmpty) {
      throw StateError('Stockfish returned no principal variation');
    }
    return GameReportPosition(fen: fen, lines: List.unmodifiable(lines));
  }

  void _fail(String message) {
    _setState(
      GameReportState(status: GameReportStatus.failed, message: message),
    );
  }

  void _reportProgress({
    required int generation,
    required double progress,
    required int completedPositions,
    required int totalPositions,
    required String message,
  }) {
    if (_disposed || generation != _generation) return;
    final nextProgress = math.max(progress, _state.progress);
    if (nextProgress == _state.progress && message == _state.message) return;
    _setState(
      GameReportState(
        status: GameReportStatus.running,
        progress: nextProgress,
        completedPositions: completedPositions,
        totalPositions: totalPositions,
        message: message,
      ),
    );
  }

  void _setState(GameReportState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_stockfish.cancelEvaluationsForOwner(_ownerId));
    super.dispose();
  }
}

class _ReportPositionPreempted implements Exception {
  const _ReportPositionPreempted();
}

String gameReportFingerprint(ChessGame game) =>
    '${game.startingFen}|${game.mainline.map((move) => move.uci).join(' ')}';

List<String> gameReportFens(ChessGame game) => List<String>.unmodifiable([
  game.startingFen,
  ...game.mainline.map((move) => move.fen),
]);

GameReportPosition? terminalGameReportPosition(String fen) {
  try {
    final position = Chess.fromSetup(Setup.parseFen(fen));
    if (!position.isGameOver) return null;
    if (position.isCheckmate) {
      final whiteWon = position.turn == Side.black;
      return GameReportPosition(
        fen: fen,
        lines: [
          GameReportLine(moves: const [], depth: 0, mate: whiteWon ? 1 : -1),
        ],
      );
    }
    return GameReportPosition(
      fen: fen,
      lines: const [GameReportLine(moves: [], depth: 0, centipawns: 0)],
    );
  } catch (_) {
    return null;
  }
}

double gameReportWinPercentage(GameReportLine line) {
  final mate = line.mate;
  if (mate != null) return mate > 0 ? 100 : 0;
  final cp = (line.centipawns ?? 0).clamp(-1000, 1000);
  final winChances = 2 / (1 + math.exp(-0.00368208 * cp)) - 1;
  return 50 + 50 * winChances;
}

GameAnalysisReport buildGameAnalysisReport({
  required ChessGame game,
  required String fingerprint,
  required List<GameReportPosition> positions,
  int? whiteRating,
  int? blackRating,
}) {
  if (positions.length != game.mainline.length + 1) {
    throw ArgumentError('A report needs one evaluation per game position');
  }
  final winPercentages = positions
      .map((position) => gameReportWinPercentage(position.bestLine))
      .toList(growable: false);
  final moves = <GameReportMove>[];
  for (var i = 0; i < game.mainline.length; i++) {
    final move = game.mainline[i];
    final before = positions[i];
    final after = positions[i + 1];
    moves.add(
      GameReportMove(
        ply: i + 1,
        san: move.san,
        uci: move.uci,
        isWhite: move.turn == ChessColor.white,
        classification: classifyGameReportMove(
          index: i,
          game: game,
          positions: positions,
          winPercentages: winPercentages,
        ),
        evaluation: after.bestLine,
        bestAlternative: _bestAlternative(before, move.uci),
      ),
    );
  }
  final accuracy = computeGameReportAccuracy(winPercentages);
  final ratings = computeGameReportEstimatedRatings(
    positions,
    whiteRating: whiteRating,
    blackRating: blackRating,
  );
  return GameAnalysisReport(
    fingerprint: fingerprint,
    positions: List.unmodifiable(positions),
    moves: List.unmodifiable(moves),
    whiteAccuracy: accuracy.white,
    blackAccuracy: accuracy.black,
    whiteEstimatedRating: ratings?.white,
    blackEstimatedRating: ratings?.black,
    generatedAt: DateTime.now(),
  );
}

String? _bestAlternative(GameReportPosition position, String playedMove) {
  for (final line in position.lines) {
    if (line.moves.isNotEmpty && line.moves.first != playedMove) {
      return line.moves.first;
    }
  }
  return null;
}

GameMoveClassification? classifyGameReportMove({
  required int index,
  required ChessGame game,
  required List<GameReportPosition> positions,
  required List<double> winPercentages,
}) {
  final move = game.mainline[index];
  final before = positions[index];
  final isWhite = move.turn == ChessColor.white;
  final beforeWin = winPercentages[index];
  final afterWin = winPercentages[index + 1];
  final moverChange = (afterWin - beforeWin) * (isWhite ? 1 : -1);
  final playedIsBest =
      before.bestLine.moves.isNotEmpty &&
      before.bestLine.moves.first == move.uci;
  final alternatives = before.lines
      .where((line) => line.moves.isNotEmpty && line.moves.first != move.uci)
      .toList(growable: false);

  if (before.lines.where((line) => line.moves.isNotEmpty).length <= 1) {
    return GameMoveClassification.forced;
  }

  final alternativeWin =
      alternatives.isEmpty ? null : gameReportWinPercentage(alternatives.first);
  if (moverChange >= -2 && alternativeWin != null) {
    final alternativeChange = (afterWin - alternativeWin) * (isWhite ? 1 : -1);
    final losing = isWhite ? afterWin < 50 : afterWin > 50;
    final alternativeCompletelyWinning =
        isWhite ? alternativeWin > 97 : alternativeWin < 3;
    if (!losing &&
        !alternativeCompletelyWinning &&
        isReportPieceSacrifice(
          before.fen,
          move.uci,
          positions[index + 1].bestLine.moves,
        )) {
      return GameMoveClassification.brilliant;
    }
    final crossedOutcome =
        moverChange > 10 &&
        ((beforeWin < 50 && afterWin > 50) ||
            (beforeWin > 50 && afterWin < 50));
    final onlyGoodMove = alternativeChange > 10;
    final simpleRecapture =
        index > 0 &&
        isSimpleReportRecapture(
          positions[index - 1].fen,
          game.mainline[index - 1].uci,
          move.uci,
        );
    if (!losing &&
        !alternativeCompletelyWinning &&
        !simpleRecapture &&
        (crossedOutcome || onlyGoodMove)) {
      return GameMoveClassification.goodMove;
    }
  }

  if (playedIsBest) return GameMoveClassification.bestMove;
  final hadWinningPosition = isWhite ? beforeWin >= 75 : beforeWin <= 25;
  final lostWinningPosition = isWhite ? afterWin <= 55 : afterWin >= 45;
  if (hadWinningPosition && lostWinningPosition) {
    return GameMoveClassification.missedWin;
  }
  if (moverChange < -20) return GameMoveClassification.blunder;
  if (moverChange < -10) return GameMoveClassification.mistake;
  if (moverChange < -5) return GameMoveClassification.inaccuracy;
  return null;
}

bool isReportPieceSacrifice(
  String fen,
  String playedUci,
  List<String> bestContinuation,
) {
  try {
    final position = Chess.fromSetup(Setup.parseFen(fen));
    final move = NormalMove.fromUci(playedUci);
    if (!position.isLegal(move)) return false;
    final moving = position.board.pieceAt(move.from);
    if (moving == null || moving.role == Role.king) return false;
    final captured = position.board.pieceAt(move.to);
    final invested = _pieceValue(moving.role);
    final immediateGain = captured == null ? 0 : _pieceValue(captured.role);
    if (immediateGain >= invested || bestContinuation.isEmpty) return false;
    final reply = NormalMove.fromUci(bestContinuation.first);
    final after = position.play(move);
    if (!after.isLegal(reply)) return false;
    final replyCapture = after.board.pieceAt(reply.to);
    return reply.to == move.to &&
        replyCapture != null &&
        _pieceValue(replyCapture.role) >= invested;
  } catch (_) {
    return false;
  }
}

bool isSimpleReportRecapture(
  String fen,
  String previousUci,
  String currentUci,
) {
  try {
    final position = Chess.fromSetup(Setup.parseFen(fen));
    final previous = NormalMove.fromUci(previousUci);
    final current = NormalMove.fromUci(currentUci);
    if (!position.isLegal(previous)) return false;
    if (position.board.pieceAt(previous.to) == null) return false;
    final after = position.play(previous);
    return after.isLegal(current) &&
        current.to == previous.to &&
        after.board.pieceAt(current.to) != null;
  } catch (_) {
    return false;
  }
}

int _pieceValue(Role role) => switch (role) {
  Role.pawn => 1,
  Role.knight || Role.bishop => 3,
  Role.rook => 5,
  Role.queen => 9,
  Role.king => 100,
};

({double white, double black}) computeGameReportAccuracy(
  List<double> winPercentages,
) {
  if (winPercentages.length < 2) return (white: 0, black: 0);
  final moveAccuracies = <double>[];
  for (var i = 1; i < winPercentages.length; i++) {
    final loss =
        i.isOdd
            ? math.max(0.0, winPercentages[i - 1] - winPercentages[i])
            : math.max(0.0, winPercentages[i] - winPercentages[i - 1]);
    final raw =
        103.1668100711649 * math.exp(-0.04354415386753951 * loss) -
        3.166924740191411;
    moveAccuracies.add((raw + 1).clamp(0, 100).toDouble());
  }
  final weights = _accuracyWeights(winPercentages);
  return (
    white: _playerAccuracy(moveAccuracies, weights, even: true),
    black: _playerAccuracy(moveAccuracies, weights, even: false),
  );
}

List<double> _accuracyWeights(List<double> values) {
  final windowSize = (values.length / 10).ceil().clamp(2, 8);
  final half = (windowSize / 2).round();
  return [
    for (var i = 1; i < values.length; i++)
      _standardDeviation(
        i - half < 0
            ? values.take(windowSize).toList()
            : i + half > values.length
            ? values.skip(math.max(0, values.length - windowSize)).toList()
            : values.sublist(i - half, i + half),
      ).clamp(0.5, 12).toDouble(),
  ];
}

double _standardDeviation(List<double> values) {
  if (values.isEmpty) return 0.5;
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance =
      values.map((value) => math.pow(value - mean, 2)).reduce((a, b) => a + b) /
      values.length;
  return math.sqrt(variance);
}

double _playerAccuracy(
  List<double> accuracies,
  List<double> weights, {
  required bool even,
}) {
  final selected = <double>[];
  final selectedWeights = <double>[];
  for (var i = 0; i < accuracies.length; i++) {
    if (i.isEven == even) {
      selected.add(accuracies[i]);
      selectedWeights.add(weights[i]);
    }
  }
  if (selected.isEmpty) return 0;
  final weightSum = selectedWeights.reduce((a, b) => a + b);
  final weighted =
      [
        for (var i = 0; i < selected.length; i++)
          selected[i] * selectedWeights[i],
      ].reduce((a, b) => a + b) /
      weightSum;
  final harmonic =
      selected.length /
      selected.map((value) => 1 / math.max(value, 10)).reduce((a, b) => a + b);
  return (weighted + harmonic) / 2;
}

({int white, int black})? computeGameReportEstimatedRatings(
  List<GameReportPosition> positions, {
  int? whiteRating,
  int? blackRating,
}) {
  if (positions.length < 3) return null;
  var whiteLoss = 0.0;
  var blackLoss = 0.0;
  var whiteMoves = 0;
  var blackMoves = 0;
  var previous = _boundedCp(positions.first.bestLine);
  for (var i = 1; i < positions.length; i++) {
    final cp = _boundedCp(positions[i].bestLine);
    if (i.isOdd) {
      whiteLoss += math.max(0, previous - cp);
      whiteMoves++;
    } else {
      blackLoss += math.max(0, cp - previous);
      blackMoves++;
    }
    previous = cp;
  }
  if (whiteMoves == 0 || blackMoves == 0) return null;
  return (
    white: _ratingFromCpl(whiteLoss / whiteMoves, whiteRating ?? blackRating),
    black: _ratingFromCpl(blackLoss / blackMoves, blackRating ?? whiteRating),
  );
}

double _boundedCp(GameReportLine line) {
  final mate = line.mate;
  if (mate != null) return mate > 0 ? 1000 : -1000;
  return (line.centipawns ?? 0).clamp(-1000, 1000).toDouble();
}

int _ratingFromCpl(double cpl, int? knownRating) {
  final fromCpl = 3100 * math.exp(-0.01 * cpl);
  if (knownRating == null || knownRating <= 0) return fromCpl.round();
  final expected = -100 * math.log(math.min(knownRating, 3100) / 3100);
  final difference = cpl - expected;
  final adjusted =
      difference > 0
          ? knownRating * math.exp(-0.005 * difference)
          : knownRating / math.exp(0.005 * difference);
  return adjusted.clamp(100, 3500).round();
}
