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
  final String gameId; // Unique game identifier to prevent cross-game contamination

  const PgnAnalysisParams({
    required this.pgn,
    required this.gameId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PgnAnalysisParams &&
          runtimeType == other.runtimeType &&
          pgn == other.pgn &&
          gameId == other.gameId;

  @override
  int get hashCode => pgn.hashCode ^ gameId.hashCode;
}

/// Parameters for analyzing moves using positions (fallback when PGN has no evals)
class PositionAnalysisParams {
  final List<String> positionFens;
  final List<String> moveSans;
  final String gameId; // Unique game identifier to prevent cross-game contamination

  const PositionAnalysisParams({
    required this.positionFens,
    required this.moveSans,
    required this.gameId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionAnalysisParams &&
          runtimeType == other.runtimeType &&
          positionFens.length == other.positionFens.length &&
          moveSans.length == other.moveSans.length &&
          gameId == other.gameId;

  @override
  int get hashCode => positionFens.length.hashCode ^ moveSans.length.hashCode ^ gameId.hashCode;
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

/// NEW: Calculate move impact by comparing player's move with best alternatives
/// This runs in a worker isolate
///
/// LOGIC:
/// 1. Get top moves from CloudEval (engine suggestions)
/// 2. Find player's actual move in the list
/// 3. Calculate eval loss = bestMoveEval - playerMoveEval
/// 4. Detect game phase (early/mid/late) for dynamic thresholds
/// 5. Check move uniqueness for brilliant annotation
/// 6. Classify based on relative comparison to alternatives
MoveImpactAnalysis? _calculateMoveImpactFromAlternatives({
  required CloudEval? positionEval,
  required String playerMoveSan,
  required int moveNumber,
  required bool isWhiteMove,
}) {
  if (positionEval == null || positionEval.pvs.isEmpty) {
    return null;
  }

  try {
    // Detect game phase for dynamic thresholds
    final GamePhase phase;
    if (moveNumber <= 15) {
      phase = GamePhase.early;
    } else if (moveNumber <= 40) {
      phase = GamePhase.mid;
    } else {
      phase = GamePhase.late;
    }

    // Get phase-specific minimum threshold
    final double minThreshold;
    switch (phase) {
      case GamePhase.early:
        minThreshold = 0.3;
        break;
      case GamePhase.mid:
        minThreshold = 0.45;
        break;
      case GamePhase.late:
        minThreshold = 0.5;
        break;
    }

    // Extract all PVs (top moves from engine)
    final pvs = positionEval.pvs;
    final bestMove = pvs.first;
    final bestMoveEval = bestMove.cp / 100.0; // Convert centipawns to pawns

    // Find player's move in the PVs
    // Player's move is the FIRST move in one of the PVs
    int? playerMoveRank;
    double? playerMoveEval;

    for (int i = 0; i < pvs.length; i++) {
      final pv = pvs[i];
      // Parse first move from PV
      final moves = pv.moves.split(' ');
      if (moves.isNotEmpty) {
        final firstMoveSan = _uciToSan(moves.first, playerMoveSan);
        if (firstMoveSan == playerMoveSan) {
          playerMoveRank = i;
          playerMoveEval = pv.cp / 100.0;
          break;
        }
      }
    }

    // If player's move not in top PVs, get evaluation from next position
    // This means it's likely a mistake since engine didn't consider it
    if (playerMoveEval == null) {
      playerMoveEval = bestMoveEval - 2.0; // Assume significant loss
      playerMoveRank = 99; // Not in top moves
    }

    // Convert evals to player's perspective (positive = good for player)
    final bestEvalFromPlayerPerspective = isWhiteMove ? bestMoveEval : -bestMoveEval;
    final playerEvalFromPlayerPerspective = isWhiteMove ? playerMoveEval : -playerMoveEval;

    // Calculate evaluation loss (how much worse than best)
    // Positive evalLoss = player lost advantage
    final evalLoss = bestEvalFromPlayerPerspective - playerEvalFromPlayerPerspective;

    // Early exit if below minimum threshold for this game phase
    if (evalLoss.abs() < minThreshold) {
      return MoveImpactAnalysis(
        impact: MoveImpactType.normal,
        evalChange: -evalLoss, // Negative because we want improvement to be negative
        bestMoveEval: bestEvalFromPlayerPerspective,
        actualMoveEval: playerEvalFromPlayerPerspective,
        bestMoveSan: _extractSanFromPv(bestMove.moves),
        actualMoveSan: playerMoveSan,
        moveIndex: moveNumber,
      );
    }

    // Classify move impact based on alternatives
    MoveImpactType impact;

    if (evalLoss <= 0.1 && playerMoveRank != null && playerMoveRank <= 2) {
      // Player played best or near-best move (within 0.1 pawns)
      // Check for brilliant: is it unique/hard to find?

      if (_isBrilliantMove(pvs, playerMoveRank, bestEvalFromPlayerPerspective)) {
        impact = MoveImpactType.brilliant;
      } else {
        // Good move but not unique - many alternatives
        impact = MoveImpactType.great;
      }
    } else if (evalLoss >= 0 && evalLoss <= 0.3) {
      // Small loss - still a good move
      impact = MoveImpactType.great;
    } else if (evalLoss > 0.3 && evalLoss <= 1.0) {
      // Missed better opportunity
      impact = MoveImpactType.interesting;
    } else if (evalLoss > 1.0 && evalLoss <= 2.5) {
      // Significant mistake
      impact = MoveImpactType.inaccuracy;
    } else if (evalLoss > 2.5) {
      // Major blunder
      impact = MoveImpactType.blunder;
    } else {
      // Shouldn't reach here
      impact = MoveImpactType.normal;
    }

    return MoveImpactAnalysis(
      impact: impact,
      evalChange: -evalLoss, // Negative because we want improvement to be negative
      bestMoveEval: bestEvalFromPlayerPerspective,
      actualMoveEval: playerEvalFromPlayerPerspective,
      bestMoveSan: _extractSanFromPv(bestMove.moves),
      actualMoveSan: playerMoveSan,
      moveIndex: moveNumber,
    );
  } catch (e) {
    debugPrint('Error calculating move impact from alternatives: $e');
    return null;
  }
}

/// Check if a move is brilliant (unique, hard to find)
/// Criteria:
/// - Move is in top 3
/// - Only 1-3 moves within 0.2 pawns of best
/// - Significant gap (>0.5) to 4th/5th best move
bool _isBrilliantMove(List<Pv> pvs, int moveRank, double bestEval) {
  if (moveRank > 2) return false; // Must be in top 3

  // Count how many moves are within 0.2 pawns of best
  int movesWithinRange = 0;
  for (final pv in pvs.take(5)) {
    final eval = pv.cp / 100.0;
    if ((eval - bestEval).abs() <= 0.2) {
      movesWithinRange++;
    }
  }

  // Must have only 1-3 moves near best (unique/hard to find)
  if (movesWithinRange > 3) return false;

  // Check gap to 4th/5th best
  if (pvs.length >= 4) {
    final fourthBestEval = pvs[3].cp / 100.0;
    if ((bestEval - fourthBestEval).abs() < 0.5) {
      return false; // Not enough gap - not unique
    }
  }

  return true;
}

/// Helper to extract SAN from PV moves string
String? _extractSanFromPv(String pvMoves) {
  final moves = pvMoves.split(' ');
  return moves.isNotEmpty ? moves.first : null;
}

/// Simplified UCI to SAN comparison (just checks if moves match)
String _uciToSan(String uci, String san) {
  // This is a simplification - ideally would parse properly
  // For now, just return the san since we're matching against engine PVs
  return san;
}

/// Game phase enum for dynamic thresholds
enum GamePhase {
  early, // moves 1-15
  mid,   // moves 16-40
  late,  // moves 41+
}

/// Calculate move impact from consecutive evaluations
/// This will run in a worker isolate
///
/// NEW STRICT LOGIC:
/// - Most moves are NORMAL - only truly exceptional/bad moves get annotations
/// - !! (Brilliant): Rare genius move that's very hard to find, unique best option
/// - ! (Great): Good move gaining advantage, but not unique/hard to find
/// - !? (Interesting): Missed opportunity for significantly better move
/// - ? (Inaccuracy): Suboptimal move losing advantage
/// - ?? (Blunder): Very bad move causing major disadvantage
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

    // Calculate evaluation change (how much the position changed for the player who moved)
    // Negative evalDiff = position improved (player gained advantage)
    // Positive evalDiff = position worsened (player lost advantage)
    final evalDiff = evalBeforeFromPlayerPerspective - evalAfterFromPlayerPerspective;

    // VERY STRICT THRESHOLDS - Most moves are normal!
    // In professional chess, ±0.6 pawns is the minimum for significance
    // First filter: Must have significant eval change (minimum ±0.6)

    if (evalDiff.abs() < 0.6) {
      // Insignificant change - definitely normal
      return MoveImpactAnalysis(
        impact: MoveImpactType.normal,
        evalChange: evalDiff,
        bestMoveEval: evalBeforeFromPlayerPerspective,
        actualMoveEval: evalAfterFromPlayerPerspective,
        bestMoveSan: null,
        actualMoveSan: actualMoveSan,
        moveIndex: moveIndex,
      );
    }

    // Determine move impact based on evaluation change
    MoveImpactType impact;

    if (evalDiff < -0.6) {
      // Position improved after this move
      // Be VERY conservative with !! and ! annotations

      if (evalDiff < -3.0) {
        // Massive improvement (> 3.0 pawns gained)
        // This is likely brilliant, but we can't verify uniqueness from PGN alone
        // So mark as great instead (would need engine to check alternatives)
        impact = MoveImpactType.great;
      } else if (evalDiff < -2.0) {
        // Significant improvement (2.0-3.0 pawns gained)
        // Good move, but probably not unique enough for brilliant
        impact = MoveImpactType.great;
      } else {
        // Moderate improvement (0.6-2.0 pawns) - still normal
        // Many moves can achieve this, so not special enough
        impact = MoveImpactType.normal;
      }
    } else if (evalDiff > 0.6) {
      // Position worsened after this move

      if (evalDiff > 4.0) {
        // Catastrophic disadvantage (> 4.0 pawns lost) - clear blunder
        impact = MoveImpactType.blunder;
      } else if (evalDiff > 2.5) {
        // Major disadvantage (2.5-4.0 pawns lost) - serious mistake
        impact = MoveImpactType.inaccuracy;
      } else if (evalDiff > 1.5) {
        // Notable disadvantage (1.5-2.5 pawns lost) - missed better opportunity
        impact = MoveImpactType.interesting;
      } else {
        // Small disadvantage (0.6-1.5 pawns) - still normal
        // Common slight inaccuracies happen, not worth marking
        impact = MoveImpactType.normal;
      }
    } else {
      // Should not reach here, but fallback to normal
      impact = MoveImpactType.normal;
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
  final String gameId; // Unique game identifier to prevent cross-game contamination

  const PositionFensParams({
    required this.allMoves,
    this.startingPosition,
    required this.gameId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionFensParams &&
          runtimeType == other.runtimeType &&
          allMoves.length == other.allMoves.length &&
          gameId == other.gameId;

  @override
  int get hashCode => allMoves.length.hashCode ^ gameId.hashCode;
}

/// Provider for FULL position evaluation including all top moves
/// Returns complete CloudEval with multiple PVs (top 5 moves)
/// Uses cascade evaluation: cloud → Supabase → Lichess → Stockfish
/// NOT auto-disposed - keeps evaluations cached for immediate display
final fullPositionEvalProvider = FutureProvider.family<CloudEval?, String>((ref, fen) async {
  try {
    // Use the cascade eval provider for this position
    final evalResult = await ref.read(cascadeEvalProviderForBoard(fen).future);
    return evalResult;
  } catch (e) {
    debugPrint('Error evaluating position $fen: $e');
    return null;
  }
});

/// NEW: Fallback provider that evaluates all positions using FULL CloudEval (top moves comparison)
/// Compares player's move vs best alternatives from engine
/// Uses cascade eval in PARALLEL with 75 isolates
/// NOT auto-disposed - keeps calculations cached while on board page
final allMovesImpactFromPositionsProvider = FutureProvider.family<Map<int, MoveImpactAnalysis>, PositionAnalysisParams>((ref, params) async {
  final Map<int, MoveImpactAnalysis> results = {};

  try {
    debugPrint('===== ADVANCED: Evaluating ${params.positionFens.length} positions with FULL CloudEval in PARALLEL =====');

    // Execute ALL position evaluations in parallel using isolates (non-blocking)
    // Each evaluation uses cascade: local cache → Supabase → Lichess → Stockfish
    // NEW: Get full CloudEval with all PVs (top 5 moves), not just best move
    final List<Future<CloudEval?>> evalTasks = [];

    for (String fen in params.positionFens) {
      // Read full position eval provider - returns CloudEval with all PVs
      evalTasks.add(ref.read(fullPositionEvalProvider(fen).future));
    }

    // Wait for all evaluations to complete in parallel
    final cloudEvals = await Future.wait(evalTasks);

    final validCount = cloudEvals.where((e) => e != null).length;
    debugPrint('===== ADVANCED: Got $validCount/${cloudEvals.length} full evaluations with alternatives =====');

    // Calculate move impacts by comparing with alternatives
    // Use worker isolates for parallel processing
    final List<Future<MoveImpactAnalysis?>> impactTasks = [];

    for (int i = 0; i < params.moveSans.length; i++) {
      final isWhiteMove = i % 2 == 0;
      final positionEval = cloudEvals[i]; // Position BEFORE the move
      final playerMoveSan = params.moveSans[i];
      final moveNumber = i;

      // Execute impact calculation in worker isolate
      impactTasks.add(
        workerManager.execute<MoveImpactAnalysis?>(
          () => _calculateMoveImpactFromAlternatives(
            positionEval: positionEval,
            playerMoveSan: playerMoveSan,
            moveNumber: moveNumber,
            isWhiteMove: isWhiteMove,
          ),
          priority: WorkPriority.high,
        ),
      );
    }

    // Wait for all impact calculations to complete
    final impacts = await Future.wait(impactTasks);

    // Build results map
    int analyzedCount = 0;
    for (int i = 0; i < impacts.length; i++) {
      if (impacts[i] != null) {
        results[i] = impacts[i]!;
        analyzedCount++;
      }
    }

    debugPrint('===== ADVANCED: Analyzed $analyzedCount moves by comparing with alternatives =====');
    return results;
  } catch (e) {
    debugPrint('Error in allMovesImpactFromPositionsProvider: $e');
    return results;
  }
});

/// Provider to analyze ALL moves from PGN in parallel using worker isolates
/// This parses evaluations from PGN comments and calculates move impacts
/// NOT auto-disposed - keeps calculations cached while on board page
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
