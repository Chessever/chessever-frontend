import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/screens/chessboard/game_review/game_report_progress.dart';
import 'package:chessever2/screens/chessboard/game_review/lichess_judgment.dart';
import 'package:chessever2/screens/chessboard/game_review/move_position_facts.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

enum GameReportStatus { idle, running, completed, cancelled, failed }

enum GameMoveClassification {
  brilliant('Brilliant'),
  goodMove('Great'),
  bestMove('Top move'),
  missedWin('Missed Win'),
  inaccuracy('Inaccuracy'),
  mistake('Mistake'),
  blunder('Blunder'),
  bookMove('Book');

  const GameMoveClassification(this.label);
  final String label;

  /// Labels that mean the move did measurable damage. Book never displaces
  /// these — a line being popular is no defence, since a whole crowd can walk
  /// into the same trap.
  bool get isNegative =>
      this == GameMoveClassification.inaccuracy ||
      this == GameMoveClassification.mistake ||
      this == GameMoveClassification.blunder ||
      this == GameMoveClassification.missedWin;
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

/// Asks the game database how many games reached [uci] from [fen], where
/// [path] is the UCI line from the initial position up to [fen].
///
/// [path] is what buys depth. The gamebase answers the first plies straight
/// from its position index — transposition-inclusive, exactly what the board's
/// opening-explorer panel shows — but past that window it can only rebuild a
/// node by replaying the line, so a lookup with no path returns nothing at all
/// from ply 22 on. That is why deep theory used to go unlabelled.
///
/// Returns null when the answer is unknown — no database, no key, or a failed
/// request. Null and zero mean different things: null is "we did not find out",
/// which must never be read as "not theory".
typedef GameReportBookLookup =
    Future<int?> Function(String fen, String uci, List<String> path);

/// Produces a whole report off-device.
///
/// The server runs a checksummed copy of the algorithm below, on the same
/// gamebase, at a deeper and uncapped search than a phone can afford — so what
/// comes back is this report, only better and reproducible.
///
/// [onProgress] drives the same progress UI the engine passes drive.
/// [isCancelled] is polled so leaving the review stops the wait.
typedef GameReportRemoteRunner =
    Future<GameAnalysisReport> Function(
      ChessGame game, {
      int? whiteRating,
      int? blackRating,
      required void Function(double progress, String message) onProgress,
      required bool Function() isCancelled,
    });

class GameAnalysisReportController extends ChangeNotifier {
  GameAnalysisReportController({
    StockfishSingleton? stockfish,
    GameReportEvaluator? evaluator,
    GameAnalysisReportStore? store,
    GameReportBookLookup? bookLookup,
    GameReportRemoteRunner? remoteRunner,
  }) : _stockfish = stockfish ?? StockfishSingleton(),
       _evaluator = evaluator,
       _store = store,
       _bookLookup = bookLookup,
       _remoteRunner = remoteRunner;

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

  /// How often the server run's progress curve repaints between polls.
  static const Duration _progressTick = Duration(milliseconds: 250);
  static const Duration _mobileSearchYield = Duration(milliseconds: 12);

  final StockfishSingleton _stockfish;
  final GameReportEvaluator? _evaluator;
  /// When null, production uses [GameAnalysisReportStore.instance]. Tests may
  /// inject a temp-dir store, or pass a no-op via a dedicated root.
  final GameAnalysisReportStore? _store;

  /// Opening-tree access. Null disables book detection entirely, which is the
  /// correct behaviour offline — every move simply keeps its engine label.
  final GameReportBookLookup? _bookLookup;

  /// Server-side analysis. Null keeps every report on this device's engine.
  final GameReportRemoteRunner? _remoteRunner;
  late final String _ownerId = StockfishSingleton.generateOwnerId(
    'gameReport',
    identityHashCode(this),
  );
  GameReportState _state = const GameReportState();
  int _generation = 0;
  bool _disposed = false;
  DateTime? _lastProgressNotification;
  Timer? _progressTicker;
  final GameReportProgressSimulator _progressSimulator =
      GameReportProgressSimulator();

  /// Game + ratings for the in-flight run so foreground recovery can restart
  /// from scratch without the UI having to re-supply them.
  ChessGame? _inFlightGame;
  int? _inFlightWhiteRating;
  int? _inFlightBlackRating;
  String? _inFlightFingerprint;

  /// True after [noteAppBackgrounded] while a report was running. Cleared by
  /// [recoverAfterForeground] (soft continue or hard restart).
  bool _suspendedWhileRunning = false;
  bool _recoveryInProgress = false;

  /// How long after resume we wait for the existing loop to make progress
  /// before tearing it down and restarting from scratch.
  static const Duration defaultSoftRecoveryWindow = Duration(
    milliseconds: 2500,
  );

  /// Per-controller soft window (tests inject a short value without racing
  /// parallel suites that would share a static override).
  @visibleForTesting
  Duration softRecoveryWindow = defaultSoftRecoveryWindow;

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

  void _markPending(String fingerprint) {
    if (_evaluator != null && _store == null) return;
    unawaited(
      _effectiveStore.markPending(fingerprint).catchError((
        Object e,
        StackTrace st,
      ) {
        debugPrint('Game report pending mark failed: $e\n$st');
      }),
    );
  }

