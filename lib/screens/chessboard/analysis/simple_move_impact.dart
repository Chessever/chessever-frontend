import 'dart:math' as math;

import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/analysis/move_impact_analyzer.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:worker_manager/worker_manager.dart';

/// COMPREHENSIVE MOVE IMPACT CALCULATION
/// Gets eval before each move, analyzes engine alternatives, compares with actual move
/// Like Lichess/Chess.com - showing brilliant, great, interesting, inaccuracy, blunder

class SimpleMoveImpactParams {
  final List<String> positionFens; // FENs for each position (length = moves + 1)
  final List<bool> isWhiteMoves; // Whether each move is white's (length = moves)
  final List<String> moveSans; // SAN notation of actual moves played (length = moves)
  final String gameId;

  SimpleMoveImpactParams({
    required this.positionFens,
    required this.isWhiteMoves,
    required this.moveSans,
    required this.gameId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimpleMoveImpactParams &&
          gameId == other.gameId &&
          listEquals(positionFens, other.positionFens);

  @override
  int get hashCode => gameId.hashCode ^ positionFens.length.hashCode;
}

const int _kEvalConcurrency = 6;
const int _kClassificationBatchSize = 16;

/// Provider that calculates move impacts by analyzing engine alternatives
/// Uses the cascade eval provider to get multiple PV lines for each position
final simpleMoveImpactProvider = FutureProvider.family<Map<int, MoveImpactAnalysis>, SimpleMoveImpactParams>((ref, params) async {
  final Map<int, MoveImpactAnalysis> impactResults = {};
  final moveCount = params.moveSans.length;
  if (moveCount == 0) {
    debugPrint('🎨 COMPREHENSIVE IMPACT: No moves to analyze for ${params.gameId}');
    return impactResults;
  }

  if (params.positionFens.length != moveCount + 1) {
    debugPrint('⚠️ COMPREHENSIVE IMPACT: FEN count mismatch for ${params.gameId} (fens=${params.positionFens.length}, moves=$moveCount)');
  }

  debugPrint('🎨 COMPREHENSIVE IMPACT: Starting for ${params.positionFens.length} positions, $moveCount moves');

  final evaluations = await _evaluatePositions(ref, params.positionFens, params.gameId);

  final availableEvalCount = evaluations.where((eval) => eval != null).length;
  debugPrint('🎨 COMPREHENSIVE IMPACT: Retrieved $availableEvalCount/${evaluations.length} position evals');

  final tasks = <Future<List<_BatchClassificationResult>>>[];
  for (int start = 0; start < moveCount; start += _kClassificationBatchSize) {
    final end = math.min(start + _kClassificationBatchSize, moveCount);
    final batchParams = _BatchClassificationParams(
      evaluations: evaluations,
      moveSans: params.moveSans,
      isWhiteMoves: params.isWhiteMoves,
      startIndex: start,
      endIndex: end,
      gameId: params.gameId,
    );

    tasks.add(
      workerManager.execute<List<_BatchClassificationResult>>(
        () => _runBatchClassification(batchParams),
        priority: WorkPriority.high,
      ),
    );
  }

  final batchResults = await Future.wait(tasks, eagerError: false);
  for (final batch in batchResults) {
    for (final result in batch) {
      if (result.analysis != null) {
        impactResults[result.moveIndex] = result.analysis!;
      }
    }
  }

  debugPrint('🎨 COMPREHENSIVE IMPACT: Classified ${impactResults.length} moves for ${params.gameId}');
  return impactResults;
});

Future<List<CloudEval?>> _evaluatePositions(
  Ref ref,
  List<String> fens,
  String gameId,
) async {
  final results = List<CloudEval?>.filled(fens.length, null, growable: false);

  for (int i = 0; i < fens.length; i += _kEvalConcurrency) {
    final end = math.min(i + _kEvalConcurrency, fens.length);
    final chunk = <Future<void>>[];

    for (int j = i; j < end; j++) {
      final fen = fens[j];
      chunk.add(() async {
        try {
          final eval = await ref.read(cascadeEvalProviderForBoard(fen).future);
          results[j] = eval;
        } catch (e) {
          debugPrint('⚠️ COMPREHENSIVE IMPACT: Failed to get eval for position $j in $gameId: $e');
          results[j] = null;
        }
      }());
    }

    await Future.wait(chunk, eagerError: false);
  }

  return results;
}

class _BatchClassificationParams {
  final List<CloudEval?> evaluations;
  final List<String> moveSans;
  final List<bool> isWhiteMoves;
  final int startIndex;
  final int endIndex;
  final String gameId;

  const _BatchClassificationParams({
    required this.evaluations,
    required this.moveSans,
    required this.isWhiteMoves,
    required this.startIndex,
    required this.endIndex,
    required this.gameId,
  });
}

class _BatchClassificationResult {
  final int moveIndex;
  final MoveImpactAnalysis? analysis;

  const _BatchClassificationResult({
    required this.moveIndex,
    required this.analysis,
  });
}

List<_BatchClassificationResult> _runBatchClassification(_BatchClassificationParams params) {
  final results = <_BatchClassificationResult>[];

  for (int index = params.startIndex; index < params.endIndex; index++) {
    final evalBefore = index < params.evaluations.length ? params.evaluations[index] : null;
    final evalAfter = (index + 1) < params.evaluations.length ? params.evaluations[index + 1] : null;
    final moveSan = params.moveSans[index];
    final isWhiteMove = params.isWhiteMoves[index];

    MoveImpactAnalysis? analysis;
    if (evalBefore != null) {
      analysis = calculateMoveImpact(
        positionEvalBeforeMove: evalBefore,
        positionEvalAfterMove: evalAfter,
        playerMoveSan: moveSan,
        moveNumber: index,
        isWhiteMove: isWhiteMove,
      );
    } else {
      debugPrint('⚠️ COMPREHENSIVE IMPACT: Missing eval before move $index in ${params.gameId}');
    }

    results.add(_BatchClassificationResult(moveIndex: index, analysis: analysis));
  }

  return results;
}
