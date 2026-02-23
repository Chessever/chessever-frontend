import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';

class ExplorerPvLine {
  final double? evaluation;
  final int? mate;
  final List<String> sanMoves;

  const ExplorerPvLine({
    this.evaluation,
    this.mate,
    this.sanMoves = const [],
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
  ExplorerEvalNotifier() : super(const ExplorerEvalState());

  static const _ownerId = 'explorer_eval';

  void evaluatePosition(String fen) {
    if (fen.isEmpty || fen.split(' ').length < 4) return;

    // Cancel any prior job for this owner.
    StockfishSingleton().cancelEvaluationsForOwner(_ownerId);

    state = ExplorerEvalState(fen: fen, isEvaluating: true);

    StockfishSingleton()
        .evaluatePosition(
          fen,
          depth: 20,
          multiPV: 3,
          isCurrentPosition: false,
          ownerId: _ownerId,
          onDepthUpdate: (depth, _) {
            if (!mounted) return;
            if (state.fen != fen) return;
            state = state.copyWith(depth: depth);
          },
          onPvUpdate: (pvs, depth) {
            if (!mounted) return;
            if (state.fen != fen) return;
            if (pvs.isEmpty) return;

            final lines = <ExplorerPvLine>[];
            for (final pv in pvs) {
              final cp = pv.cp / 100.0;
              final normalizedEval = _normalizeEval(cp, fen);
              final normalizedMate = _normalizeMate(pv.mate, fen);
              final sanMoves = _uciToSanMoves(fen, pv.moves);

              lines.add(ExplorerPvLine(
                evaluation: normalizedEval,
                mate: (normalizedMate != null && normalizedMate != 0)
                    ? normalizedMate
                    : null,
                sanMoves: sanMoves,
              ));
            }

            final first = lines.first;
            state = state.copyWith(
              evaluation: first.evaluation,
              mate: first.mate,
              depth: depth,
              pvLines: lines,
              clearMate: first.mate == null,
            );
          },
        )
        .then((result) {
          if (!mounted) return;
          if (state.fen != fen) return;

          final lines = <ExplorerPvLine>[];
          for (final pv in result.pvs) {
            if (pv.moves.trim().isEmpty) continue;
            final cp = pv.cp / 100.0;
            // Result PVs are already normalized to white's perspective by
            // StockfishSingleton._normalizeToWhitePerspective, so don't
            // double-normalize.
            final normalizedMate =
                (pv.mate != null && pv.mate != 0) ? pv.mate : null;
            final sanMoves = _uciToSanMoves(fen, pv.moves);

            lines.add(ExplorerPvLine(
              evaluation: cp,
              mate: normalizedMate,
              sanMoves: sanMoves,
            ));
          }

          final pv = result.pvs.firstOrNull;
          if (pv != null && pv.moves.isNotEmpty) {
            final cp = pv.cp / 100.0;
            final normalizedMate =
                (pv.mate != null && pv.mate != 0) ? pv.mate : null;

            state = state.copyWith(
              evaluation: cp,
              mate: normalizedMate,
              depth: result.depth,
              isEvaluating: false,
              pvLines: lines,
              clearMate: normalizedMate == null,
            );
          } else {
            state = state.copyWith(isEvaluating: false, pvLines: lines);
          }
        })
        .catchError((Object _) {
          if (!mounted) return;
          state = state.copyWith(isEvaluating: false);
        });
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
    StockfishSingleton().cancelEvaluationsForOwner(_ownerId);
    super.dispose();
  }
}

final explorerEvalProvider =
    StateNotifierProvider.autoDispose<ExplorerEvalNotifier, ExplorerEvalState>(
  (ref) => ExplorerEvalNotifier(),
);