  void _clearPending(String? fingerprint) {
    if (fingerprint == null) return;
    if (_evaluator != null && _store == null) return;
    unawaited(
      _effectiveStore.clearPending(fingerprint).catchError((
        Object e,
        StackTrace st,
      ) {
        debugPrint('Game report pending clear failed: $e\n$st');
      }),
    );
  }

  void _clearInFlight({bool clearPending = true}) {
    _stopProgressTicker();
    final fp = _inFlightFingerprint;
    _inFlightGame = null;
    _inFlightWhiteRating = null;
    _inFlightBlackRating = null;
    _inFlightFingerprint = null;
    _suspendedWhileRunning = false;
    if (clearPending) _clearPending(fp);
  }

  GameReportState get state => _state;

  /// Whether a whole-game report was interrupted by process death / kill and
  /// should be restarted for [fingerprint] without a new free-tier claim.
  Future<bool> hasInterruptedRun(String fingerprint) async {
    if (_evaluator != null && _store == null) return false;
    return _effectiveStore.isPending(fingerprint);
  }

  /// App went to background while a report may be running. Does not cancel;
  /// pairs with [recoverAfterForeground] on resume.
  void noteAppBackgrounded() {
    if (_disposed) return;
    if (_state.isRunning) {
      _suspendedWhileRunning = true;
    }
  }

