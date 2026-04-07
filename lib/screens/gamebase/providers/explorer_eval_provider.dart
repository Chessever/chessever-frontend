import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';

class ExplorerPvLine {
  final double? evaluation;
  final int? mate;
  final List<String> sanMoves;
  final List<String> uciMoves;

  const ExplorerPvLine({
    this.evaluation,
    this.mate,
    this.sanMoves = const [],
    this.uciMoves = const [],
  });

  bool get isEmpty => sanMoves.isEmpty;

  String get displayEval {
    if (mate != null && mate != 0) return '#$mate';
    if (evaluation != null) {
      final sign = evaluation! > 0 ? '+' : '';
      return '$sign${evaluation!.toStringAsFixed(1)}';
    }
    return '';
  }
}

class ExplorerEvalState {
  final double? evaluation;
  final int? mate;
  final int depth;
  final bool isEvaluating;
  final String fen;
  final List<ExplorerPvLine> pvLines;

  const ExplorerEvalState({
    this.evaluation,
    this.mate,
    this.depth = 0,
    this.isEvaluating = false,
    this.fen = '',
    this.pvLines = const [],
  });

  ExplorerEvalState copyWith({
    double? evaluation,
    int? mate,
    int? depth,
    bool? isEvaluating,
    String? fen,
    List<ExplorerPvLine>? pvLines,
    bool clearEval = false,
    bool clearMate = false,
  }) {
    return ExplorerEvalState(
      evaluation: clearEval ? null : (evaluation ?? this.evaluation),
      mate: clearMate ? null : (mate ?? this.mate),
      depth: depth ?? this.depth,
      isEvaluating: isEvaluating ?? this.isEvaluating,
      fen: fen ?? this.fen,
      pvLines: pvLines ?? this.pvLines,
    );
  }
}

class ExplorerEvalNotifier extends StateNotifier<ExplorerEvalState> {
  ExplorerEvalNotifier(this.ref) : super(const ExplorerEvalState());

  final String _ownerId = StockfishSingleton.generateOwnerId(
    'explorer_eval',
    0,
  );
  final Ref ref;

  /// Simple monotonic generation counter. Incremented every time a new
  /// evaluation starts or the engine is disabled/disposed. Callbacks check
  /// their captured generation against the current one — if they differ,
  /// the callback is stale and is silently dropped.
  int _generation = 0;

  bool _isDisposed = false;
  bool _engineEnabled = true;

  /// Watchdog timer that detects stalled evaluations and forces a retry.
  Timer? _evalWatchdog;
  int _consecutiveWatchdogTimeouts = 0;
  static const Duration _watchdogInterval = Duration(seconds: 5);
  static const int _maxWatchdogRetries = 3;

  // ---------------------------------------------------------------
  // Position key — ignores halfmove/fullmove counters
  // ---------------------------------------------------------------

  String _positionKey(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return fen.trim();
    return parts.take(4).join(' ');
  }

  // ---------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------

  void setEngineEnabled({
    required bool enabled,
    required String fen,
    bool force = false,
  }) {
    _engineEnabled = enabled;

    if (!enabled) {
      _generation++;
      _stopAndClear(reason: 'disabled');
      return;
    }

    if (fen.trim().isEmpty) return;
    evaluatePosition(fen, force: force);
  }

