import 'package:dartchess/dartchess.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';

class ExplorerPvLine {
  final double? evaluation;
  final int? mate;
  final List<String> sanMoves;

  const ExplorerPvLine({this.evaluation, this.mate, this.sanMoves = const []});

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

  static const _ownerId = 'explorer_eval';
  final Ref ref;
  int _requestId = 0;
  bool _isDisposed = false;

  void setEngineEnabled({
    required bool enabled,
    required String fen,
    bool force = false,
  }) {
    if (!enabled) {
      _stopAndClear(reason: 'disabled');
      return;
    }
    if (fen.trim().isEmpty) return;
    evaluatePosition(fen, force: force);
  }

  void evaluatePosition(String fen, {bool force = false, int attempt = 0}) {
    final normalizedFen = fen.trim();
    if (_isDisposed ||
        normalizedFen.isEmpty ||
        normalizedFen.split(' ').length < 4) {
      return;
    }

    if (!force && state.fen == normalizedFen) {
      if (state.isEvaluating) return;
      if (state.pvLines.isNotEmpty) return;
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

    // Cancel any prior job for this owner.
    StockfishSingleton().cancelEvaluationsForOwner(_ownerId);

    state = state.copyWith(
      fen: normalizedFen,
      isEvaluating: true,
      depth: 0,
      clearEval: true,
      clearMate: true,
      pvLines: const [],
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
            if (!_isActiveRequest(requestId, normalizedFen)) return;
            state = state.copyWith(depth: depth, isEvaluating: true);
            _updateDepthTracking(
              depth: depth,
              knodes: knodes,
              fen: normalizedFen,
              allowDecrease: true,
              context: 'opening explorer depth',
            );
          },
          onPvUpdate: (pvs, depth) {
            if (!_isActiveRequest(requestId, normalizedFen)) return;
            if (pvs.isEmpty) return;

            final lines = <ExplorerPvLine>[];
            for (final pv in pvs) {
              final cp = pv.cp / 100.0;
              final normalizedEval = _normalizeEval(cp, normalizedFen);
              final normalizedMate = _normalizeMate(pv.mate, normalizedFen);
              final sanMoves = _uciToSanMoves(normalizedFen, pv.moves);

              lines.add(
                ExplorerPvLine(
                  evaluation: normalizedEval,
                  mate:
                      (normalizedMate != null && normalizedMate != 0)
                          ? normalizedMate
                          : null,
                  sanMoves: sanMoves,
                ),
              );
            }

            final first = lines.first;
            state = state.copyWith(
              evaluation: first.evaluation,
              mate: first.mate,
              depth: depth,
              pvLines: lines,
              isEvaluating: true,
              clearMate: first.mate == null,
            );
            _updateDepthTracking(
              depth: depth,
              knodes: 0,
              fen: normalizedFen,
              allowDecrease: true,
              context: 'opening explorer pv',
            );
          },
        )
        .then((result) {
          if (!_isActiveRequest(requestId, normalizedFen)) return;

          if (result.isCancelled) {
            if (attempt < 1) {
              _scheduleRetry(normalizedFen, attempt + 1);
              return;
            }
            state = state.copyWith(isEvaluating: false);
            return;
          }

          final lines = <ExplorerPvLine>[];
          for (final pv in result.pvs) {
            if (pv.moves.trim().isEmpty) continue;
            final cp = pv.cp / 100.0;
            // Result PVs are already normalized to white's perspective by
            // StockfishSingleton._normalizeToWhitePerspective, so don't
            // double-normalize.
            final normalizedMate =
                (pv.mate != null && pv.mate != 0) ? pv.mate : null;
            final sanMoves = _uciToSanMoves(normalizedFen, pv.moves);

            lines.add(
              ExplorerPvLine(
                evaluation: cp,
                mate: normalizedMate,
                sanMoves: sanMoves,
              ),
            );
          }

          if (lines.isEmpty && attempt < 1) {
            _scheduleRetry(normalizedFen, attempt + 1);
            return;
          }

          if (lines.isNotEmpty) {
            final first = lines.first;
            final resolvedDepth = result.depth > 0 ? result.depth : state.depth;

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
            state = state.copyWith(
              depth: 0,
              isEvaluating: false,
              pvLines: const [],
              clearEval: true,
              clearMate: true,
            );
          }
        })
        .catchError((Object _, StackTrace __) {
          if (!_isActiveRequest(requestId, normalizedFen)) return;
          if (attempt < 1) {
            _scheduleRetry(normalizedFen, attempt + 1);
            return;
          }
          state = state.copyWith(isEvaluating: false);
        });
  }

  bool _isActiveRequest(int requestId, String fen) {
    return !_isDisposed &&
        mounted &&
        _requestId == requestId &&
        state.fen == fen;
  }

  void _scheduleRetry(String fen, int attempt) {
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (_isDisposed || !mounted || state.fen != fen) return;
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

  @override
  void dispose() {
    _isDisposed = true;
    _requestId++;
    _stopAndClear(reason: 'dispose');
    super.dispose();
  }
}

final explorerEvalProvider =
    StateNotifierProvider.autoDispose<ExplorerEvalNotifier, ExplorerEvalState>(
      (ref) => ExplorerEvalNotifier(ref),
    );
