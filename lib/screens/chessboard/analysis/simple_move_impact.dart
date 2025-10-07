import 'dart:async';
import 'dart:io';
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
      positionFens: params.positionFens,
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

  const maxBrilliantPerGame = 2;
  int brilliantCount = 0;
  final sortedKeys = impactResults.keys.toList()..sort();
  for (final key in sortedKeys) {
    final analysis = impactResults[key]!;
    if (analysis.impact == MoveImpactType.brilliant) {
      if (brilliantCount >= maxBrilliantPerGame) {
        impactResults[key] = MoveImpactAnalysis(
          impact: MoveImpactType.great,
          evalChange: analysis.evalChange,
          bestMoveEval: analysis.bestMoveEval,
          actualMoveEval: analysis.actualMoveEval,
          bestMoveSan: analysis.bestMoveSan,
          actualMoveSan: analysis.actualMoveSan,
          moveIndex: analysis.moveIndex,
        );
      } else {
        brilliantCount++;
      }
    }
  }

  final typeCounts = <MoveImpactType, int>{};
  for (final analysis in impactResults.values) {
    typeCounts.update(analysis.impact, (value) => value + 1, ifAbsent: () => 1);
  }

  debugPrint('🎨 COMPREHENSIVE IMPACT: Classified ${impactResults.length} moves for ${params.gameId}');
  debugPrint('🎨 IMPACT DISTRIBUTION: ${typeCounts.map((k, v) => MapEntry(k.symbol.isEmpty ? 'regular' : k.symbol, v))}');
  return impactResults;
});

Future<List<CloudEval?>> _evaluatePositions(
  Ref ref,
  List<String> fens,
  String gameId,
) async {
  final results = List<CloudEval?>.filled(fens.length, null, growable: false);

  final indices = List<int>.generate(fens.length, (i) => fens.length - 1 - i);

  for (int chunkStart = 0; chunkStart < indices.length; chunkStart += _kEvalConcurrency) {
    final end = math.min(chunkStart + _kEvalConcurrency, indices.length);
    final chunk = <Future<void>>[];

    for (int idx = chunkStart; idx < end; idx++) {
      final fenIndex = indices[idx];
      final fen = fens[fenIndex];
      chunk.add(() async {
        try {
          // Add timeout to prevent individual eval from hanging forever
          results[fenIndex] = await _fetchEvalWithRetry(
            ref,
            fen,
            gameId,
            fenIndex,
          ).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              debugPrint('⏱️ COMPREHENSIVE IMPACT: Timeout fetching eval for position $fenIndex in $gameId');
              return null;
            },
          );
        } catch (e) {
          debugPrint('⚠️ COMPREHENSIVE IMPACT: Error fetching eval for position $fenIndex in $gameId: $e');
          results[fenIndex] = null;
        }
      }());
    }

    // Add timeout to chunk processing to prevent entire batch from hanging
    try {
      await Future.wait(chunk, eagerError: false).timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          debugPrint('⏱️ COMPREHENSIVE IMPACT: Chunk timeout for positions $chunkStart-$end in $gameId');
          return <void>[];
        },
      );
    } catch (e) {
      debugPrint('⚠️ COMPREHENSIVE IMPACT: Chunk error for positions $chunkStart-$end in $gameId: $e');
    }

    // Log progress every chunk
    final completedSoFar = results.where((e) => e != null).length;
    debugPrint('🎨 COMPREHENSIVE IMPACT: Progress $completedSoFar/${fens.length} evals completed');
  }

  return results;
}

Future<CloudEval?> _fetchEvalWithRetry(
  Ref ref,
  String fen,
  String gameId,
  int index, {
  int maxAttempts = 4,
  Duration initialDelay = const Duration(milliseconds: 600),
}) async {
  Duration delay = initialDelay;

  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await ref.read(cascadeEvalProviderForBoard(fen).future);
    } catch (e) {
      final bool rateLimited = _isRateLimitError(e);
      if (!rateLimited || attempt == maxAttempts) {
        debugPrint('⚠️ COMPREHENSIVE IMPACT: Failed to get eval for position $index in $gameId: $e');
        return null;
      }

      debugPrint(
        '⏳ COMPREHENSIVE IMPACT: Rate limited for position $index in $gameId. '
        'Retrying in ${delay.inMilliseconds}ms (attempt ${attempt + 1}/$maxAttempts)',
      );
      await Future.delayed(delay);
      delay = Duration(milliseconds: (delay.inMilliseconds * 1.8).round());
    }
  }

  return null;
}

bool _isRateLimitError(Object error) {
  if (error is HttpException) {
    return error.message.contains('429') || error.message.contains('Too Many Requests');
  }

  final message = error.toString();
  return message.contains('429') || message.contains('Too Many Requests');
}

class _BatchClassificationParams {
  final List<CloudEval?> evaluations;
  final List<String> moveSans;
  final List<String> positionFens;
  final int startIndex;
  final int endIndex;
  final String gameId;

  const _BatchClassificationParams({
    required this.evaluations,
    required this.moveSans,
    required this.positionFens,
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
    final fenBefore = index < params.positionFens.length ? params.positionFens[index] : '';
    final fenAfter = (index + 1) < params.positionFens.length ? params.positionFens[index + 1] : null;

    MoveImpactAnalysis? analysis;
    if (evalBefore != null) {
      analysis = calculateMoveImpact(
        positionEvalBeforeMove: evalBefore,
        positionEvalAfterMove: evalAfter,
        positionFenBeforeMove: fenBefore,
        positionFenAfterMove: fenAfter,
        playerMoveSan: moveSan,
        moveNumber: index,
      );
    } else {
      debugPrint('⚠️ COMPREHENSIVE IMPACT: Missing eval before move $index in ${params.gameId}');
    }

    results.add(_BatchClassificationResult(moveIndex: index, analysis: analysis));
  }

  return results;
}
