import 'package:dartchess/dartchess.dart';
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

  // Unique owner per notifier instance so stale cancellations from a disposed
  // explorer cannot cancel jobs enqueued by a freshly created instance.
  final String _ownerId = StockfishSingleton.generateOwnerId(
    'explorer_eval',
    0,
  );
  final Ref ref;
  int _requestId = 0;
  bool _isDisposed = false;
  bool _engineEnabled = true;

  /// Stable position identity (board + side/castling/ep).
  ///
  /// Halfmove/fullmove counters are intentionally ignored because they can
  /// change without a meaningful position change for engine evaluation.
  String _positionKey(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return fen.trim();
    return parts.take(4).join(' ');
  }

  void setEngineEnabled({
    required bool enabled,
    required String fen,
    bool force = false,
  }) {
    _engineEnabled = enabled;

    if (!enabled) {
      // Invalidate in-flight callbacks so stale completion handlers cannot
      // restart analysis after the engine was intentionally disabled.
      _requestId++;
      _stopAndClear(reason: 'disabled');
      return;
    }

    if (fen.trim().isEmpty) return;
    evaluatePosition(fen, force: force);
  }

  void evaluatePosition(String fen, {bool force = false, int attempt = 0}) {
    final normalizedFen = fen.trim();
    if (_isDisposed ||
        !_engineEnabled ||
        normalizedFen.isEmpty ||
        normalizedFen.split(' ').length < 4) {
      return;
    }

    final normalizedKey = _positionKey(normalizedFen);
    final stateKey = _positionKey(state.fen);

    if (!force && stateKey == normalizedKey) {
      if (state.isEvaluating) return;
      if (state.pvLines.isNotEmpty) return;
    }

    // Guard against duplicate forced starts for the same position while
    // analysis is already in progress (e.g. multiple post-frame triggers).
    // Allow forced restart when stuck at depth 0 with no PV lines — this
    // enables stall recovery to break the deadlock where isEvaluating is
    // true but no Stockfish job is actually running.
    if (force &&
        stateKey == normalizedKey &&
        (state.pvLines.isNotEmpty || (state.isEvaluating && state.depth > 0))) {
      return;
    }

    final settings =
        ref.read(engineSettingsProviderNew).valueOrNull ??
        const EngineSettings();
    final multiPv = settings.multiPvForStockfish().clamp(1, 5);
    final maxDepth = settings.maxDepthFor(EngineComponent.evaluationGauge);
    final searchDuration = settings.searchDurationFor(
      EngineComponent.evaluationGauge,
    );
    final requestId = ++_requestId;
    final isSameFen = stateKey == normalizedKey;

    // Guard against rare queue starvation where the request is accepted but no
    // depth/PV callbacks ever arrive (UI remains on "..."). If we detect this,
    // reset the singleton queue once and retry the same position.
    _scheduleStallRecovery(
      fen: normalizedFen,
      fenKey: normalizedKey,
      requestId: requestId,
      attempt: attempt,
    );

    // Do not fire-and-forget owner cancellation here: it races with the new
    // request and can cancel the freshly enqueued job, causing indefinite
    // "..." loading states. StockfishSingleton already cancels stale current
    // jobs for `isCurrentPosition: true` requests.

    if (!isSameFen) {
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
      // Keep previous depth/eval/PVs when retrying the same position to avoid
      // UI flicker (depth text jumping back to 0 and panel collapsing).
      depth: isSameFen ? state.depth : 0,
      clearEval: !isSameFen,
      clearMate: !isSameFen,
      pvLines: isSameFen ? state.pvLines : const [],
    );

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
            if (!_isActiveRequest(requestId, normalizedKey)) return;
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
            if (!_isActiveRequest(requestId, normalizedKey)) return;
            if (pvs.isEmpty) return;

            final lines = <ExplorerPvLine>[];
            for (final pv in pvs) {
              final normalizedEval = _pvToWhiteEval(pv, normalizedFen);
              final normalizedMate = _pvToWhiteMate(pv, normalizedFen);
              final sanMoves = _uciToSanMoves(normalizedFen, pv.moves);

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
          if (!_isActiveRequest(requestId, normalizedKey)) return;

          if (result.isCancelled) {
            // Always clear isEvaluating on cancellation so that stall
            // recovery and scheduled retries don't deadlock on guard 4
            // (which blocks forced restarts when isEvaluating is true).
            state = state.copyWith(isEvaluating: false);
            if (attempt < 1) {
              _scheduleRetry(normalizedFen, attempt + 1, fenKey: normalizedKey);
              return;
            }
            return;
          }

          final lines = <ExplorerPvLine>[];
          for (final pv in result.pvs) {
            if (pv.moves.trim().isEmpty) continue;
            final normalizedEval = _pvToWhiteEval(pv, normalizedFen);
            final normalizedMate = _pvToWhiteMate(pv, normalizedFen);
            final sanMoves = _uciToSanMoves(normalizedFen, pv.moves);

            lines.add(
              ExplorerPvLine(
                evaluation: normalizedEval,
                mate: normalizedMate,
                sanMoves: sanMoves,
                uciMoves: pv.moves.trim().split(RegExp(r'\s+')),
              ),
            );
          }

          if (lines.isEmpty && attempt < 1) {
            _scheduleRetry(normalizedFen, attempt + 1, fenKey: normalizedKey);
            return;
          }

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
          } else {
            final hasStableData = state.pvLines.isNotEmpty;
            state = state.copyWith(
              depth: state.depth,
              isEvaluating: false,
              pvLines: hasStableData ? state.pvLines : const [],
              clearEval: !hasStableData,
              clearMate: !hasStableData,
            );
          }
        })
        .catchError((Object _, StackTrace __) {
          if (!_isActiveRequest(requestId, normalizedKey)) return;
          if (attempt < 1) {
            _scheduleRetry(normalizedFen, attempt + 1, fenKey: normalizedKey);
            return;
          }
          state = state.copyWith(isEvaluating: false);
        });
  }

  void _scheduleStallRecovery({
    required String fen,
    required String fenKey,
    required int requestId,
    required int attempt,
  }) {
    Future<void>.delayed(const Duration(milliseconds: 2400), () async {
      if (!_isActiveRequest(requestId, fenKey)) return;

      final noProgressYet =
          state.isEvaluating && state.depth <= 0 && state.pvLines.isEmpty;
      if (!noProgressYet) return;
      if (!_engineEnabled) return;

      // Retry once — cancel only this owner's stale jobs to avoid nuking
      // other providers' in-flight evaluations.
      if (attempt < 1) {
        await StockfishSingleton().cancelEvaluationsForOwner(_ownerId);
        if (!_isActiveRequest(requestId, fenKey)) return;
        evaluatePosition(fen, force: true, attempt: attempt + 1);
        return;
      }

      // Never leave the UI stuck in an endless loading state.
      state = state.copyWith(isEvaluating: false);
    });
  }

  bool _isActiveRequest(int requestId, String fenKey) {
    return !_isDisposed &&
        mounted &&
        _requestId == requestId &&
        _positionKey(state.fen) == fenKey;
  }

  void _scheduleRetry(String fen, int attempt, {required String fenKey}) {
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (_isDisposed ||
          !_engineEnabled ||
          !mounted ||
          _positionKey(state.fen) != fenKey) {
        return;
      }
      evaluatePosition(fen, force: true, attempt: attempt);
    });
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

  /// Normalize centipawn eval to White's perspective.
  /// Used for intermediate onPvUpdate callbacks where PVs are raw
  /// (from side-to-move perspective).
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

  /// Normalize a PV score to White's perspective.
  ///
  /// `Pv.whitePerspective == false` means score is in side-to-move
  /// perspective and must be normalized using FEN turn.
  double _pvToWhiteEval(Pv pv, String fen) {
    final cpEval = pv.cp / 100.0;
    return pv.whitePerspective ? cpEval : _normalizeEval(cpEval, fen);
  }

  /// Normalize a mate score to White's perspective.
  int? _pvToWhiteMate(Pv pv, String fen) {
    final mate = pv.mate;
    if (mate == null || mate == 0) return null;
    return pv.whitePerspective ? mate : _normalizeMate(mate, fen);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _engineEnabled = false;
    _requestId++;
    _stopAndClear(reason: 'dispose');
    super.dispose();
  }
}

final explorerEvalProvider =
    StateNotifierProvider.autoDispose<ExplorerEvalNotifier, ExplorerEvalState>(
      (ref) => ExplorerEvalNotifier(ref),
    );
