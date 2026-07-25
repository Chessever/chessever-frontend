import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

enum GameReportStatus { idle, running, completed, cancelled, failed }

enum GameMoveClassification {
  brilliant('Brilliant'),
  goodMove('Best'),
  bestMove('Great'),
  missedWin('Missed Win'),
  inaccuracy('Inaccuracy'),
  mistake('Mistake'),
  blunder('Blunder');

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
    GameAnalysisReportStore? store,
  }) : _stockfish = stockfish ?? StockfishSingleton(),
       _evaluator = evaluator,
       _store = store;

  static const int reportDepth = 12;
  static const int reportMultiPv = 3;
  /// Deeper search reserved for high-precision !! verification only.
  static const int brilliantDepth = 16;
  static const int brilliantMultiPv = 3;
  static const double reportKnodeReference = 500;
  static const Duration primarySearchBudget = Duration(milliseconds: 500);
  static const Duration refinementSearchBudget = Duration(milliseconds: 500);
  static const Duration brilliantSearchBudget = Duration(milliseconds: 900);
  // An empty result during heavy board contention (rapid navigation preempting
  // the report) is transient, not a dead position — retry patiently (each loop
  // waits for board handoff first) instead of failing the whole report.
  static const int unavailableRetryLimit = 8;
  static const Duration unavailableRetryDelay = Duration(milliseconds: 200);
  static const Duration _progressThrottle = Duration(milliseconds: 120);
  static const Duration _mobileSearchYield = Duration(milliseconds: 12);

  final StockfishSingleton _stockfish;
  final GameReportEvaluator? _evaluator;
  /// When null, production uses [GameAnalysisReportStore.instance]. Tests may
  /// inject a temp-dir store, or pass a no-op via a dedicated root.
  final GameAnalysisReportStore? _store;
  late final String _ownerId = StockfishSingleton.generateOwnerId(
    'gameReport',
    identityHashCode(this),
  );
  GameReportState _state = const GameReportState();
  int _generation = 0;
  bool _disposed = false;
  DateTime? _lastProgressNotification;

  /// Completed reports keyed by game fingerprint. Session-hot path; durable
  /// store backs cold starts (see [loadPersistedReport]).
  static final Map<String, GameAnalysisReport> _reportCache =
      <String, GameAnalysisReport>{};
  static const int _reportCacheLimit = 32;

  /// The cached report for [fingerprint], if this game was already analyzed.
  static GameAnalysisReport? cachedReportFor(String fingerprint) =>
      _reportCache[fingerprint];

  /// Test hook: drop the in-memory session map (does not touch disk).
  @visibleForTesting
  static void clearSessionCacheForTest() => _reportCache.clear();

  GameAnalysisReportStore get _effectiveStore =>
      _store ?? GameAnalysisReportStore.instance;

  static void _cacheReport(String fingerprint, GameAnalysisReport report) {
    _reportCache.remove(fingerprint);
    _reportCache[fingerprint] = report;
    while (_reportCache.length > _reportCacheLimit) {
      _reportCache.remove(_reportCache.keys.first);
    }
  }

  void _persistReport(GameAnalysisReport report) {
    // Unit-test harnesses inject an evaluator without a store — skip disk IO
    // so path_provider is never touched outside a real app / injected root.
    if (_evaluator != null && _store == null) return;
    // Disk write is fire-and-forget so completion never blocks the UI thread
    // beyond the memory cache update.
    unawaited(
      _effectiveStore.save(report).catchError((Object e, StackTrace st) {
        debugPrint('Game report durable save failed: $e\n$st');
      }),
    );
  }

  GameReportState get state => _state;

  /// Adopts a previously computed report for [fingerprint] from the **session**
  /// memory cache without touching Stockfish. Returns true when applied.
  bool loadCachedReport(String fingerprint) {
    if (_disposed) return false;
    final cached = _reportCache[fingerprint];
    if (cached == null || cached.fingerprint != fingerprint) return false;
    _adoptCompletedReport(cached);
    return true;
  }

  /// Memory first, then durable local store. Call before scheduling analysis so
  /// a prior generation is restored without Stockfish.
  ///
  /// Captures [_generation] before the async disk read so a stale load for
  /// fingerprint A cannot clobber state after [invalidate] / a newer adopt for
  /// fingerprint B (game switch mid-flight).
  Future<bool> loadPersistedReport(String fingerprint) async {
    if (_disposed) return false;
    if (loadCachedReport(fingerprint)) return true;
    // Controllers with an injected evaluator are unit-test harnesses that
    // should not pull shared disk unless an explicit store was injected.
    if (_evaluator != null && _store == null) return false;
    final generation = _generation;
    final cached = await _effectiveStore.load(fingerprint);
    if (_disposed || generation != _generation) return false;
    if (cached == null || cached.fingerprint != fingerprint) return false;
    // Do not clobber an analysis that already started.
    if (_state.isRunning) return false;
    // Do not replace a completed report for a different game.
    final existing = _state.report;
    if (_state.status == GameReportStatus.completed &&
        existing != null &&
        existing.fingerprint != fingerprint) {
      return false;
    }
    _cacheReport(fingerprint, cached);
    _adoptCompletedReport(cached);
    return true;
  }

  void _adoptCompletedReport(GameAnalysisReport report) {
    _generation++;
    _setState(
      GameReportState(
        status: GameReportStatus.completed,
        progress: 1,
        completedPositions: report.positions.length,
        totalPositions: report.positions.length,
        report: report,
      ),
    );
  }

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
    final fingerprint = gameReportFingerprint(game);
    // Always check previous generations first: session memory, then durable
    // local store. Skip Stockfish when either hits.
    if (loadCachedReport(fingerprint)) return;
    if (await loadPersistedReport(fingerprint)) return;
    final generation = ++_generation;
    final fens = gameReportFens(game);
    final totalMoves = (game.mainline.length + 1) ~/ 2;
    final totalWorkUnits = fens.length + game.mainline.length;
    _lastProgressNotification = null;
    _setState(
      GameReportState(
        status: GameReportStatus.running,
        totalPositions: totalWorkUnits,
        message: 'Waiting for board analysis…',
      ),
    );

    // Board-first / report-second. The board eval bar / lines are #1: the
    // report waits for the board to be idle before touching the engine, and
    // every report job is submitted isCurrentPosition:false so any board search
    // preempts it at the scheduler. The board eval path is pristine — it knows
    // nothing about the report.
    var claimedEngine = false;
    final positions = <GameReportPosition>[];
    final evaluatedPositions = <String, GameReportPosition>{};
    try {
      if (_evaluator == null) {
        await _stockfish.waitForBoardIdle();
        if (_disposed || generation != _generation) return;
        await _stockfish.warmUp(allowInDebug: true);
        if (_disposed || generation != _generation) return;
      }
      claimedEngine = true;
      _reportProgress(
        generation: generation,
        progress: 0,
        completedPositions: 0,
        totalPositions: totalWorkUnits,
        message: 'Preparing Stockfish…',
        force: true,
      );

      // First pass: one principal variation is sufficient for the evaluation
      // graph, accuracy, rating estimate, and loss-based classifications. This
      // is substantially cheaper than asking Stockfish for three lines at
      // every ply on thermally constrained mobile devices.
      for (var i = 0; i < fens.length; i++) {
        if (_disposed || generation != _generation) return;
        final fen = fens[i];
        final terminal = terminalGameReportPosition(fen);
        GameReportPosition position;
        if (terminal != null) {
          position = terminal;
        } else {
          final reused = evaluatedPositions[fen];
          if (reused != null) {
            position = reused;
          } else {
            position = await _evaluateWithRetry(
              fen,
              generation: generation,
              multiPv: 1,
              completedWorkUnits: i,
              totalWorkUnits: totalWorkUnits,
              message: _primaryPassMessage(i, totalMoves),
            );
          }
          evaluatedPositions[fen] = position;
        }
        if (_disposed || generation != _generation) return;
        positions.add(position);
        final done = i + 1;
        _reportProgress(
          generation: generation,
          progress: done / totalWorkUnits,
          completedPositions: done,
          totalPositions: totalWorkUnits,
          message: _primaryPassMessage(i, totalMoves),
          force: true,
        );
        await _yieldForMobile();
      }

      // Second pass: request alternative lines only where they can affect the
      // report (Best/Good/Brilliant and best-alternative data). Bad moves keep
      // their depth-12 primary evaluation without paying the MultiPV cost.
      final winPercentages = positions
          .map((position) => gameReportWinPercentage(position.bestLine))
          .toList(growable: false);
      final refinedPositions = <String, GameReportPosition>{};
      for (var moveIndex = 0; moveIndex < game.mainline.length; moveIndex++) {
        if (_disposed || generation != _generation) return;
        final completedBefore = fens.length + moveIndex;
        final needsRefinement = gameReportMoveNeedsMultiPv(
          index: moveIndex,
          game: game,
          positions: positions,
          winPercentages: winPercentages,
        );
        if (needsRefinement) {
          final fen = fens[moveIndex];
          final reused = refinedPositions[fen];
          late final GameReportPosition refined;
          if (reused != null) {
            refined = reused;
          } else {
            refined = await _evaluateWithRetry(
              fen,
              generation: generation,
              multiPv: reportMultiPv,
              completedWorkUnits: completedBefore,
              totalWorkUnits: totalWorkUnits,
              message: _refinementPassMessage(moveIndex, totalMoves),
            );
          }
          refinedPositions[fen] = refined;
          positions[moveIndex] = refined;
        }
        final done = completedBefore + 1;
        _reportProgress(
          generation: generation,
          progress: done / totalWorkUnits,
          completedPositions: done,
          totalPositions: totalWorkUnits,
          message: _refinementPassMessage(moveIndex, totalMoves),
          force: true,
        );
        await _yieldForMobile();
      }

      // Third pass: high-precision !! only. Reanalyze candidate positions more
      // deeply with MultiPV so ordinary gambits never receive Brilliant from
      // shallow one-reply sacrifice heuristics alone.
      final refinedWinPct = positions
          .map((position) => gameReportWinPercentage(position.bestLine))
          .toList(growable: false);
      for (var moveIndex = 0; moveIndex < game.mainline.length; moveIndex++) {
        if (_disposed || generation != _generation) return;
        if (!isBrilliantCandidate(
          index: moveIndex,
          game: game,
          positions: positions,
          winPercentages: refinedWinPct,
        )) {
          continue;
        }
        final fen = fens[moveIndex];
        final deep = await _evaluateWithRetry(
          fen,
          generation: generation,
          multiPv: brilliantMultiPv,
          depth: brilliantDepth,
          searchDuration: brilliantSearchBudget,
          completedWorkUnits: totalWorkUnits,
          totalWorkUnits: totalWorkUnits,
          message: _brilliantPassMessage(moveIndex, totalMoves),
        );
        if (_disposed || generation != _generation) return;
        positions[moveIndex] = deep;
        // Deeper after-position line for multi-ply persistence. Keep MultiPV so
        // we do not clobber the next half-move's refined alternatives (a multiPv:1
        // overwrite made classifyGameReportMove see a single line and drop tags).
        final afterFen = fens[moveIndex + 1];
        if (terminalGameReportPosition(afterFen) == null) {
          final deepAfter = await _evaluateWithRetry(
            afterFen,
            generation: generation,
            multiPv: brilliantMultiPv,
            depth: brilliantDepth,
            searchDuration: brilliantSearchBudget,
            completedWorkUnits: totalWorkUnits,
            totalWorkUnits: totalWorkUnits,
            message: _brilliantPassMessage(moveIndex, totalMoves),
          );
          if (_disposed || generation != _generation) return;
          positions[moveIndex + 1] = deepAfter;
        }
        await _yieldForMobile();
      }

      final report = buildGameAnalysisReport(
        game: game,
        fingerprint: fingerprint,
        positions: positions,
        whiteRating: whiteRating,
        blackRating: blackRating,
      );
      if (_disposed || generation != _generation) return;
      // Production (no injected evaluator) and store-injected harnesses keep
      // session + durable copies so the next board visit is free. Pure unit
      // evaluators skip the static session map so tests stay isolated.
      if (_evaluator == null || _store != null) {
        _cacheReport(fingerprint, report);
        _persistReport(report);
      }
      _setState(
        GameReportState(
          status: GameReportStatus.completed,
          progress: 1,
          completedPositions: totalWorkUnits,
          totalPositions: totalWorkUnits,
          report: report,
        ),
      );
    } catch (error) {
      if (generation == _generation) _fail('Game analysis failed: $error');
    } finally {
      // Drop any leftover report jobs so they cannot linger on the engine after
      // settle. Owner-scoped cancel never touches the board's Stockfish owner.
      if (claimedEngine && _evaluator == null) {
        unawaited(_stockfish.cancelEvaluationsForOwner(_ownerId));
      }
    }
  }

  String _primaryPassMessage(int positionIndex, int totalMoves) {
    if (positionIndex == 0) return 'Analyzing starting position';
    final moveNumber = (positionIndex + 1) ~/ 2;
    return 'Analyzing move $moveNumber of $totalMoves';
  }

  String _refinementPassMessage(int moveIndex, int totalMoves) {
    final moveNumber = moveIndex ~/ 2 + 1;
    return 'Refining move $moveNumber of $totalMoves';
  }

  String _brilliantPassMessage(int moveIndex, int totalMoves) {
    final moveNumber = moveIndex ~/ 2 + 1;
    return 'Verifying brilliant candidate $moveNumber of $totalMoves';
  }

  Future<GameReportPosition> _evaluateWithRetry(
    String fen, {
    required int generation,
    required int multiPv,
    required int completedWorkUnits,
    required int totalWorkUnits,
    required String message,
    int? depth,
    Duration? searchDuration,
  }) async {
    var attempt = 0;
    while (true) {
      if (_disposed || generation != _generation) {
        throw const _ReportPositionPreempted();
      }
      // Board eval bar / lines are #1: hold until no board search is running or
      // queued before touching the engine for this position. Any board search
      // that starts while the report is mid-position still preempts it at the
      // scheduler (report jobs are isCurrentPosition:false).
      if (_evaluator == null) {
        await _stockfish.waitForBoardIdle();
        if (_disposed || generation != _generation) {
          throw const _ReportPositionPreempted();
        }
      }
      try {
        attempt++;
        final resolvedDepth = depth ?? reportDepth;
        final searchBudget =
            searchDuration ??
            (multiPv == 1 ? primarySearchBudget : refinementSearchBudget);
        final position = await _evaluate(
          fen,
          depth: resolvedDepth,
          multiPv: multiPv,
          searchDuration: searchBudget,
          ownerId: _ownerId,
          onProgress: (reached, knodes) {
            if (knodes <= 0) return;
            final within = 1 - 1 / (1 + knodes / reportKnodeReference);
            _reportProgress(
              generation: generation,
              progress: (completedWorkUnits + within) / totalWorkUnits,
              completedPositions: completedWorkUnits,
              totalPositions: totalWorkUnits,
              message: message,
            );
          },
        );
        return position;
      } on _ReportPositionPreempted {
        if (_disposed || generation != _generation) rethrow;
        _reportProgress(
          generation: generation,
          progress: _state.progress,
          completedPositions: completedWorkUnits,
          totalPositions: totalWorkUnits,
          message: 'Waiting for live position analysis…',
          force: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      } on _ReportPositionUnavailable {
        if (attempt >= unavailableRetryLimit ||
            _disposed ||
            generation != _generation) {
          rethrow;
        }
        _reportProgress(
          generation: generation,
          progress: _state.progress,
          completedPositions: completedWorkUnits,
          totalPositions: totalWorkUnits,
          message: 'Stockfish is warming up…',
          force: true,
        );
        await Future<void>.delayed(unavailableRetryDelay);
      }
    }
  }

  Future<void> _yieldForMobile() async {
    final isMobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    await Future<void>.delayed(isMobile ? _mobileSearchYield : Duration.zero);
  }

  Future<GameReportPosition> _evaluate(
    String fen, {
    required int depth,
    required int multiPv,
    required Duration searchDuration,
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
              searchDuration: searchDuration,
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
      throw const _ReportPositionUnavailable();
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
    bool force = false,
  }) {
    if (_disposed || generation != _generation) return;
    final now = DateTime.now();
    final lastNotification = _lastProgressNotification;
    if (!force &&
        lastNotification != null &&
        now.difference(lastNotification) < _progressThrottle) {
      return;
    }
    final nextProgress = math.max(progress, _state.progress);
    if (nextProgress == _state.progress && message == _state.message) return;
    _lastProgressNotification = now;
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

class _ReportPositionUnavailable implements Exception {
  const _ReportPositionUnavailable();

  @override
  String toString() => 'Stockfish returned no principal variation';
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
  // Sequential: some tags depend on the previous half-move's classification.
  GameMoveClassification? previousClassification;
  for (var i = 0; i < game.mainline.length; i++) {
    final move = game.mainline[i];
    final before = positions[i];
    final after = positions[i + 1];
    final classification = classifyGameReportMove(
      index: i,
      game: game,
      positions: positions,
      winPercentages: winPercentages,
      previousMoveClassification: previousClassification,
    );
    previousClassification = classification;
    moves.add(
      GameReportMove(
        ply: i + 1,
        san: move.san,
        uci: move.uci,
        isWhite: move.turn == ChessColor.white,
        classification: classification,
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

/// Whether a move needs MultiPV refinement (PV1 vs PV2 for specials / Best).
bool gameReportMoveNeedsMultiPv({
  required int index,
  required ChessGame game,
  required List<GameReportPosition> positions,
  required List<double> winPercentages,
}) {
  final move = game.mainline[index];
  final before = positions[index];
  final isWhite = move.turn == ChessColor.white;
  final moverChange =
      (winPercentages[index + 1] - winPercentages[index]) * (isWhite ? 1 : -1);
  final playedIsBest =
      before.bestLine.moves.isNotEmpty &&
      before.bestLine.moves.first == move.uci;
  return playedIsBest || moverChange >= -2;
}

/// Classifies a mainline move into our [GameMoveClassification] set.
///
/// Primary metric: mover win-probability change from
/// [gameReportWinPercentage] (percentage points). Specials run first, then
/// loss tiers. Ordinary accurate play returns null.
GameMoveClassification? classifyGameReportMove({
  required int index,
  required ChessGame game,
  required List<GameReportPosition> positions,
  required List<double> winPercentages,
  GameMoveClassification? previousMoveClassification,
}) {
  final move = game.mainline[index];
  final before = positions[index];
  final isWhite = move.turn == ChessColor.white;
  final beforeWin = winPercentages[index];
  final afterWin = winPercentages[index + 1];

  // Mover ΔWin% (pp). Negative = lost winning chances.
  var moverChange = (afterWin - beforeWin) * (isWhite ? 1 : -1);

  // Prefer MultiPV estimate of the played candidate when present (stable under
  // shallow mobile search).
  for (final line in before.lines) {
    if (line.moves.isEmpty || line.moves.first != move.uci) continue;
    final lineWin = gameReportWinPercentage(line);
    final lineChange = (lineWin - beforeWin) * (isWhite ? 1 : -1);
    moverChange = math.max(moverChange, lineChange);
    break;
  }

  final playedIsBest =
      before.bestLine.moves.isNotEmpty &&
      before.bestLine.moves.first == move.uci;

  // Only one engine line → forced if it was the only choice; else loss tiers.
  if (before.lines.length <= 1) {
    if (playedIsBest) return null;
    return _missedOrLoss(
      moverChange: moverChange,
      beforeWin: beforeWin,
      afterWin: afterWin,
      isWhite: isWhite,
      playedIsBest: playedIsBest,
      previousMoveClassification: previousMoveClassification,
    );
  }

  final alternatives = before.lines
      .where((line) => line.moves.isNotEmpty && line.moves.first != move.uci)
      .toList(growable: false);
  final alternativeWin =
      alternatives.isEmpty ? null : gameReportWinPercentage(alternatives.first);

  // Gap: played result vs next-best path (pp, mover's favour).
  final alternativeGap =
      alternativeWin == null
          ? 0.0
          : (afterWin - alternativeWin) * (isWhite ? 1 : -1);

  final simpleRecapture =
      index > 0 &&
      isSimpleReportRecapture(
        positions[index - 1].fen,
        game.mainline[index - 1].uci,
        move.uci,
      );

  // ── Brilliant (!!) ─────────────────────────────────────────────────────
  // High precision, low frequency: engine-best/tied + meaningful investment +
  // multi-ply persistence + exclusions. Immediate one-reply sacrifice alone
  // is not enough (ordinary gambits / accepted pawn offers stay untagged).
  if (verifyBrilliantMove(
    index: index,
    game: game,
    positions: positions,
    winPercentages: winPercentages,
    moverChange: moverChange,
    playedIsBest: playedIsBest,
    alternativeWin: alternativeWin,
    alternativeGap: alternativeGap,
    simpleRecapture: simpleRecapture,
  )) {
    return GameMoveClassification.brilliant;
  }

  // ── Great ──────────────────────────────────────────────────────────────
  // Near-best, not a free recapture, not already crushing: either the only
  // good move (gap > 10pp) or a decisive outcome swing (cross equality with
  // ≥10pp gain). Also: engine-top conversion after the opponent's blunder.
  if (moverChange >= -2 &&
      alternativeWin != null &&
      !simpleRecapture &&
      !_isLosingOrAlternateCrushing(
        afterWin: afterWin,
        alternativeWin: alternativeWin,
        isWhite: isWhite,
      )) {
    final onlyGoodMove = alternativeGap > 10;
    final outcomeSwing = _hasChangedGameOutcome(
      beforeWin: beforeWin,
      afterWin: afterWin,
      isWhite: isWhite,
      moverChange: moverChange,
    );
    final punishError =
        playedIsBest &&
        (previousMoveClassification == GameMoveClassification.blunder ||
            previousMoveClassification == GameMoveClassification.mistake);
    if (onlyGoodMove || outcomeSwing || punishError) {
      return GameMoveClassification.bestMove;
    }
  }

  // ── Best ───────────────────────────────────────────────────────────────
  // Engine top in a live position with a meaningful PV split — not every
  // equal opening choice. Without multipv gap data, require true PV1 only
  // when the game is still contested.
  if (playedIsBest && moverChange >= -2) {
    final moverBefore = isWhite ? beforeWin : (100 - beforeWin);
    final live = moverBefore > 12 && moverBefore < 88;
    final hasMoat = alternativeWin == null || alternativeGap >= 5;
    if (live && hasMoat && !simpleRecapture) {
      return GameMoveClassification.goodMove;
    }
    // Quiet equals / decided → no positive tag.
    return null;
  }

  return _missedOrLoss(
    moverChange: moverChange,
    beforeWin: beforeWin,
    afterWin: afterWin,
    isWhite: isWhite,
    playedIsBest: playedIsBest,
    previousMoveClassification: previousMoveClassification,
  );
}

GameMoveClassification? _missedOrLoss({
  required double moverChange,
  required double beforeWin,
  required double afterWin,
  required bool isWhite,
  required bool playedIsBest,
  required GameMoveClassification? previousMoveClassification,
}) {
  final moverBefore = isWhite ? beforeWin : (100 - beforeWin);
  final moverAfter = isWhite ? afterWin : (100 - afterWin);

  // Missed conversion after opponent's blunder.
  if (previousMoveClassification == GameMoveClassification.blunder &&
      !playedIsBest &&
      moverChange < -5 &&
      moverBefore >= 60) {
    return GameMoveClassification.missedWin;
  }
  // Threw a clear win.
  if (moverBefore >= 75 && moverAfter <= 55 && moverChange <= -15) {
    return GameMoveClassification.missedWin;
  }

  return _lossTier(moverChange, beforeWin, afterWin, isWhite);
}

/// Losing after the move, or the unplayed line was already a forced win.
bool _isLosingOrAlternateCrushing({
  required double afterWin,
  required double alternativeWin,
  required bool isWhite,
}) {
  final losing = isWhite ? afterWin < 50 : afterWin > 50;
  final altCrushing = isWhite ? alternativeWin > 97 : alternativeWin < 3;
  return losing || altCrushing;
}

/// Crossed the 50% line with a ≥10pp gain for the mover.
bool _hasChangedGameOutcome({
  required double beforeWin,
  required double afterWin,
  required bool isWhite,
  required double moverChange,
}) {
  if (moverChange <= 10) return false;
  return (beforeWin < 50 && afterWin > 50) ||
      (beforeWin > 50 && afterWin < 50);
}

/// Loss tiers from mover win% drop (pp). Softened in decided games.
GameMoveClassification? _lossTier(
  double moverChange,
  double beforeWin,
  double afterWin,
  bool isWhite,
) {
  final moverBefore = isWhite ? beforeWin : (100 - beforeWin);
  final moverAfter = isWhite ? afterWin : (100 - afterWin);
  final drop = -moverChange;

  // Heavy-score "garbage time": demote severity, never spam blunders.
  if (moverBefore <= 8 || moverAfter >= 92 || moverBefore >= 95) {
    if (drop >= 25) return GameMoveClassification.mistake;
    if (drop >= 12) return GameMoveClassification.inaccuracy;
    return null;
  }

  // Live-game bands (win-probability points).
  if (drop >= 20) return GameMoveClassification.blunder;
  if (drop >= 10) return GameMoveClassification.mistake;
  if (drop >= 5) return GameMoveClassification.inaccuracy;
  // drop < 5: quiet / excellent residual — no chip.
  return null;
}

// ── Brilliant (!!) high-precision path ─────────────────────────────────────

/// Max mover win% loss (pp) for a !! candidate / verified brilliant.
const double kBrilliantMaxLossPp = 1.5;

/// Minimum MultiPV gap (played vs next-best, mover pp) for non-unique best.
const double kBrilliantMinAlternativeGapPp = 8;

/// Early plies treated as opening/book for !! exclusion (half-moves).
const int kBrilliantOpeningPlyLimit = 10;

/// Minimum engine continuation length for multi-ply persistence.
const int kBrilliantMinContinuationPlies = 3;

/// Cheap prefilter: worth spending a deeper MultiPV pass on this move.
bool isBrilliantCandidate({
  required int index,
  required ChessGame game,
  required List<GameReportPosition> positions,
  required List<double> winPercentages,
}) {
  if (index < 0 || index >= game.mainline.length) return false;
  if (index + 1 >= positions.length || index + 1 >= winPercentages.length) {
    return false;
  }
  final move = game.mainline[index];
  if (move.san.contains('=')) return false;
  if (isReportLikelyOpeningBookForBrilliant(index, game)) return false;

  final before = positions[index];
  final after = positions[index + 1];
  final isWhite = move.turn == ChessColor.white;
  final beforeWin = winPercentages[index];
  final afterWin = winPercentages[index + 1];
  if (isReportCompletelyDecidedForBrilliant(
    beforeWin: beforeWin,
    afterWin: afterWin,
    isWhite: isWhite,
  )) {
    return false;
  }

  final moverChange = (afterWin - beforeWin) * (isWhite ? 1 : -1);
  if (moverChange < -2) return false;

  final playedIsBest =
      before.bestLine.moves.isNotEmpty &&
      before.bestLine.moves.first == move.uci;
  if (!playedIsBest && moverChange < -kBrilliantMaxLossPp) return false;

  if (index > 0 &&
      isSimpleReportRecapture(
        positions[index - 1].fen,
        game.mainline[index - 1].uci,
        move.uci,
      )) {
    return false;
  }

  return isMeaningfulBrilliantInvestment(
    before.fen,
    move.uci,
    after.bestLine.moves,
  );
}

/// Full high-confidence !! gate used by [classifyGameReportMove].
///
/// Prefer fail-closed (false) over awarding !! on ordinary gambits.
bool verifyBrilliantMove({
  required int index,
  required ChessGame game,
  required List<GameReportPosition> positions,
  required List<double> winPercentages,
  required double moverChange,
  required bool playedIsBest,
  required double? alternativeWin,
  required double alternativeGap,
  required bool simpleRecapture,
}) {
  if (index < 0 || index >= game.mainline.length) return false;
  if (index + 1 >= positions.length || index + 1 >= winPercentages.length) {
    return false;
  }
  final move = game.mainline[index];
  final before = positions[index];
  final after = positions[index + 1];
  final isWhite = move.turn == ChessColor.white;
  final beforeWin = winPercentages[index];
  final afterWin = winPercentages[index + 1];

  // ── Hard exclusions ────────────────────────────────────────────────────
  if (move.san.contains('=')) return false;
  if (simpleRecapture) return false;
  if (isReportLikelyOpeningBookForBrilliant(index, game)) return false;
  if (isReportCompletelyDecidedForBrilliant(
    beforeWin: beforeWin,
    afterWin: afterWin,
    isWhite: isWhite,
  )) {
    return false;
  }
  if (alternativeWin != null &&
      _isLosingOrAlternateCrushing(
        afterWin: afterWin,
        alternativeWin: alternativeWin,
        isWhite: isWhite,
      )) {
    return false;
  }
  final losing = isWhite ? afterWin < 48 : afterWin > 52;
  if (losing) return false;

  // ── Engine-best or effectively tied ────────────────────────────────────
  final tiedForBest = moverChange >= -kBrilliantMaxLossPp;
  if (!playedIsBest && !tiedForBest) return false;
  if (moverChange < -kBrilliantMaxLossPp) return false;

  // Need MultiPV alternatives for prestige; single-line "only move" is not !!.
  if (before.lines.length < 2 || alternativeWin == null) return false;

  // Clear edge over ordinary alternatives, or a uniquely strong only-move.
  final onlyMoveResource = alternativeGap >= 12;
  final meaningfulGap = alternativeGap >= kBrilliantMinAlternativeGapPp;
  if (!onlyMoveResource && !meaningfulGap) return false;

  // ── Material / tactical investment ─────────────────────────────────────
  if (!isMeaningfulBrilliantInvestment(
    before.fen,
    move.uci,
    after.bestLine.moves,
  )) {
    return false;
  }

  // ── Multi-ply persistence (not only the immediate reply) ───────────────
  if (!brilliantContinuationPersists(
    beforeFen: before.fen,
    playedUci: move.uci,
    continuationAfterMove: after.bestLine.moves,
    afterWin: afterWin,
    isWhite: isWhite,
  )) {
    return false;
  }

  return true;
}

/// Opening / book exclusion for !!: early quiet development and gambit territory.
///
/// Sparse FENs (endgame studies / crafted boards) are not treated as opening
/// just because the half-move index is low.
bool isReportLikelyOpeningBookForBrilliant(int index, ChessGame game) {
  if (index >= kBrilliantOpeningPlyLimit) return false;
  if (_sidePieceCount(game.startingFen) <= 12) return false;
  final move = game.mainline[index];
  final san = move.san;
  // Quiet early moves in a full opening are book-like.
  final tactical = san.contains('x') || san.contains('+') || san.contains('#');
  if (!tactical) return true;
  // Early pawn gambits (even with captures) are not prestigious !! material.
  try {
    final beforeFen =
        index == 0 ? game.startingFen : game.mainline[index - 1].fen;
    final pos = Chess.fromSetup(Setup.parseFen(beforeFen));
    final played = NormalMove.fromUci(move.uci);
    if (!pos.isLegal(played)) return true;
    final piece = pos.board.pieceAt(played.from);
    if (piece?.role == Role.pawn) return true;
  } catch (_) {
    return true;
  }
  return false;
}

int _sidePieceCount(String fen) {
  try {
    final pos = Chess.fromSetup(Setup.parseFen(fen));
    var n = 0;
    for (final sq in Square.values) {
      if (pos.board.pieceAt(sq) != null) n++;
    }
    return n;
  } catch (_) {
    return 32;
  }
}

/// Completely decided positions: !! has no prestige value.
bool isReportCompletelyDecidedForBrilliant({
  required double beforeWin,
  required double afterWin,
  required bool isWhite,
}) {
  final moverBefore = isWhite ? beforeWin : (100 - beforeWin);
  final moverAfter = isWhite ? afterWin : (100 - afterWin);
  return moverBefore >= 92 ||
      moverBefore <= 8 ||
      moverAfter >= 95 ||
      moverAfter <= 5;
}

/// Meaningful material investment for !! (not routine development / exchanges).
///
/// Accepts only real sacs:
/// - classic immediate piece sacrifice (opponent takes on destination),
///   with invested piece value ≥ 3 (no pawn-only offers);
/// - declined/delayed sac: after the move, the opponent can capture our
///   just-moved piece and a one-exchange SEE is net-negative for us
///   (truly hanging / underprotected — not a protected piece on an attacked
///   square where the trade is equal or better for us).
///
/// Quiet piece moves (e.g. Nc3) are never investments — fail closed.
bool isMeaningfulBrilliantInvestment(
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
    // Equal or winning capture is not a sacrifice.
    if (immediateGain >= invested) return false;
    // Pawn-only offers are not !! investment (opening gambits, etc.).
    if (invested < 3) return false;

    final after = position.play(move);
    // Accepted in PV *or* declined: require one-exchange SEE net-negative for
    // us on the destination (true hang / underprotection). Protected pieces
    // taken into a fair recapture (e.g. N on c3 hit by pawn, defended by pawn)
    // do not count as !! material investment.
    return _isNetHangingPiece(
      after,
      square: move.to,
      owner: moving.color,
    );
  } catch (_) {
    return false;
  }
}

/// One-exchange SEE: opponent takes our piece on [square]; we recapture with
/// the cheapest defender if any. Net < 0 for [owner] ⇒ truly hanging /
/// underprotected (protected equal trades return false).
bool _isNetHangingPiece(
  Position position, {
  required Square square,
  required Side owner,
}) {
  final ourPiece = position.board.pieceAt(square);
  if (ourPiece == null || ourPiece.color != owner) return false;
  final ourVal = _pieceValue(ourPiece.role);
  if (ourVal < 3) return false;

  final opponent = owner == Side.white ? Side.black : Side.white;
  ({Square from, int value})? cheapestAttacker;
  for (final sq in Square.values) {
    final piece = position.board.pieceAt(sq);
    if (piece == null || piece.color != opponent) continue;
    final candidate = NormalMove(from: sq, to: square);
    if (!position.isLegal(candidate)) continue;
    final v = _pieceValue(piece.role);
    if (cheapestAttacker == null || v < cheapestAttacker.value) {
      cheapestAttacker = (from: sq, value: v);
    }
  }
  if (cheapestAttacker == null) return false;

  final afterCapture = position.play(
    NormalMove(from: cheapestAttacker.from, to: square),
  );
  var canRecapture = false;
  var cheapestRecapture = 100;
  for (final sq in Square.values) {
    final piece = afterCapture.board.pieceAt(sq);
    if (piece == null || piece.color != owner) continue;
    final candidate = NormalMove(from: sq, to: square);
    if (!afterCapture.isLegal(candidate)) continue;
    canRecapture = true;
    final v = _pieceValue(piece.role);
    if (v < cheapestRecapture) cheapestRecapture = v;
  }

  // Material for owner if opponent takes (and we recapture once optimally).
  final netForUs =
      canRecapture
          ? (-ourVal + cheapestAttacker.value)
          : -ourVal;
  // Require a real material hole (at least a full minor net, or free take).
  if (!canRecapture) return true;
  return netForUs <= -3;
}

/// Multi-ply persistence: the idea survives several continuation plies.
///
/// Immediate-reply capture alone is not enough — require either:
/// - a long enough PV (≥ [kBrilliantMinContinuationPlies]),
/// - material recovery / continued pressure along that PV, or
/// - a short mate sequence.
bool brilliantContinuationPersists({
  required String beforeFen,
  required String playedUci,
  required List<String> continuationAfterMove,
  required double afterWin,
  required bool isWhite,
  int minPlies = kBrilliantMinContinuationPlies,
}) {
  final moverAfter = isWhite ? afterWin : (100 - afterWin);
  // Position must not collapse for the sacrificer after the move.
  if (moverAfter < 48) return false;

  try {
    Position position = Chess.fromSetup(Setup.parseFen(beforeFen));
    final move = NormalMove.fromUci(playedUci);
    if (!position.isLegal(move)) return false;
    position = position.play(move);

    // Immediate mate after the sac is rare but valid multi-ply "persistence".
    if (position.isCheckmate) return true;

    if (continuationAfterMove.length < minPlies) {
      // Short PV only acceptable if it ends in mate for the sacrificer.
      return _continuationEndsInMateFor(
        position,
        continuationAfterMove,
        side: isWhite ? Side.white : Side.black,
      );
    }

    final materialAfterMove = _materialBalanceWhite(position);
    final sacrificer = isWhite ? Side.white : Side.black;
    // Do NOT count the check from the played move itself as multi-ply
    // persistence — that would mark any checking best-move with a long PV.
    var sawContinuationCheck = false;
    var sacAcceptedInPv = false;
    var materialAfterAcceptance = materialAfterMove;
    var pos = position;
    final dest = move.to;
    final plies = math.min(minPlies, continuationAfterMove.length);
    for (var i = 0; i < plies; i++) {
      final step = NormalMove.fromUci(continuationAfterMove[i]);
      if (!pos.isLegal(step)) return false;
      // First reply captures our sacrificed unit on its destination.
      if (i == 0 && step.to == dest) {
        final victim = pos.board.pieceAt(dest);
        if (victim != null && victim.color == sacrificer) {
          sacAcceptedInPv = true;
        }
      }
      pos = pos.play(step);
      if (i == 0 && sacAcceptedInPv) {
        materialAfterAcceptance = _materialBalanceWhite(pos);
      }
      // Checks only count after the opponent has answered (ply index >= 1).
      if (i >= 1 && pos.isCheck) sawContinuationCheck = true;
      if (pos.isCheckmate) {
        final matingSide = pos.turn == Side.white ? Side.black : Side.white;
        return matingSide == sacrificer;
      }
    }

    final materialLater = _materialBalanceWhite(pos);
    final recoveryDelta =
        isWhite
            ? (materialLater - materialAfterAcceptance)
            : (materialAfterAcceptance - materialLater);
    // Persistence: continued attack after the reply, or material recovery
    // *after the sac was accepted in the PV* — not a quiet PV that never
    // touches the offered piece (materialDelta == 0 for free).
    if (sawContinuationCheck) return true;
    if (sacAcceptedInPv && recoveryDelta >= 0) return true;
    return false;
  } catch (_) {
    return false;
  }
}

bool _continuationEndsInMateFor(
  Position start,
  List<String> ucis, {
  required Side side,
}) {
  try {
    var pos = start;
    for (final uci in ucis) {
      final step = NormalMove.fromUci(uci);
      if (!pos.isLegal(step)) return false;
      pos = pos.play(step);
    }
    if (!pos.isCheckmate) return false;
    final matingSide = pos.turn == Side.white ? Side.black : Side.white;
    return matingSide == side;
  } catch (_) {
    return false;
  }
}

int _materialBalanceWhite(Position position) {
  var score = 0;
  for (final sq in Square.values) {
    final piece = position.board.pieceAt(sq);
    if (piece == null || piece.role == Role.king) continue;
    final v = _pieceValue(piece.role);
    score += piece.color == Side.white ? v : -v;
  }
  return score;
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
