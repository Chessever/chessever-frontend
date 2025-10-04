import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:worker_manager/worker_manager.dart';

/// Enum representing different types of impactful chess moves with their visual properties
enum MoveImpactType {
  // Brilliant move (!!) - Very smart move, not easy to find
  brilliant(
    symbol: '!!',
    color: Color(0xFF00BCD4), // Turquoise
    description: 'Brilliant move - Very hard to find, gains significant advantage',
  ),

  // Great move (!) - Good move with less impact than brilliant
  great(
    symbol: '!',
    color: Color(0xFF2E7D32), // Dark green
    description: 'Great move - Good move that gains advantage',
  ),

  // Interesting move (!?) - Missed opportunity for a much better move
  interesting(
    symbol: '!?',
    color: Color(0xFFF9A825), // Dark yellow
    description: 'Interesting move - Missed opportunity for a better move',
  ),

  // Inaccuracy (?) - Suboptimal move with minor disadvantage
  inaccuracy(
    symbol: '?',
    color: Color(0xFFD32F2F), // Darker red
    description: 'Inaccuracy - Suboptimal move with minor disadvantage',
  ),

  // Blunder (??) - Very bad move causing significant disadvantage
  blunder(
    symbol: '??',
    color: Color(0xFFF44336), // Red
    description: 'Blunder - Very bad move causing significant disadvantage',
  ),

  // Normal move - No special annotation
  normal(
    symbol: '',
    color: Color(0xFFFFFFFF), // White
    description: 'Normal move',
  );

  final String symbol;
  final Color color;
  final String description;

  const MoveImpactType({
    required this.symbol,
    required this.color,
    required this.description,
  });
}

/// Data class containing move impact analysis results
class MoveImpactAnalysis {
  final MoveImpactType impact;
  final double evalChange;
  final double? bestMoveEval;
  final double? actualMoveEval;
  final String? bestMoveSan;
  final String actualMoveSan;
  final int moveIndex;

  const MoveImpactAnalysis({
    required this.impact,
    required this.evalChange,
    this.bestMoveEval,
    this.actualMoveEval,
    this.bestMoveSan,
    required this.actualMoveSan,
    required this.moveIndex,
  });
}

/// Parameters for analyzing all moves from PGN
class PgnAnalysisParams {
  final String pgn;