  Future<void> evaluatePosition(String fen, {bool force = false}) async {
    final normalizedFen = fen.trim();
    if (_isDisposed ||
        !_engineEnabled ||
        normalizedFen.isEmpty ||
        normalizedFen.split(' ').length < 4) {
      return;
    }

    final normalizedKey = _positionKey(normalizedFen);
    final stateKey = _positionKey(state.fen);
    final isSamePosition = stateKey == normalizedKey;

    // Skip if we already have results or are evaluating this position.
    if (!force && isSamePosition) {
      if (state.isEvaluating || state.pvLines.isNotEmpty) return;
    }

    // Skip if forced but we already have meaningful results for this FEN.
    if (force && isSamePosition && state.pvLines.isNotEmpty) return;

    // Bump generation so any in-flight callbacks from the previous
    // evaluation see a stale generation and are silently dropped.
    // Do NOT fire-and-forget cancelEvaluationsForOwner here — it races
    // with the new enqueue and can cancel the freshly added job.
    // StockfishSingleton already handles preemption for same-owner
    // isCurrentPosition jobs internally.
    final gen = ++_generation;

    if (!isSamePosition) {
      final tracker = ref.read(engineDepthTrackerProvider.notifier);
      tracker.clear(
        EngineComponent.evaluationGauge,
        reason: 'opening explorer new position',
      );
      tracker.clear(
        EngineComponent.principalVariation,
        reason: 'opening explorer new position',
      );
    }

    state = state.copyWith(
      fen: normalizedFen,
      isEvaluating: true,
      depth: isSamePosition ? state.depth : 0,
      clearEval: !isSamePosition,
      clearMate: !isSamePosition,
      pvLines: isSamePosition ? state.pvLines : const [],
    );

    final settings =
        ref.read(engineSettingsProviderNew).valueOrNull ??
        const EngineSettings();
    final multiPv = settings.multiPvForStockfish().clamp(1, 5);
    final maxDepth = settings.maxDepthFor(EngineComponent.evaluationGauge);
    final searchDuration = settings.searchDurationFor(
      EngineComponent.evaluationGauge,
    );

    debugPrint(
      '🔍 EXPLORER EVAL: Starting for ${normalizedKey.split(' ').first} '
      '(gen=$gen, owner=$_ownerId)',
    );

    // ---------------------------------------------------------------
    // 1️⃣  Check Gamebase first (New!)
    // ---------------------------------------------------------------
    try {
      final gamebase = ref.read(gamebaseRepositoryProvider);
      final gamebaseEval = await gamebase
          .getEvalByFen(normalizedFen)
          .timeout(const Duration(milliseconds: 800), onTimeout: () => null);

      if (gamebaseEval != null && _isStale(gen) == false) {
        final lines = _parsePvLines(gamebaseEval.pvs, normalizedFen);
        if (lines.isNotEmpty) {
          final first = lines.first;
          final fenParts = normalizedFen.split(' ');
          final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
          final cp =
              gamebaseEval.pvs.isNotEmpty ? gamebaseEval.pvs.first.cp : 0;
          debugPrint(
            '💎 EVAL SOURCE (explorer): GAMEBASE - fen=$normalizedFen, side=$sideToMove, cp=$cp, depth=${gamebaseEval.depth}',
          );
          state = state.copyWith(
            evaluation: first.evaluation,
            mate: first.mate,
            depth: gamebaseEval.depth,
            pvLines: lines,
            isEvaluating: false,
            clearMate: first.mate == null,
          );
          _updateDepthTracking(
            depth: gamebaseEval.depth,
            knodes: gamebaseEval.knodes,
            fen: normalizedFen,
            allowDecrease: false,
            context: 'opening explorer gamebase',
          );
          return; // Skip Stockfish
        }
      }
      debugPrint(
        '⚪️ EVAL SOURCE (explorer): GAMEBASE MISS - fen=$normalizedFen',
      );
    } catch (e) {
      debugPrint('⚠️ EXPLORER EVAL: Gamebase error: $e');
    }

    // ---------------------------------------------------------------
    // 2️⃣  Fallback to Stockfish
    // ---------------------------------------------------------------
    debugPrint(
      '🟢 EVAL SOURCE (explorer): STOCKFISH FALLBACK - fen=$normalizedFen',
    );
    _scheduleWatchdog(gen, normalizedFen);

    StockfishSingleton()
        .evaluatePosition(
          normalizedFen,
          depth: maxDepth,
          searchDuration: searchDuration,
          maxDepth: maxDepth,
          multiPV: multiPv,
          isCurrentPosition: true,
          allowCache: false,
          ownerId: _ownerId,
          onDepthUpdate: (depth, knodes) {
            if (_isStale(gen)) return;
            final nextDepth = depth > state.depth ? depth : state.depth;
            state = state.copyWith(depth: nextDepth, isEvaluating: true);
            _updateDepthTracking(
              depth: nextDepth,
              knodes: knodes,
              fen: normalizedFen,
              allowDecrease: false,
              context: 'opening explorer depth',
            );
          },
          onPvUpdate: (pvs, depth) {
            if (_isStale(gen)) return;
            if (pvs.isEmpty) return;

            final lines = _parsePvLines(pvs, normalizedFen);
            if (lines.isEmpty) return;

            // Got real data — cancel watchdog and reset timeout counter.
            _cancelWatchdog();
            _consecutiveWatchdogTimeouts = 0;

            final first = lines.first;
            final streamedDepth = depth > 0 ? depth : state.depth;
            final resolvedDepth =
                streamedDepth > state.depth ? streamedDepth : state.depth;
            state = state.copyWith(
              evaluation: first.evaluation,
              mate: first.mate,
              depth: resolvedDepth,
              pvLines: lines,
              isEvaluating: true,
              clearMate: first.mate == null,
            );
            _updateDepthTracking(
              depth: resolvedDepth,
              knodes: 0,
              fen: normalizedFen,
              allowDecrease: false,
              context: 'opening explorer pv',
            );
          },
        )
        .then((result) {
          _cancelWatchdog();
          if (_isStale(gen)) return;

          if (result.isCancelled) {
            debugPrint(
              '🛑 EXPLORER EVAL: Cancelled for ${normalizedKey.split(' ').first} (gen=$gen)',
            );
            if (!_isStale(gen)) {
              // Job was preempted (likely by another provider). Cancel our
              // own Stockfish jobs first, then retry after a brief delay.
              // Cancelling first prevents the retry from coalescing with a
              // still-running job whose callbacks reference a stale generation
              // (which causes watchdog loops and perpetual "..." states).
              debugPrint(
                '🔄 EXPLORER EVAL: Scheduling retry after cancellation',
              );
              state = state.copyWith(isEvaluating: false);
              StockfishSingleton().cancelEvaluationsForOwner(_ownerId).then((
                _,
              ) {
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (!_isDisposed &&
                      mounted &&
                      _engineEnabled &&
                      _positionKey(state.fen) == normalizedKey) {
                    evaluatePosition(normalizedFen, force: true);
                  }
                });
              });
            }
            return;
          }

          final lines = _parsePvLines(
            result.pvs.where((pv) => pv.moves.trim().isNotEmpty).toList(),
            normalizedFen,
          );

          if (lines.isNotEmpty) {
            final first = lines.first;
            final finalDepth = result.depth > 0 ? result.depth : state.depth;
            final resolvedDepth =
                finalDepth > state.depth ? finalDepth : state.depth;

            state = state.copyWith(
              evaluation: first.evaluation,
              mate: first.mate,
              depth: resolvedDepth,
              isEvaluating: false,
              pvLines: lines,
              clearMate: first.mate == null,
            );
            _updateDepthTracking(
              depth: resolvedDepth,
              knodes: result.knodes,
              fen: normalizedFen,
              allowDecrease: false,
              context: 'opening explorer final',
            );
            debugPrint(
              '✅ EXPLORER EVAL: Complete depth=$resolvedDepth '
              'pvs=${lines.length} (gen=$gen)',
            );
          } else {
            final hasStableData = state.pvLines.isNotEmpty;
            state = state.copyWith(
              depth: state.depth,
              isEvaluating: false,
              pvLines: hasStableData ? state.pvLines : const [],
              clearEval: !hasStableData,
              clearMate: !hasStableData,
            );
            debugPrint('⚠️ EXPLORER EVAL: No lines returned (gen=$gen)');
          }
        })
        .catchError((Object e, StackTrace __) {
          if (_isStale(gen)) return;
          debugPrint('❌ EXPLORER EVAL: Error $e (gen=$gen)');
          state = state.copyWith(isEvaluating: false);
        });
  }

  // ---------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------

  bool _isStale(int gen) => _isDisposed || !mounted || gen != _generation;

  void _scheduleWatchdog(int gen, String fen) {
    _cancelWatchdog();
    _evalWatchdog = Timer(_watchdogInterval, () {
      if (_isStale(gen) || !state.isEvaluating) return;

      // Evaluation is still running with no PV data — likely stuck.
      _consecutiveWatchdogTimeouts++;
      debugPrint(
        '⚠️ EXPLORER EVAL WATCHDOG: Stalled for $fen '
        '(consecutive: $_consecutiveWatchdogTimeouts)',
      );

      if (_consecutiveWatchdogTimeouts >= _maxWatchdogRetries) {
        debugPrint('🔧 EXPLORER EVAL WATCHDOG: Forcing Stockfish recovery');
        _consecutiveWatchdogTimeouts = 0;
        // Bump generation BEFORE cancelling so the cancelled job's .then
        // callback sees a stale generation and does NOT schedule its own
        // retry. Only forceRecovery().then will retry — preventing double
        // evaluatePosition calls that coalesce and break streaming callbacks.
        _generation++;
        state = state.copyWith(isEvaluating: false);
        StockfishSingleton().cancelEvaluationsForOwner(_ownerId);
        StockfishSingleton().forceRecovery().then((_) {
          if (!_isDisposed && mounted && _engineEnabled) {
            evaluatePosition(fen, force: true);
          }
        });
        return;
      }

      // Cancel stuck job. Do NOT schedule a retry here — the cancelled
      // job's `.then` callback already handles retry after cancellation.
      // Retrying from BOTH the watchdog AND `.then` causes double
      // evaluatePosition calls that coalesce and invalidate callbacks.
      state = state.copyWith(isEvaluating: false);
      StockfishSingleton().cancelEvaluationsForOwner(_ownerId);
    });
  }

  void _cancelWatchdog() {
    _evalWatchdog?.cancel();
    _evalWatchdog = null;
  }

  List<ExplorerPvLine> _parsePvLines(List<Pv> pvs, String fen) {
    final lines = <ExplorerPvLine>[];
    for (final pv in pvs) {
      if (pv.moves.trim().isEmpty) continue;
      final normalizedEval = _pvToWhiteEval(pv, fen);
      final normalizedMate = _pvToWhiteMate(pv, fen);
      final sanMoves = _uciToSanMoves(fen, pv.moves);
      lines.add(
        ExplorerPvLine(
          evaluation: normalizedEval,
          mate:
              (normalizedMate != null && normalizedMate != 0)
                  ? normalizedMate
                  : null,
          sanMoves: sanMoves,
          uciMoves: pv.moves.trim().split(RegExp(r'\s+')),
        ),
      );
    }
    return lines;
  }

  void _updateDepthTracking({
    required int depth,
    required int knodes,
    required String fen,
    required bool allowDecrease,
    required String context,
  }) {
    final progress = EngineSearchProgress(
      depth: depth,
      kiloNodes: knodes,
      fenFragment: fen,
    );
    final tracker = ref.read(engineDepthTrackerProvider.notifier);
    tracker.update(
      component: EngineComponent.evaluationGauge,
      progress: progress,
      context: context,
      allowDecrease: allowDecrease,
    );
    tracker.update(
      component: EngineComponent.principalVariation,
      progress: progress,
      context: context,
      allowDecrease: allowDecrease,
    );
  }

  void _stopAndClear({required String reason}) {
    StockfishSingleton().cancelEvaluationsForOwner(_ownerId);
    final tracker = ref.read(engineDepthTrackerProvider.notifier);
    tracker.clear(
      EngineComponent.evaluationGauge,
      reason: 'opening explorer $reason',
    );
    tracker.clear(
      EngineComponent.principalVariation,
      reason: 'opening explorer $reason',
    );
    state = state.copyWith(
      isEvaluating: false,
      depth: 0,
      pvLines: const [],
      clearEval: true,
      clearMate: true,
    );
  }

  List<String> _uciToSanMoves(String baseFen, String uciMoves) {
    if (uciMoves.trim().isEmpty) return [];
    final moves = uciMoves.trim().split(RegExp(r'\s+'));
    final sanMoves = <String>[];
    var currentFen = baseFen;

    for (final uci in moves) {
      if (uci.length < 4) break;
      try {
        final position = Chess.fromSetup(Setup.parseFen(currentFen));
        final from = Square.fromName(uci.substring(0, 2));
        final to = Square.fromName(uci.substring(2, 4));
        Role? promotion;
        if (uci.length > 4) promotion = Role.fromChar(uci[4]);

        final move = NormalMove(from: from, to: to, promotion: promotion);
        final result = position.makeSan(move);
        sanMoves.add(result.$2);
        currentFen = result.$1.fen;
      } catch (_) {
        break;
      }
    }
    return sanMoves;
  }

  double _normalizeEval(double cpEval, String fen) {
    final isWhiteToMove =
        fen.split(' ').length > 1 ? fen.split(' ')[1] == 'w' : true;
    return isWhiteToMove ? cpEval : -cpEval;
  }

  int? _normalizeMate(int? mate, String fen) {
    if (mate == null || mate == 0) return mate;
    final isWhiteToMove =
        fen.split(' ').length > 1 ? fen.split(' ')[1] == 'w' : true;
    return isWhiteToMove ? mate : -mate;
  }

  double _pvToWhiteEval(Pv pv, String fen) {
    final cpEval = pv.cp / 100.0;
    return pv.whitePerspective ? cpEval : _normalizeEval(cpEval, fen);
  }

  int? _pvToWhiteMate(Pv pv, String fen) {
    final mate = pv.mate;
    if (mate == null || mate == 0) return null;
    return pv.whitePerspective ? mate : _normalizeMate(mate, fen);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _engineEnabled = false;
    _generation++;
    _cancelWatchdog();
    _stopAndClear(reason: 'dispose');
    super.dispose();
  }
}

final explorerEvalProvider =
    StateNotifierProvider.autoDispose<ExplorerEvalNotifier, ExplorerEvalState>(
      (ref) => ExplorerEvalNotifier(ref),
    );