  /// After the app returns to foreground: keep a healthy in-flight run, or
  /// restart the same game from scratch when the old loop is stuck / dead.
  ///
  /// Never flips to the cancelled/"stopped" CTA — the UI stays on progress
  /// through soft continue or hard restart. No free-tier re-claim (caller
  /// already claimed before the original [analyze]).
  Future<void> recoverAfterForeground() async {
    if (_disposed || _recoveryInProgress) return;
    if (!_state.isRunning) return;
    // Only recover runs that actually saw background; plain setActive resume
    // must not tear down a healthy mid-report.
    if (!_suspendedWhileRunning) return;

    _recoveryInProgress = true;
    final softGeneration = _generation;
    final progressBefore = _state.completedPositions;
    final fractionBefore = _state.progress;
    try {
      _suspendedWhileRunning = false;
      if (_evaluator == null) {
        try {
          await _stockfish.warmUp(allowInDebug: true);
        } catch (e, st) {
          debugPrint('Game report resume warmUp failed: $e\n$st');
        }
      }

      final window = softRecoveryWindow;
      final deadline = DateTime.now().add(window);
      while (DateTime.now().isBefore(deadline)) {
        if (_disposed) return;
        if (!_state.isRunning) return;
        if (_generation != softGeneration) return;
        if (_state.completedPositions > progressBefore ||
            _state.progress > fractionBefore + 0.0005) {
          // Existing loop is alive again — keep it.
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      if (_disposed || !_state.isRunning || _generation != softGeneration) {
        return;
      }
      // Stalled after soft window: kill the old loop and start clean.
      await _restartInFlightFromScratch();
    } finally {
      _recoveryInProgress = false;
    }
  }

  /// Tear down a stuck generation and re-enter [analyze] for the same game.
  /// Keeps the user on a progress surface (never cancelled) when possible.
  Future<void> _restartInFlightFromScratch() async {
    final game = _inFlightGame;
    final whiteRating = _inFlightWhiteRating;
    final blackRating = _inFlightBlackRating;
    final fingerprint = _inFlightFingerprint;

    // Invalidate the stuck loop first so its awaits exit.
    _stopProgressTicker();
    _generation++;
    try {
      await _stockfish.cancelEvaluationsForOwner(_ownerId);
    } catch (_) {}
    try {
      _stockfish.notifyEngineReleased();
    } catch (_) {}

    if (_disposed) return;

    if (game == null || game.mainline.isEmpty) {
      // Nothing to restart with — fall back to the retry CTA.
      _clearInFlight();
      _setState(
        const GameReportState(
          status: GameReportStatus.cancelled,
          message: 'Analysis interrupted. Tap Generate Report to try again.',
        ),
      );
      return;
    }

    // Drop to non-running so [analyze] can re-enter, without "cancelled" copy.
    _setState(
      const GameReportState(
        status: GameReportStatus.idle,
        message: 'Resuming analysis…',
      ),
    );
    // Re-mark pending for the new attempt (cleared only on terminal states).
    if (fingerprint != null) _markPending(fingerprint);

    await analyze(
      game,
      whiteRating: whiteRating,
      blackRating: blackRating,
    );
  }

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
    _stopProgressTicker();
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
    _clearInFlight();
    _setState(const GameReportState());
  }

  Future<void> cancel() async {
    if (!_state.isRunning) return;
    // Leave `running` immediately. Engine teardown can wait on bestmove/idle
    // (and hang if Stockfish was suspended while the app was backgrounded);
    // the CTA must not stay stuck on progress for that duration.
    _generation++;
    _clearInFlight();
    _setState(
      const GameReportState(
        status: GameReportStatus.cancelled,
        message: 'Analysis cancelled. Tap Generate Report to try again.',
      ),
    );
    // Best-effort teardown after UI state is already non-running. Generation
    // bump already invalidates the in-flight analyze loop.
    try {
      await _stockfish.cancelEvaluationsForOwner(_ownerId);
    } catch (_) {
      // Engine may be suspended or disposed after backgrounding.
    }
    try {
      _stockfish.notifyEngineReleased();
    } catch (_) {}
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
    if (loadCachedReport(fingerprint)) {
      _clearPending(fingerprint);
      return;
    }
    if (await loadPersistedReport(fingerprint)) {
      _clearPending(fingerprint);
      return;
    }

    // Neither cache had it, so it has to be analysed. Prefer the server: it
    // runs this same classifier deeper than a phone can, without spending the
    // user's battery. Anything that stops it falls through to the passes below,
    // so the review still works offline — it is just shallower.
    final remote = _remoteRunner;
    if (remote != null &&
        await _analyzeRemotely(
          remote,
          game,
          whiteRating: whiteRating,
          blackRating: blackRating,
        )) {
      return;
    }

    final generation = ++_generation;
    final fens = gameReportFens(game);
    final totalMoves = (game.mainline.length + 1) ~/ 2;
    final totalWorkUnits = fens.length + game.mainline.length;
    _lastProgressNotification = null;
    _inFlightGame = game;
    _inFlightWhiteRating = whiteRating;
    _inFlightBlackRating = blackRating;
    _inFlightFingerprint = fingerprint;
    _suspendedWhileRunning = false;
    _markPending(fingerprint);
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

    // Network-bound and independent of the engine, so it runs alongside the
    // Stockfish passes and is collected just before the report is assembled —
    // the opening lookups cost no extra wall-clock. [_probeBookMoves] swallows
    // its own failures, so this future never needs a catch of its own.
    final bookGameCountsFuture = _probeBookMoves(
      game,
      fens,
      generation: generation,
    );

    try {
      if (_evaluator == null) {
        await _stockfish.waitForBoardIdle();
        if (_disposed || generation != _generation) return;
        // Intentional exception: Game Review may start Stockfish in debug.
        // Board analysis must NOT copy allowInDebug: true — see
        // kEnableStockfishInDebug (LLM/agent guardrail; hangs hot restart).
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
        bookGameCounts: await bookGameCountsFuture,
      );
      if (_disposed || generation != _generation) return;
      // Production (no injected evaluator) and store-injected harnesses keep
      // session + durable copies so the next board visit is free. Pure unit
      // evaluators skip the static session map so tests stay isolated.
      if (_evaluator == null || _store != null) {
        _cacheReport(fingerprint, report);
        _persistReport(report);
      }
      _clearInFlight();
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
      if (generation == _generation) {
        _clearInFlight();
        _fail('Game analysis failed: $error');
      }
    } finally {
      // Drop any leftover report jobs so they cannot linger on the engine after
      // settle. Owner-scoped cancel never touches the board's Stockfish owner.
      if (claimedEngine && _evaluator == null) {
        unawaited(_stockfish.cancelEvaluationsForOwner(_ownerId));
        // The board's search may have handed the engine over at
        // boardHandoffDepth so this report could run. Now that the report is
        // done with it, tell the board to carry the on-screen position deeper.
        _stockfish.notifyEngineReleased();
      }
    }
  }

  /// Runs the report on the server, driving the same state machine, session
  /// cache and durable store the local passes drive.
  ///
  /// Returns true when the outcome is final — the report arrived, or the run was
  /// cancelled or superseded. Returns false when the service could not answer,
  /// which is the signal to analyse on this device instead.
  Future<bool> _analyzeRemotely(
    GameReportRemoteRunner remote,
    ChessGame game, {
    int? whiteRating,
    int? blackRating,
  }) async {
    final generation = ++_generation;
    final fingerprint = gameReportFingerprint(game);
    // The server reports one fraction for the whole job rather than a position
    // count, so the total exists only to give the progress widgets a scale.
    // It has to be the *same* scale the local passes use — one unit per FEN
    // plus one per move — because the sheet reads the move count back out of
    // it, and a shorter scale would label a 40-move game as 20.
    final totalUnits = gameReportFens(game).length + game.mainline.length;
    _lastProgressNotification = null;
    _inFlightGame = game;
    _inFlightWhiteRating = whiteRating;
    _inFlightBlackRating = blackRating;
    _inFlightFingerprint = fingerprint;
    _suspendedWhileRunning = false;
    _markPending(fingerprint);
    _beginProgressTicker();
    _setState(
      GameReportState(
        status: GameReportStatus.running,
        totalPositions: totalUnits,
        message: 'Sending game for analysis…',
      ),
    );

    try {
      final report = await remote(
        game,
        whiteRating: whiteRating,
        blackRating: blackRating,
        onProgress: (progress, message) {
          if (_disposed || generation != _generation) return;
          _reportProgress(
            generation: generation,
            progress: progress,
            completedPositions: (totalUnits * progress.clamp(0.0, 1.0)).round(),
            totalPositions: totalUnits,
            message: message,
            force: true,
          );
        },
        isCancelled: () => _disposed || generation != _generation,
      );

      if (_disposed || generation != _generation) return true;
      if (report.fingerprint != fingerprint) {
        // Everything downstream is keyed on the fingerprint, so a mismatch
        // would paint one game's verdicts onto another. The client checks this
        // too; this is the backstop.
        _clearInFlight();
        _fail('The server analysed a different game.');
        return true;
      }
      // Same rule as the local path: real app and store-injected harnesses keep
      // session and durable copies, pure unit evaluators stay isolated.
      if (_evaluator == null || _store != null) {
        _cacheReport(fingerprint, report);
        _persistReport(report);
      }
      _clearInFlight();
      _setState(
        GameReportState(
          status: GameReportStatus.completed,
          progress: 1,
          completedPositions: totalUnits,
          totalPositions: totalUnits,
          report: report,
        ),
      );
      return true;
    } catch (error) {
      // A cancelled or superseded run has already had its state set by whoever
      // cancelled it. Anything else means the server did not answer, and the
      // passes below can analyse any game it declined — so every remaining
      // failure falls back rather than surfacing.
      if (_disposed || generation != _generation) return true;
      // Cleared so the local path re-establishes its own in-flight state from
      // scratch rather than inheriting a half-finished remote attempt.
      _clearInFlight();
      debugPrint(
        '[GameReport] server analysis unavailable ($error); analysing locally',
      );
      return false;
    }
  }

  /// Walks the game from move one asking how many database games played each
  /// move, and keeps every answer it gets.
  ///
  /// Each ply is judged on its own count — a move with [kBookMoveMinGames] or
  /// more games is theory, whatever the ply before it did. Move orders dip out
  /// of the database and transpose straight back into a main line, and the
  /// board's own opening explorer counts those transpositions, so a single
  /// quiet ply must not close the book on everything after it. The walk stops
  /// only once theory is properly gone: [kBookProbeDryStreak] plies in a row
  /// below the threshold, or the [kBookProbeMaxPlies] runaway guard.
  ///
  /// Lookups go out [kBookProbeConcurrency] at a time. The walk is collected
  /// after the Stockfish passes, which take minutes, so this is about not
  /// opening a burst of connections rather than about latency.
  ///
  /// The tree is an enhancement, never a dependency: a failed lookup leaves
  /// that ply unknown rather than failing the report.
  Future<List<int?>> _probeBookMoves(
    ChessGame game,
    List<String> fens, {
    required int generation,
  }) async {
    final counts = List<int?>.filled(game.mainline.length, null);
    final lookup = _bookLookup;
    if (lookup == null) return counts;

    // The gamebase infers a position's ply from the FEN's side-to-move and
    // fullmove number. A game set up from a custom position carries counters
    // that describe that position, not a real opening, so every lookup would be
    // answering a question about the wrong ply. Such a game has no book by
    // definition — skip the walk rather than spend requests misaddressing it.
    if (game.startingFen != kInitialFEN) return counts;

    final limit = math.min(game.mainline.length, kBookProbeMaxPlies);
    final line = game.mainline
        .map((move) => move.uci)
        .toList(growable: false);
    // The engine passes normally outlast this walk, but a stalled database must
    // not be what holds a finished report open. Whatever theory was resolved
    // before the budget ran out is kept.
    final elapsed = Stopwatch()..start();
    var dryStreak = 0;

    for (var start = 0; start < limit; start += kBookProbeConcurrency) {
      if (_disposed || generation != _generation) return counts;
      if (elapsed.elapsed > kBookProbeBudget) return counts;
      final end = math.min(start + kBookProbeConcurrency, limit);
      final wave = await Future.wait<int?>([
        for (var i = start; i < end; i++)
          _bookGameCount(lookup, fens[i], line[i], line.sublist(0, i)),
      ]);
      if (_disposed || generation != _generation) return counts;
      for (var offset = 0; offset < wave.length; offset++) {
        final total = wave[offset];
        counts[start + offset] = total;
        // An unknown answer counts as dry: it is not evidence of theory, and a
        // database that has stopped answering should end the walk, not spend
        // the whole budget timing out ply after ply.
        if (total == null || total < kBookMoveMinGames) {
          dryStreak++;
        } else {
          dryStreak = 0;
        }
      }
      if (dryStreak >= kBookProbeDryStreak) return counts;
    }
    return counts;
  }

  /// One opening lookup, resolving to null on timeout or failure so a flaky
  /// database costs one unknown ply instead of the whole report.
  Future<int?> _bookGameCount(
    GameReportBookLookup lookup,
    String fen,
    String uci,
    List<String> path,
  ) async {
    try {
      return await lookup(fen, uci, path).timeout(kBookLookupTimeout);
    } catch (_) {
      return null;
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
            // allowInDebug: true is Game Review only. Do not mirror this on the
            // board eval bar path (kEnableStockfishInDebug / hot-restart guard).
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
    _stopProgressTicker();
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
    final simulatedProgress = _progressSimulator.observe(progress);
    final now = DateTime.now();
    final lastNotification = _lastProgressNotification;
    if (!force &&
        lastNotification != null &&
        now.difference(lastNotification) < _progressThrottle) {
      return;
    }
    final nextProgress = math.max(simulatedProgress, _state.progress);
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
    _stopProgressTicker();
    _disposed = true;
    _generation++;
    // Keep durable pending so a process-death / dispose mid-run can resume
    // when the same game is opened again. In-memory in-flight refs go away.
    _inFlightGame = null;
    _inFlightWhiteRating = null;
    _inFlightBlackRating = null;
    // fingerprint left for pending row; clear only the live refs
    _suspendedWhileRunning = false;
    unawaited(_stockfish.cancelEvaluationsForOwner(_ownerId));
    super.dispose();
  }

  /// Keeps the bar moving while the server works.
  ///
  /// The Worker answers one poll every couple of seconds and holds a single
  /// phase fraction for most of the job, so without this the bar would freeze
  /// for tens of seconds at a time and read as a hang. The local passes do not
  /// arm it: they call back per analysed position, which is already an honest
  /// bar, and a synthetic curve there would only overstate real work.
  void _beginProgressTicker() {
    _progressTicker?.cancel();
    _progressSimulator.start();
    _progressTicker = Timer.periodic(_progressTick, (_) {
      if (_disposed || !_state.isRunning) {
        _stopProgressTicker();
        return;
      }
      final progress = _progressSimulator.tick();
      if (progress <= _state.progress) return;
      _setState(
        GameReportState(
          status: GameReportStatus.running,
          progress: progress,
          completedPositions: _state.completedPositions,
          totalPositions: _state.totalPositions,
          message: _state.message,
        ),
      );
    });
  }

  void _stopProgressTicker() {
    _progressTicker?.cancel();
    _progressTicker = null;
    // Disarm the curve too: a server attempt that failed hands over to the
    // local passes, and those must report their own progress from zero.
    _progressSimulator.reset();
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
  /// Database game count per move index, or null where it was not looked up.
  List<int?>? bookGameCounts,
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
      bookGameCount:
          bookGameCounts != null && i < bookGameCounts.length
              ? bookGameCounts[i]
              : null,
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
/// Two halves, deliberately kept apart. The praise — Brilliant, Great, Best and
/// Book — is ours, and it reasons in win-percentage points from
/// [gameReportWinPercentage] plus board facts. The damage — `?!`, `?`, `??` — is
/// lichess's, judged in winning chances by [lichessJudgementForReportMove], with
/// Missed Win as the one label layered over it. Ordinary accurate play returns
/// null.
GameMoveClassification? classifyGameReportMove({
  required int index,
  required ChessGame game,
  required List<GameReportPosition> positions,
  required List<double> winPercentages,
  GameMoveClassification? previousMoveClassification,
  int? bookGameCount,
}) => applyBookMoveOverride(
  _classifyGameReportMoveCore(
    index: index,
    game: game,
    positions: positions,
    winPercentages: winPercentages,
    previousMoveClassification: previousMoveClassification,
  ),
  bookGameCount,
);

/// Replaces a non-damaging label with Book when the database has seen the move
/// often enough for it to be theory.
///
/// Theory is not a decision the player found at the board, so it earns no
/// praise — Brilliant, Great and Best all give way. Errors do not: a popular
/// move can still be a trap a hundred players have fallen into, so Inaccuracy,
/// Mistake, Blunder and Missed Win always outrank Book.
GameMoveClassification? applyBookMoveOverride(
  GameMoveClassification? classification,
  int? bookGameCount,
) {
  if (bookGameCount == null || bookGameCount < kBookMoveMinGames) {
    return classification;
  }
  if (classification != null && classification.isNegative) return classification;
  return GameMoveClassification.bookMove;
}

GameMoveClassification? _classifyGameReportMoveCore({
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

  final moverBefore = isWhite ? beforeWin : (100 - beforeWin);
  final moverAfter = isWhite ? afterWin : (100 - afterWin);

  // A single engine line can never support a positive label — they all have to
  // beat an alternative — so the judgment is the whole verdict here.
  if (before.lines.length <= 1) {
    return _missedOrLoss(
      index: index,
      game: game,
      positions: positions,
      moverChange: moverChange,
      moverBefore: moverBefore,
      moverAfter: moverAfter,
      previousMoveClassification: previousMoveClassification,
    );
  }

  final alternatives = before.lines
      .where((line) => line.moves.isNotEmpty && line.moves.first != move.uci)
      .toList(growable: false);
  final alternativeWin = alternatives.isEmpty
      ? null
      : gameReportWinPercentage(alternatives.first);
  final alternativeMoverWin = alternativeWin == null
      ? null
      : (isWhite ? alternativeWin : (100 - alternativeWin));

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

  // ── Steps 2–3: board facts and outcome-band context ────────────────────
  // Derived from the FENs alone, so re-tuning the rules below never needs a
  // fresh engine run.
  final facts = describeMove(
    beforeFen: before.fen,
    playedUci: move.uci,
    previousUci: index > 0 ? game.mainline[index - 1].uci : null,
  );

  // Routine and forced moves veto *positive* labels only. They must still fall
  // through to the judgment — an obvious-looking move can be an inaccuracy or
  // worse, and returning "no symbol" here would hide it.
  var positiveLabelsEligible = !facts.isForcedOrRoutine && !simpleRecapture;

  // Routine material recovery: taking a loose or already-committed unit while
  // conceding nothing, in a position the capture does not actually change.
  // Material balance alone is never the test — a deficit can be real
  // compensation — so board evidence is combined with band and win% movement.
  final routineMaterialRecovery =
      facts.isBoardLevelMaterialRecovery &&
      !escapesClearlyLosingBand(
        moverBefore: moverBefore,
        moverAfter: moverAfter,
      ) &&
      outcomeBandFor(moverAfter).index <= outcomeBandFor(moverBefore).index &&
      moverChange < kRoutinePraiseMinWinGainPp;
  if (routineMaterialRecovery) positiveLabelsEligible = false;

  // Praise floor: below it, an ordinary capture, recapture or retreat has to
  // earn its symbol with a real winning-chance gain or by escaping the
  // clearly-losing band.
  //
  // Scoped to Great and Best only, matching the rule as written. It does not
  // currently change Brilliant either way: [verifyBrilliantMove] independently
  // requires the mover to sit near or above equality after the move, so a !!
  // can never reach this band. That also means a genuine *defensive* brilliancy
  // in a losing position is unreachable today — a known gap, tracked separately
  // rather than papered over here.
  var greatAndBestEligible = positiveLabelsEligible;

  // Once the played move and the first real alternative both keep a clearly
  // won position clearly won, their gap is conversion noise rather than a
  // prestigious decision. Brilliant remains separate: an independently
  // verified exceptional idea may still qualify on its own evidence.
  final saturatedWinningConversion =
      moverBefore >= kBandBetterMax &&
      moverAfter >= kBandBetterMax &&
      alternativeMoverWin != null &&
      alternativeMoverWin >= kBandBetterMax;
  if (saturatedWinningConversion) greatAndBestEligible = false;

  // Do not let routine captures inherit the prestige of the tactic that made
  // them possible. A capture can still earn praise in a competitive position,
  // by crossing an outcome band, or by producing a substantial win% gain.
  final beforeBand = outcomeBandFor(moverBefore);
  final afterBand = outcomeBandFor(moverAfter);
  final routineConversionCapture =
      facts.isCapture &&
      beforeBand == afterBand &&
      beforeBand != OutcomeBand.competitive &&
      moverChange < kRoutinePraiseMinWinGainPp;
  if (routineConversionCapture) greatAndBestEligible = false;

  if (moverAfter <= kPositivePraiseWinFloorPp &&
      (facts.isCapture || facts.isRoutineRetreat || facts.isForcedRecapture)) {
    final earnsException =
        moverChange >= kRoutinePraiseMinWinGainPp ||
        escapesClearlyLosingBand(
          moverBefore: moverBefore,
          moverAfter: moverAfter,
        );
    if (!earnsException) greatAndBestEligible = false;
  }

  // ── Steps 4–7: positive labels ─────────────────────────────────────────
  if (positiveLabelsEligible) {
    // Brilliant (!!): engine-best/tied + genuine material investment +
    // multi-ply persistence + exclusions. An immediate one-reply sacrifice
    // alone is not enough — ordinary gambits and accepted pawn offers stay
    // untagged.
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
      facts: facts,
    )) {
      return GameMoveClassification.brilliant;
    }

    // Great: near-best — the only reliable move (meaningful MultiPV gap), a
    // decisive outcome swing, engine-top punishment of the opponent's error,
    // a defensive save, or a clean advantage conversion where natural
    // alternatives slip. Defensive saves may still sit under 50% after the
    // move (partial recovery); other paths keep the losing/alt-crushing veto.
    if (greatAndBestEligible &&
        moverChange >= -2 &&
        alternativeWin != null) {
      final defensiveSave = _isDefensiveSave(
        playedIsBest: playedIsBest,
        moverBefore: moverBefore,
        moverAfter: moverAfter,
        alternativeGap: alternativeGap,
      );
      final notLosingOrCrushing = !_isLosingOrAlternateCrushing(
        afterWin: afterWin,
        alternativeWin: alternativeWin,
        isWhite: isWhite,
      );
      if (defensiveSave || notLosingOrCrushing) {
        final onlyGoodMove = alternativeGap >= kGreatOnlyGoodMoveGapPp;
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
        final advantageConversion = _isAdvantageConversion(
          playedIsBest: playedIsBest,
          moverBefore: moverBefore,
          moverAfter: moverAfter,
          alternativeMoverWin: alternativeMoverWin!,
          alternativeGap: alternativeGap,
        );
        if (defensiveSave ||
            (notLosingOrCrushing &&
                (onlyGoodMove ||
                    outcomeSwing ||
                    punishError ||
                    advantageConversion))) {
          return GameMoveClassification.bestMove;
        }
      }
    }

    // Best: being PV1 is not sufficient on its own. The next playable
    // alternative has to be meaningfully worse, and the position has to still
    // be contested — unless the move is itself a substantial defensive
    // recovery.
    if (greatAndBestEligible && playedIsBest && moverChange >= -2) {
      final band = outcomeBandFor(moverBefore);
      final contested =
          band == OutcomeBand.competitive ||
          band == OutcomeBand.worse ||
          band == OutcomeBand.better;
      final recovers = escapesClearlyLosingBand(
        moverBefore: moverBefore,
        moverAfter: moverAfter,
      );
      final hasMoat =
          alternativeWin == null || alternativeGap >= kBestRequiredPvMoatPp;
      if ((contested || recovers) && hasMoat) {
        return GameMoveClassification.goodMove;
      }
    }
  }

  // ── Steps 8–11 ─────────────────────────────────────────────────────────
  return _missedOrLoss(
    index: index,
    game: game,
    positions: positions,
    moverChange: moverChange,
    moverBefore: moverBefore,
    moverAfter: moverAfter,
    previousMoveClassification: previousMoveClassification,
  );
}

/// Lichess's verdict for mainline move [index] — the sole source of `?!`, `?`
/// and `??`. Null means lichess would leave the move unmarked.
///
/// Both scores come from the engine's first line, White-relative, exactly as
/// `AnalysisBuilder.makeInfos` feeds `Advice`. See [lichessAdvice] for the rules
/// and for the one deviation (lichess measures move one against a fixed +0.15
/// because fishnet never evaluates the starting position; we have that
/// evaluation, so we use it).
LichessJudgement? lichessJudgementForReportMove({
  required int index,
  required ChessGame game,
  required List<GameReportPosition> positions,
}) {
  if (index < 0 || index >= game.mainline.length) return null;
  if (index + 1 >= positions.length) return null;
  final move = game.mainline[index];
  final before = positions[index].bestLine;
  final after = positions[index + 1].bestLine;
  return lichessAdvice(
    previous: EngineScore.fromLine(
      centipawns: before.centipawns,
      mate: before.mate,
    ),
    current: EngineScore.fromLine(
      centipawns: after.centipawns,
      mate: after.mate,
    ),
    moverIsWhite: move.turn == ChessColor.white,
    engineBestUci: before.moves.isEmpty ? null : before.moves.first,
    playedUci: move.uci,
  );
}

/// The negative half of the verdict: lichess's judgment, with ChessEver's
/// decided-outcome amnesty and Missed Win layered on top of it.
///
/// The port remains the source of thresholds and severity. The one deliberate
/// product overlay is that a mover who remains at 77 or higher, or at 23 or
/// lower, on the report's winning-chance scale receives no negative symbol.
/// Those bounds map roughly to ±3.3 and keep conversion noise silent on either
/// side without weakening judgments that change the outcome.
GameMoveClassification? _missedOrLoss({
  required int index,
  required ChessGame game,
  required List<GameReportPosition> positions,
  required double moverChange,
  required double moverBefore,
  required double moverAfter,
  required GameMoveClassification? previousMoveClassification,
}) {
  final retainedDecisiveWin =
      moverBefore >= kDecisiveWinNoErrorFloorPp &&
      moverAfter >= kDecisiveWinNoErrorFloorPp;
  final retainedDecisiveLoss =
      moverBefore <= kDecisiveLossNoErrorCeilingPp &&
      moverAfter <= kDecisiveLossNoErrorCeilingPp;
  if (retainedDecisiveWin || retainedDecisiveLoss) {
    return null;
  }

  final judgement = lichessJudgementForReportMove(
    index: index,
    game: game,
    positions: positions,
  );
  if (judgement == null) return null;

  // ── Missed Win ─────────────────────────────────────────────────────────
  // Ours, not lichess's, and deliberately gated behind a judgment: it only ever
  // *renames* an error lichess already found, so the set of moves carrying a
  // negative symbol stays exactly lichess's set. A missed conversion after the
  // opponent's blunder, then throwing a clear win outright.
  if (previousMoveClassification == GameMoveClassification.blunder &&
      moverChange < -5 &&
      moverBefore >= 60) {
    return GameMoveClassification.missedWin;
  }
  if (moverBefore >= 75 && moverAfter <= 55 && moverChange <= -15) {
    return GameMoveClassification.missedWin;
  }

  return switch (judgement) {
    LichessJudgement.inaccuracy => GameMoveClassification.inaccuracy,
    LichessJudgement.mistake => GameMoveClassification.mistake,
    LichessJudgement.blunder => GameMoveClassification.blunder,
  };
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

/// Near-best resource that lifts the mover out of a lost or clearly-worse
/// position while alternatives remain meaningfully inferior.
///
/// Stronger than Best's "recovers" path: requires engine-top play plus a
/// gap under the Great only-reliable bar so ordinary defensive Best moves
/// stay ★ rather than !.
bool _isDefensiveSave({
  required bool playedIsBest,
  required double moverBefore,
  required double moverAfter,
  required double alternativeGap,
}) {
  if (!playedIsBest) return false;
  if (alternativeGap < kGreatSupportingPathMinGapPp) return false;
  final beforeBand = outcomeBandFor(moverBefore);
  final afterBand = outcomeBandFor(moverAfter);
  final savedFromLosing = escapesClearlyLosingBand(
    moverBefore: moverBefore,
    moverAfter: moverAfter,
  );
  final climbedFromWorse =
      beforeBand == OutcomeBand.worse &&
      afterBand.index >= OutcomeBand.competitive.index &&
      (moverAfter - moverBefore) > kBandHysteresisPp;
  return savedFromLosing || climbedFromWorse;
}

/// Engine-top conversion that keeps a real advantage when the natural
/// alternative would surrender it (band drop with a supporting MultiPV gap).
bool _isAdvantageConversion({
  required bool playedIsBest,
  required double moverBefore,
  required double moverAfter,
  required double alternativeMoverWin,
  required double alternativeGap,
}) {
  if (!playedIsBest) return false;
  if (alternativeGap < kGreatSupportingPathMinGapPp) return false;
  final beforeBand = outcomeBandFor(moverBefore);
  final afterBand = outcomeBandFor(moverAfter);
  if (beforeBand.index < OutcomeBand.better.index) return false;
  if (afterBand.index < OutcomeBand.better.index) return false;
  return outcomeBandFor(alternativeMoverWin).index < OutcomeBand.better.index;
}

// ── Brilliant (!!) high-precision path ─────────────────────────────────────

/// Max mover win% loss (pp) for a !! candidate / verified brilliant.
///
/// A Brilliant has to be the engine's move: within one percentage point of PV1.
const double kBrilliantMaxLossPp = 1;

/// Database games a move needs before it counts as theory rather than a choice
/// the player made over the board.
const int kBookMoveMinGames = 10;

/// How far into a game the opening tree is consulted at all — a runaway guard,
/// not the real stopping rule (that is [kBookProbeDryStreak]), so a pathological
/// line cannot spend a lookup per move across a 150-move game.
///
/// The old ceiling was twenty plies, tied to the gamebase materialised view.
/// That view is only the *fast* path: handed the move line, the backend keeps
/// answering far deeper — a Marshall main line still returns 22 games at ply 36
/// — and real theory routinely runs past move fifteen, so the view's depth was
/// cutting off book long before book actually ended. Sixty plies clears any
/// real book line while still bounding the work.
const int kBookProbeMaxPlies = 60;

/// Plies in a row below [kBookMoveMinGames] that end the walk.
///
/// Deliberately not a contiguity rule. A move order can leave the database for
/// a ply and transpose straight back into a main line, and that move is still
/// theory, so one quiet ply must not close the book. Six is long enough for any
/// real transposition and short enough that a middlegame costs six spare
/// lookups before the walk gives up.
const int kBookProbeDryStreak = 6;

/// Lookups in flight at once.
const int kBookProbeConcurrency = 4;

/// Ceiling on one opening lookup, and on the walk as a whole.
///
/// A cold position at the edge of the cached view is served by a table scan —
/// measured between four and six and a half seconds — so the old four-second
/// ceiling timed out exactly where theory gets interesting. The counts are
/// collected after the engine passes, which take minutes, so neither number is
/// on the report's critical path.
const Duration kBookLookupTimeout = Duration(seconds: 12);
const Duration kBookProbeBudget = Duration(seconds: 90);

/// PV moat (pp) the played move needs over the first unplayed alternative
/// before being called Best. Being PV1 is not on its own a distinction.
///
/// Tuned so accurate, contested PV1 choices earn ★ without requiring the
/// near-only-move gap reserved for Great.
const double kBestRequiredPvMoatPp = 2.5;

/// MultiPV gap (pp, mover favour) for Great via the only-reliable-move path.
/// Alternatives this far worse mean the played move is the only practical choice.
const double kGreatOnlyGoodMoveGapPp = 7.5;

/// Supporting-path floor for Great defensive-save and advantage-conversion.
/// Below the only-reliable bar so those paths need their band evidence as well.
const double kGreatSupportingPathMinGapPp = 5;

/// Mover winning chance (pp) below which ordinary captures, recaptures and
/// retreats no longer earn a positive symbol by default.
const double kPositivePraiseWinFloorPp = 25;

/// The winning-chance gain (pp) that buys a routine-looking move its symbol
/// back, at any point on the scale.
const double kRoutinePraiseMinWinGainPp = 10;

/// Human-facing Game Report floor for a retained decisive win. The report's
/// Stockfish-to-win curve maps +3.3 to about 77.1%, so 77% intentionally treats
/// +7, +4 and +3.3 as the same won outcome for negative-symbol purposes.
const double kDecisiveWinNoErrorFloorPp = 77;

/// Mover-relative mirror of [kDecisiveWinNoErrorFloorPp]. A move that remains
/// below this ceiling stays decisively lost and receives no evaluation-based
/// negative symbol merely for shortening the conversion to mate.
const double kDecisiveLossNoErrorCeilingPp =
    100 - kDecisiveWinNoErrorFloorPp;

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
  MovePositionFacts? facts,
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
  // A forced reply, a recapture or an attacked piece stepping aside is never
  // Brilliant, however well the engine scores it.
  final moveFacts =
      facts ??
      describeMove(
        beforeFen: before.fen,
        playedUci: move.uci,
        previousUci: index > 0 ? game.mainline[index - 1].uci : null,
      );
  if (moveFacts.isForcedOrRoutine) return false;
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
    //
    // This SEE gate is what enforces "acceptance creates a real material
    // deficit": it requires the mover to end at least a full minor down. That
    // is one step stricter than counting a bare exchange sacrifice, chosen
    // deliberately to favour precision — a missed !! costs less than a wrong
    // one.
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
}) => isNetHangingPiece(position, square: square, owner: owner);

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

int _materialBalanceWhite(Position position) =>
    reportMaterialBalanceWhite(position);

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

int _pieceValue(Role role) => reportPieceValue(role);

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