  const PgnAnalysisParams({
    required this.pgn,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PgnAnalysisParams &&
          runtimeType == other.runtimeType &&
          pgn == other.pgn;

  @override
  int get hashCode => pgn.hashCode;
}

/// Parameters for analyzing moves using positions (fallback when PGN has no evals)
class PositionAnalysisParams {
  final List<String> positionFens;
  final List<String> moveSans;

  const PositionAnalysisParams({
    required this.positionFens,
    required this.moveSans,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionAnalysisParams &&
          runtimeType == other.runtimeType &&
          positionFens.length == other.positionFens.length &&
          moveSans.length == other.moveSans.length;

  @override
  int get hashCode => positionFens.length.hashCode ^ moveSans.length.hashCode;
}

/// Parse evaluations from PGN comments
/// This will run in a worker isolate
List<double?> _parseEvalsFromPgn(String pgn) {
  final List<double?> evals = [];
  int evalCount = 0;

  try {
    final game = PgnGame.parsePgn(pgn);

    // Iterate through mainline moves
    for (final nodeData in game.moves.mainline()) {
      double? evalValue;

      // Check if this move has comments
      if (nodeData.comments != null) {
        // Extract eval if it exists in any comment
        for (String comment in nodeData.comments!) {
          final evalMatch = RegExp(r'\[%eval (-?\d+\.?\d*)\]').firstMatch(comment);
          if (evalMatch != null) {
            final evalStr = evalMatch.group(1);
            if (evalStr != null) {
              evalValue = double.tryParse(evalStr);
              if (evalValue != null) evalCount++;
              break;
            }
          }
        }
      }

      evals.add(evalValue);
    }

    debugPrint('===== Parsed ${evals.length} moves, found $evalCount evaluations in PGN =====');
  } catch (e) {
    debugPrint('Error parsing PGN evaluations: $e');
  }

  return evals;
}

/// Calculate move impact from consecutive evaluations
/// This will run in a worker isolate
MoveImpactAnalysis? _calculateMoveImpactFromEvals({
  required double? evalBefore,
  required double? evalAfter,
  required String actualMoveSan,
  required int moveIndex,
  required bool isWhiteMove,
}) {
  if (evalBefore == null || evalAfter == null) {
    return null;
  }

  try {
    // Evaluations in PGN are from white's perspective
    // Convert to current player's perspective
    final evalBeforeFromPlayerPerspective = isWhiteMove ? evalBefore : -evalBefore;
    final evalAfterFromPlayerPerspective = isWhiteMove ? -evalAfter : evalAfter;

    // Calculate evaluation change (how much worse the position got for the player who moved)
    // Positive evalDiff means the player lost advantage
    final evalDiff = evalBeforeFromPlayerPerspective - evalAfterFromPlayerPerspective;

    // Determine move impact based on evaluation change
    MoveImpactType impact;

    if (evalDiff < -0.5) {
      // Position improved significantly - brilliant or great move
      if (evalDiff < -1.5) {
        impact = MoveImpactType.brilliant;
      } else {
        impact = MoveImpactType.great;
      }
    } else if (evalDiff < 0.3) {
      // Very small change or slight improvement - normal or great
      if (evalDiff < -0.2) {
        impact = MoveImpactType.great;
      } else {
        impact = MoveImpactType.normal;
      }
    } else if (evalDiff < 0.5) {
      // Slight loss - still normal
      impact = MoveImpactType.normal;
    } else if (evalDiff < 1.0) {
      // Missed opportunity
      impact = MoveImpactType.interesting;
    } else if (evalDiff < 2.5) {
      // Clear inaccuracy
      impact = MoveImpactType.inaccuracy;
    } else {
      // Major blunder
      impact = MoveImpactType.blunder;
    }

    return MoveImpactAnalysis(
      impact: impact,
      evalChange: evalDiff,
      bestMoveEval: evalBeforeFromPlayerPerspective,
      actualMoveEval: evalAfterFromPlayerPerspective,
      bestMoveSan: null, // Not available from PGN evaluations
      actualMoveSan: actualMoveSan,
      moveIndex: moveIndex,
    );
  } catch (e) {
    debugPrint('Error calculating move impact from evals: $e');
    return null;
  }
}

/// Memoized provider to generate position FENs from game state
/// Prevents rebuild loop by calculating FENs once and caching
final positionFensProvider = Provider.family<List<String>, PositionFensParams>((ref, params) {
  final List<String> positionFens = [];
  Position currentPos = params.startingPosition ?? Chess.initial;
  positionFens.add(currentPos.fen); // Starting position

  for (Move move in params.allMoves) {
    currentPos = currentPos.play(move);
    positionFens.add(currentPos.fen);
  }

  return positionFens;
});

/// Parameters for position FENs generation
class PositionFensParams {
  final List<Move> allMoves;
  final Position? startingPosition;

  const PositionFensParams({
    required this.allMoves,
    this.startingPosition,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionFensParams &&
          runtimeType == other.runtimeType &&
          allMoves.length == other.allMoves.length;

  @override
  int get hashCode => allMoves.length.hashCode;
}

/// Provider for individual position evaluation - used as fallback when PGN has no evals
/// Uses cascade evaluation: cloud → Supabase → Lichess → Stockfish
final individualPositionEvalProvider = FutureProvider.autoDispose.family<double?, String>((ref, fen) async {
  try {
    // Use the cascade eval provider for this position
    final evalResult = await ref.read(cascadeEvalProviderForBoard(fen).future);

    if (evalResult != null && evalResult.pvs.isNotEmpty) {
      // Get the best line evaluation (first PV)
      final bestPv = evalResult.pvs.first;
      // Convert centipawns to pawns
      return bestPv.cp / 100.0;
    }

    return null;
  } catch (e) {
    debugPrint('Error evaluating position $fen: $e');
    return null;
  }
});

/// Fallback provider that evaluates all positions when PGN has no evaluations
/// Uses individual position evaluation via cascade eval
final allMovesImpactFromPositionsProvider = FutureProvider.family<Map<int, MoveImpactAnalysis>, PositionAnalysisParams>((ref, params) async {
  final Map<int, MoveImpactAnalysis> results = {};

  try {
    debugPrint('===== FALLBACK: Evaluating ${params.positionFens.length} positions individually =====');

    // Create evaluation tasks for all positions
    final List<Future<double?>> evalTasks = [];

    for (String fen in params.positionFens) {
      evalTasks.add(ref.read(individualPositionEvalProvider(fen).future));
    }

    // Wait for all evaluations
    final evals = await Future.wait(evalTasks);

    // Calculate move impacts from position evaluations
    for (int i = 0; i < params.moveSans.length; i++) {
      final evalBefore = i == 0 ? 0.0 : evals[i];
      final evalAfter = i + 1 < evals.length ? evals[i + 1] : null;
      final isWhiteMove = i % 2 == 0;

      if (evalBefore != null && evalAfter != null) {
        final impact = _calculateMoveImpactFromEvals(
          evalBefore: evalBefore,
          evalAfter: evalAfter,
          actualMoveSan: params.moveSans[i],
          moveIndex: i,
          isWhiteMove: isWhiteMove,
        );

        if (impact != null) {
          results[i] = impact;
        }
      }
    }

    debugPrint('===== FALLBACK: Analyzed ${results.length} moves using individual positions =====');
    return results;
  } catch (e) {
    debugPrint('Error in allMovesImpactFromPositionsProvider: $e');
    return results;
  }
});

/// Provider to analyze ALL moves from PGN in parallel using worker isolates
/// This parses evaluations from PGN comments and calculates move impacts
final allMovesImpactFromPgnProvider = FutureProvider.family<Map<int, MoveImpactAnalysis>, PgnAnalysisParams>((ref, params) async {
  final Map<int, MoveImpactAnalysis> results = {};

  try {
    // Parse all evaluations from PGN in a worker isolate
    final evals = await workerManager.execute<List<double?>>(
      () => _parseEvalsFromPgn(params.pgn),
      priority: WorkPriority.high,
    );

    if (evals.isEmpty) {
      debugPrint('===== No evaluations found in PGN, cannot analyze move impacts =====');
      return results;
    }

    // Count how many evaluations we actually have
    final evalCount = evals.where((e) => e != null).length;
    debugPrint('===== PGN has $evalCount evaluations out of ${evals.length} moves =====');

    // If we don't have enough evaluations, return empty results
    if (evalCount < 2) {
      debugPrint('===== Not enough evaluations to analyze move impacts =====');
      return results;
    }

    // Parse move SANs from PGN to get move text
    List<String> moveSans = [];
    try {
      final game = PgnGame.parsePgn(params.pgn);
      for (final nodeData in game.moves.mainline()) {
        moveSans.add(nodeData.san);
      }
    } catch (e) {
      debugPrint('Error parsing PGN moves: $e');
      return results;
    }

    // Create list of all move analysis tasks
    final List<Future<MoveImpactAnalysis?>> tasks = [];

    // We need position BEFORE and AFTER each move
    // For move at index i:
    // - evalBefore is at index i (evaluation before the move)
    // - evalAfter is at index i (evaluation after the move, before next move)
    // Actually, PGN evals are AFTER the move, so:
    // - For move i: eval[i-1] is before, eval[i] is after

    for (int i = 0; i < moveSans.length; i++) {
      final evalBefore = i == 0 ? 0.0 : evals[i - 1]; // Starting position is 0.0
      final evalAfter = evals[i];
      final isWhiteMove = i % 2 == 0;

      // Skip if we don't have evaluation data for this move
      if (evalAfter == null) {
        tasks.add(Future.value(null));
        continue;
      }

      // Execute move impact calculation in worker isolate
      tasks.add(
        workerManager.execute<MoveImpactAnalysis?>(
          () => _calculateMoveImpactFromEvals(
            evalBefore: evalBefore,
            evalAfter: evalAfter,
            actualMoveSan: moveSans[i],
            moveIndex: i,
            isWhiteMove: isWhiteMove,
          ),
          priority: WorkPriority.high,
        ),
      );
    }

    // Wait for all calculations to complete
    final evaluations = await Future.wait(tasks);

    // Build results map
    int analyzedCount = 0;
    for (int i = 0; i < evaluations.length; i++) {
      if (evaluations[i] != null) {
        results[i] = evaluations[i]!;
        analyzedCount++;
      }
    }

    debugPrint('===== Successfully analyzed $analyzedCount moves =====');
    return results;
  } catch (e) {
    debugPrint('Error in allMovesImpactFromPgnProvider: $e');
    return results;
  }
});
