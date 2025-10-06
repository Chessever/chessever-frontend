import 'dart:math' as math;
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

/// BULLETPROOF Move Impact Analysis - Understanding Chess Engine Evaluation
///
/// THE CRITICAL CHESS INSIGHT:
/// ===========================
/// When opponent blunders, the engine IMMEDIATELY shows you're winning (+3.5)
/// This evaluation ASSUMES you'll find the best move.
///
/// Example after opponent's blunder:
/// - Position eval: +3.5 (engine assumes you'll find best move to keep this)
/// - If you play best move: +3.5 → +3.5 (NORMAL - you preserved it, didn't "gain" it)
/// - If you play 2nd best:  +3.5 → +2.8 (MISTAKE - lost 0.7 pawns)
/// - If you play blunder:   +3.5 → +0.5 (BLUNDER - threw away 3.0 pawns)
///
/// YOU CANNOT GAIN ADVANTAGE THAT THE ENGINE ALREADY GAVE YOU!
/// The +3.5 eval means "this position IS +3.5 if best moves are played"
///
/// CORRECT IMPACT CALCULATION:
/// ===========================
/// 1. BRILLIANT/GREAT: Ignore position change! Only look at:
///    - Is this the objectively best move in THIS position?
///    - Is it unique (few alternatives)?
///    - Is it tactical/sacrificial?
///
/// 2. BLUNDER/MISTAKE: Compare move to alternatives:
///    - How much worse is played move vs best available?
///    - Alternatives gap = bestEval - playedMoveEval (in THIS position)
///
/// 3. NORMAL: Everything else (95%+ of moves)
///
/// EXAMPLES:
/// =========
/// Scenario: Opponent blundered, position is +3.5 for you
/// - Best move keeps +3.5 → NORMAL (preserved advantage, not gained)
/// - 2nd best gets +2.8 (gap 0.7) → MISTAKE (failed to preserve)
/// - Blunder gets +1.0 (gap 2.5) → BLUNDER (threw away win)
///
/// Scenario: Equal position (0.0)
/// - Best move gets +1.5 → GREAT! (actually gained advantage)
/// - Your move gets +1.3 (gap 0.2) → NORMAL (close to best)
/// - Your move gets -0.5 (gap 2.0) → BLUNDER (turned advantage into disadvantage)
MoveImpactAnalysis? _calculateMoveImpactFromAlternatives({
  required CloudEval? positionEvalBeforeMove,
  required CloudEval? positionEvalAfterMove,
  required String playerMoveSan,
  required int moveNumber,
  required bool isWhiteMove,
}) {
  if (positionEvalBeforeMove == null || positionEvalBeforeMove.pvs.isEmpty) {
    return null;
  }

  try {
    final pvs = positionEvalBeforeMove.pvs;
    final bestPv = pvs[0];

    // Parse the position FEN to get dartchess Position for UCI→SAN conversion
    final positionBeforeMove = Position.setupPosition(Rule.chess, Setup.parseFen(positionEvalBeforeMove.fen));

    // === STEP 1: Find player's move in engine alternatives ===
    int? playerMoveRank;
    int? playerMoveResultingCp;

    for (int i = 0; i < pvs.length; i++) {
      final pv = pvs[i];
      final moves = pv.moves.split(' ');
      if (moves.isNotEmpty) {
        // Convert UCI to SAN using the position BEFORE the move
        final firstMoveSan = _uciToSan(moves.first, positionBeforeMove);
        if (firstMoveSan != null && firstMoveSan == playerMoveSan) {
          playerMoveRank = i;
          playerMoveResultingCp = pv.cp;
          debugPrint('   ✓ Move match: "$playerMoveSan" found at rank $i (cp=${pv.cp})');
          break;
        }
      }
    }

    // Debug: Show what we're comparing if no match
    if (playerMoveRank == null) {
      debugPrint('   ⚠️ Move "$playerMoveSan" NOT found in engine PVs:');
      for (int i = 0; i < pvs.length && i < 3; i++) {
        final moves = pvs[i].moves.split(' ');
        if (moves.isNotEmpty) {
          final san = _uciToSan(moves.first, positionBeforeMove);
          debugPrint('      PV[$i]: $san (UCI: ${moves.first})');
        }
      }
    }

    // If not found in engine PVs, player made a move outside top alternatives
    if (playerMoveResultingCp == null) {
      playerMoveRank = 99;
      // Use position AFTER the move to calculate actual eval
      if (positionEvalAfterMove != null && positionEvalAfterMove.pvs.isNotEmpty) {
        playerMoveResultingCp = positionEvalAfterMove.pvs[0].cp;
      } else {
        // Fallback: estimate penalty
        final bestResultCp = bestPv.cp;
        playerMoveResultingCp = isWhiteMove ? bestResultCp - 200 : bestResultCp + 200;
      }
    }

    final bestResultingCp = bestPv.cp;

    // === STEP 2: Calculate eval from player's perspective ===
    final bestResultPlayer = isWhiteMove ? bestResultingCp : -bestResultingCp;
    final actualResultPlayer = isWhiteMove ? playerMoveResultingCp : -playerMoveResultingCp;

    playerMoveRank ??= pvs.length;

    // Perspective conversions for probability metrics
    final wpBest = _cpToWinProb(bestResultPlayer);
    final wpActual = _cpToWinProb(actualResultPlayer);
    final winProbLoss = (wpBest - wpActual).clamp(-1.0, 1.0);
    final winProbGain = (wpActual - wpBest).clamp(-1.0, 1.0);

    // Centipawn gap remains informative for UI (positive ⇒ worse than best)
    final alternativesGap = bestResultPlayer - actualResultPlayer;

    final phase = _detectGamePhase(positionEvalBeforeMove.fen);
    final nearBestCount = _countNearBestMoves(pvs);
    final decided = _isDecidedPosition(bestResultingCp);
    final actualDecided = _isDecidedPosition(actualResultPlayer);
    final outcomeFlipAgainstPlayer = _flipsOutcomeClass(bestResultPlayer, actualResultPlayer);
    final bool lowConfidence = positionEvalBeforeMove.depth < 12 || positionEvalBeforeMove.knodes < 80;

    final thresholds = _phaseThresholdsMap[phase]!;
    final blunderThreshold = thresholds.blunder + _advantageBuffer(bestResultPlayer, factor: 0.05);
    final inaccuracyThreshold = thresholds.inaccuracy + _advantageBuffer(bestResultPlayer, factor: 0.02);
    final interestingThreshold = thresholds.interesting + _advantageBuffer(bestResultPlayer, factor: 0.01);
    final positiveGainThreshold = math.max(0.04, thresholds.great / 2);

    final bool bothDecidedSame = decided && actualDecided &&
        (bestResultPlayer == 0 || actualResultPlayer == 0 || bestResultPlayer.sign == actualResultPlayer.sign);
    final AdvantageTier bestTier = _advantageTier(bestResultPlayer);
    final AdvantageTier actualTier = _advantageTier(actualResultPlayer);
    final bool bestInDrawBand = _inDrawBand(bestResultPlayer);
    final bool actualInDrawBand = _inDrawBand(actualResultPlayer);
    final bool drawBandCrossAgainstPlayer = bestInDrawBand && !actualInDrawBand && actualResultPlayer < 0;
    final bool gaveAwayWin = _gaveAwayWin(bestResultPlayer, actualResultPlayer);
    final bool handedOverAdvantage = _handedOverAdvantage(bestResultPlayer, actualResultPlayer);
    final bool severeSignFlip = (bestResultPlayer > 0 && actualResultPlayer < 0) ||
        (bestResultPlayer < 0 && actualResultPlayer > 0);
    final bool stillClearlyWinning = bestTier == AdvantageTier.winning && actualTier == AdvantageTier.winning;
    final int cpLoss = bestResultPlayer - actualResultPlayer;
    final bool subtleDrawLeak = drawBandCrossAgainstPlayer && winProbLoss >= 0.03;
    final bool bigDropInWonGame = stillClearlyWinning && cpLoss >= 320;

    final double adjustedBlunderThreshold = bothDecidedSame ? math.max(blunderThreshold, 0.6) : blunderThreshold;
    final double adjustedInaccuracyThreshold = bothDecidedSame ? math.max(inaccuracyThreshold, 0.12) : inaccuracyThreshold;

    MoveImpactType impact = MoveImpactType.normal;

    final bool playerHadMate = bestResultPlayer >= 100000;
    final bool playerFoundMate = actualResultPlayer >= 100000;
    final bool opponentHadMateThreat = bestResultPlayer <= -100000;
    final bool playerWalkedIntoMate = actualResultPlayer <= -100000;

    if ((playerHadMate && !playerFoundMate) || (opponentHadMateThreat && playerWalkedIntoMate)) {
      impact = MoveImpactType.blunder;
    }

    if (impact == MoveImpactType.normal) {
      final bool qualifiesBlunder = winProbLoss >= adjustedBlunderThreshold ||
          outcomeFlipAgainstPlayer ||
          handedOverAdvantage ||
          gaveAwayWin ||
          drawBandCrossAgainstPlayer ||
          (severeSignFlip && actualResultPlayer.abs() >= 150);

      if (qualifiesBlunder) {
        impact = MoveImpactType.blunder;
      } else {
        final bool qualifiesInaccuracy = (!stillClearlyWinning &&
                ((winProbLoss >= adjustedInaccuracyThreshold && (cpLoss >= 80 || winProbLoss >= 0.12)) ||
                    subtleDrawLeak ||
                    cpLoss >= 180)) ||
            bigDropInWonGame;

        if (qualifiesInaccuracy) {
          impact = MoveImpactType.inaccuracy;
        }
      }
    }

    if (impact == MoveImpactType.normal) {
      final bool candidateInteresting = playerMoveRank >= 2 && playerMoveRank <= 4;
      final double interestingLowerBound = math.max(0.04, interestingThreshold);
      final bool interestingBand = winProbLoss >= interestingLowerBound && winProbLoss < adjustedInaccuracyThreshold;
      final bool cpTension = cpLoss >= 120 && _inDrawBand(bestResultPlayer);

      if (!bothDecidedSame && !decided && candidateInteresting && nearBestCount <= 3 &&
          (interestingBand || cpTension)) {
        impact = MoveImpactType.interesting;
      }
    }

    if (impact == MoveImpactType.normal) {
      final gapToSecond = pvs.length > 1 ? (bestResultingCp - pvs[1].cp).abs() : 0;
      final gapToThird = pvs.length > 2 ? (bestResultingCp - pvs[2].cp).abs() : 0;
      final bool uniqueBest = nearBestCount <= 1 && gapToSecond >= 60;
      final bool clearGap = gapToSecond >= 80 || gapToThird >= 120;
      final bool tactical = _isSacrifice(
            moveSan: playerMoveSan,
            cpBefore: bestResultPlayer,
            cpAfter: actualResultPlayer,
          ) ||
          _isQuietTactical(
            moveSan: playerMoveSan,
            evalSwing: alternativesGap,
          );

      if (playerMoveRank == 0 && !decided && !bothDecidedSame && pvs.length >= 3 && nearBestCount <= 2) {
        final bool preservesEval = winProbLoss <= 0.01;
        if (uniqueBest && tactical && preservesEval && !lowConfidence) {
          impact = MoveImpactType.brilliant;
        } else if ((uniqueBest || clearGap) && preservesEval && !lowConfidence) {
          impact = MoveImpactType.great;
        }
      } else if (playerMoveRank == 0 && clearGap && !lowConfidence && pvs.length >= 3 &&
          winProbGain >= positiveGainThreshold && !decided && !bothDecidedSame) {
        impact = MoveImpactType.great;
      }
    }

    if ((decided || bothDecidedSame) && impact == MoveImpactType.great) {
      impact = MoveImpactType.normal;
    }
    if ((decided || bothDecidedSame) && impact == MoveImpactType.brilliant) {
      impact = MoveImpactType.great;
    }

    return MoveImpactAnalysis(
      impact: impact,
      evalChange: alternativesGap / 100.0,  // Eval difference in pawns
      bestMoveEval: bestResultPlayer / 100.0,
      actualMoveEval: actualResultPlayer / 100.0,
      bestMoveSan: bestPv.moves.isNotEmpty
          ? (_uciToSan(bestPv.moves.split(' ').first, positionBeforeMove) ??
              _extractSanFromPv(bestPv.moves))
          : null,
      actualMoveSan: playerMoveSan,
      moveIndex: moveNumber,
    );
  } catch (e) {
    debugPrint('Error calculating move impact from alternatives: $e');
    return null;
  }
}

MoveImpactAnalysis? calculateMoveImpact({
  required CloudEval? positionEvalBeforeMove,
  required CloudEval? positionEvalAfterMove,
  required String playerMoveSan,
  required int moveNumber,
  required bool isWhiteMove,
}) {
  return _calculateMoveImpactFromAlternatives(
    positionEvalBeforeMove: positionEvalBeforeMove,
    positionEvalAfterMove: positionEvalAfterMove,
    playerMoveSan: playerMoveSan,
    moveNumber: moveNumber,
    isWhiteMove: isWhiteMove,
  );
}

/// Helper to extract SAN from PV moves string
String? _extractSanFromPv(String pvMoves) {
  final moves = pvMoves.split(' ');
  return moves.isNotEmpty ? moves.first : null;
}

/// Convert UCI move notation to SAN using dartchess Position
/// This is critical for comparing player's move against engine PVs
String? _uciToSan(String uci, Position position) {
  try {
    // Parse UCI move (e.g., "e2e4" or "e7e8q" for promotion)
    if (uci.length < 4) return null;

    final fromSquare = uci.substring(0, 2);
    final toSquare = uci.substring(2, 4);
    final promotion = uci.length > 4 ? uci[4] : null;

    // Convert square names to Square objects
    final from = Square.fromName(fromSquare);
    final to = Square.fromName(toSquare);

    // Create the move
    Move? move;
    if (promotion != null) {
      // Handle pawn promotion
      Role? promotionRole;
      switch (promotion.toLowerCase()) {
        case 'q':
          promotionRole = Role.queen;
          break;
        case 'r':
          promotionRole = Role.rook;
          break;
        case 'b':
          promotionRole = Role.bishop;
          break;
        case 'n':
          promotionRole = Role.knight;
          break;
        default:
          return null;
      }
      move = NormalMove(from: from, to: to, promotion: promotionRole);
    } else {
      move = NormalMove(from: from, to: to);
    }

    // Convert to SAN using dartchess - makeSan returns (Position, String) tuple
    final result = position.makeSan(move);
    return result.$2; // Return just the SAN string
  } catch (e) {
    debugPrint('❌ ERROR converting UCI "$uci" to SAN: $e');
    return null;
  }
}

/// Game phase enum for dynamic thresholds
enum GamePhase {
  opening,
  middlegame,
  endgame,
}

enum AdvantageTier {
  equal,
  slight,
  winning,
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
/// DEPRECATED: This function cannot properly classify moves from PGN evaluations alone
///
/// WHY THIS FUNCTION IS WRONG:
/// ==========================
/// PGN only contains evaluations before/after moves, NOT alternative move evaluations.
/// According to correct chess engine understanding:
/// - Engine evals ASSUME best moves will be played
/// - After opponent blunders to +3.5, playing best move to keep +3.5 is NORMAL (not brilliant!)
/// - You cannot "gain" advantage the engine already gave you
/// - Move quality MUST be judged by comparing alternatives in THAT position
///
/// WHAT THIS MEANS:
/// ===============
/// Without alternative move data, we cannot know if:
/// - The played move was the ONLY good move (brilliant/great)
/// - There were 10 other moves just as good (normal)
/// - Position change is IRRELEVANT for positive annotations
///
/// SOLUTION:
/// ========
/// This function now returns NORMAL for all moves with PGN data.
/// The position-based provider (_calculateMoveImpactFromAlternatives) has the
/// alternative move data needed for proper classification.
///
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
    // Convert to current player's perspective for display purposes only
    final evalBeforeFromPlayerPerspective = isWhiteMove ? evalBefore : -evalBefore;
    final evalAfterFromPlayerPerspective = isWhiteMove ? -evalAfter : evalAfter;

    // Calculate evaluation change for informational purposes
    final evalDiff = evalBeforeFromPlayerPerspective - evalAfterFromPlayerPerspective;

    // ALWAYS return NORMAL - we cannot properly classify without alternatives
    // The position-based provider will handle actual classification
    return MoveImpactAnalysis(
      impact: MoveImpactType.normal,
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

/// Provider that watches ONLY game moves and provides impact analysis
/// This isolates impact calculation from frequent state changes (analysis mode, current move, etc.)
/// Only depends on game ID - internally extracts moves from a game-specific source
/// Must be overridden per-game to provide actual moves data
final gameMoveImpactsProvider = FutureProvider.family.autoDispose<Map<int, MoveImpactAnalysis>?, String>((ref, gameId) async {
  // NOTE: This provider should be overridden in each screen that needs impact analysis
  // For now, return null to avoid errors
  // The screen must provide a provider that returns PositionAnalysisParams for the given gameId
  return null;
});

/// NEW: Fallback provider that evaluates all positions using FULL CloudEval (top moves comparison)
/// Compares player's move vs best alternatives from engine
/// Uses cascade eval in PARALLEL with 75 isolates
/// NOT auto-disposed - keeps calculations cached while on board page
final allMovesImpactFromPositionsProvider = FutureProvider.family<Map<int, MoveImpactAnalysis>, PositionAnalysisParams>((ref, params) async {
  final Map<int, MoveImpactAnalysis> results = {};

  try {
    debugPrint('🎨🎨🎨 MOVE IMPACT: Starting analysis for game ${params.gameId}');
    debugPrint('🎨 MOVE IMPACT: ${params.positionFens.length} positions, ${params.moveSans.length} moves');

    // Execute ALL position evaluations in parallel using isolates (non-blocking)
    // Each evaluation uses cascade: local cache → Supabase → Lichess → Stockfish
    // NEW: Get full CloudEval with all PVs (top 5 moves), not just best move
    final List<Future<CloudEval?>> evalTasks = [];

    for (String fen in params.positionFens) {
      // Read full position eval provider - returns CloudEval with all PVs
      // Add timeout to prevent hanging indefinitely
      final evalFuture = ref.read(fullPositionEvalProvider(fen).future)
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            debugPrint('⏱️ TIMEOUT evaluating position: ${fen.substring(0, 30)}...');
            return null;
          },
        );
      evalTasks.add(evalFuture);
    }

    // Wait for all evaluations to complete in parallel (with timeouts)
    final cloudEvals = await Future.wait(evalTasks, eagerError: false);

    final validCount = cloudEvals.where((e) => e != null).length;
    debugPrint('===== ADVANCED: Got $validCount/${cloudEvals.length} full evaluations with alternatives =====');

    // Calculate move impacts by comparing with alternatives
    // Use worker isolates for parallel processing
    final List<Future<MoveImpactAnalysis?>> impactTasks = [];

    for (int i = 0; i < params.moveSans.length; i++) {
      final isWhiteMove = i % 2 == 0;
      final positionEvalBefore = cloudEvals[i]; // Position BEFORE the move
      final positionEvalAfter = i + 1 < cloudEvals.length ? cloudEvals[i + 1] : null; // Position AFTER the move
      final playerMoveSan = params.moveSans[i];
      final moveNumber = i;

      // Execute impact calculation in worker isolate
      impactTasks.add(
        workerManager.execute<MoveImpactAnalysis?>(
          () => _calculateMoveImpactFromAlternatives(
            positionEvalBeforeMove: positionEvalBefore,
            positionEvalAfterMove: positionEvalAfter,
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
    int brilliantCount = 0, greatCount = 0, interestingCount = 0, inaccuracyCount = 0, blunderCount = 0;

    for (int i = 0; i < impacts.length; i++) {
      if (impacts[i] != null) {
        results[i] = impacts[i]!;
        analyzedCount++;

        // Count impact types
        switch (impacts[i]!.impact) {
          case MoveImpactType.brilliant:
            brilliantCount++;
            debugPrint('🎨 !! BRILLIANT move $i: ${params.moveSans[i]}');
            break;
          case MoveImpactType.great:
            greatCount++;
            debugPrint('🎨 ! GREAT move $i: ${params.moveSans[i]}');
            break;
          case MoveImpactType.interesting:
            interestingCount++;
            debugPrint('🎨 !? INTERESTING move $i: ${params.moveSans[i]}');
            break;
          case MoveImpactType.inaccuracy:
            inaccuracyCount++;
            debugPrint('🎨 ? INACCURACY move $i: ${params.moveSans[i]}');
            break;
          case MoveImpactType.blunder:
            blunderCount++;
            debugPrint('🎨 ?? BLUNDER move $i: ${params.moveSans[i]}');
            break;
          case MoveImpactType.normal:
            // Don't log normal moves
            break;
        }
      }
    }

    debugPrint('🎨🎨🎨 MOVE IMPACT SUMMARY for game ${params.gameId}:');
    debugPrint('🎨 Total analyzed: $analyzedCount moves');
    debugPrint('🎨 Brilliant: $brilliantCount, Great: $greatCount, Interesting: $interestingCount');
    debugPrint('🎨 Inaccuracy: $inaccuracyCount, Blunder: $blunderCount');
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

// ============================================================================
// HELPER FUNCTIONS FOR COMPREHENSIVE MOVE IMPACT ANALYSIS
// ============================================================================

/// Convert centipawns to win probability using sigmoid function
/// Formula: winProb = 1 / (1 + e^(-k * cp))
/// where k controls the steepness (default 0.004 ≈ 1/250)
///
/// Examples:
/// - cp = 0   → 50% win probability (equal)
/// - cp = 100 → ~62% (slight advantage)
/// - cp = 300 → ~77% (winning)
/// - cp = 500 → ~88% (clearly winning)
double _cpToWinProb(int cp, {double k = 0.004}) {
  // Handle mate scores (±100000)
  if (cp.abs() >= 100000) {
    return cp > 0 ? 1.0 : 0.0;
  }
  return 1.0 / (1.0 + math.exp(-k * cp));
}

/// Detect game phase based on FEN
/// - Opening: Queens on board + high material count
/// - Endgame: Queens off OR very low material (≤10 points of minor/major pieces)
/// - Middlegame: Everything else
GamePhase _detectGamePhase(String fen) {
  final parts = fen.split(' ');
  if (parts.isEmpty) return GamePhase.middlegame;

  final board = parts[0];

  // Check if queens are on board
  final hasWhiteQueen = board.contains('Q');
  final hasBlackQueen = board.contains('q');
  final queensOn = hasWhiteQueen || hasBlackQueen;

  // Count material (simplified)
  int material = 0;
  material += 'R'.allMatches(board).length * 5; // Rooks
  material += 'r'.allMatches(board).length * 5;
  material += 'B'.allMatches(board).length * 3; // Bishops
  material += 'b'.allMatches(board).length * 3;
  material += 'N'.allMatches(board).length * 3; // Knights
  material += 'n'.allMatches(board).length * 3;
  material += 'Q'.allMatches(board).length * 9; // Queens
  material += 'q'.allMatches(board).length * 9;

  // Endgame: queens off and low material, or very low material regardless
  if ((!queensOn && material <= 10) || material <= 6) {
    return GamePhase.endgame;
  }

  // Opening: queens on and high material
  if (queensOn && material >= 30) {
    return GamePhase.opening;
  }

  return GamePhase.middlegame;
}

class _PhaseThresholds {
  final double blunder;
  final double inaccuracy;
  final double great;
  final double interesting;

  const _PhaseThresholds({
    required this.blunder,
    required this.inaccuracy,
    required this.great,
    required this.interesting,
  });
}

const Map<GamePhase, _PhaseThresholds> _phaseThresholdsMap = {
  GamePhase.opening: _PhaseThresholds(
    blunder: 0.45,
    inaccuracy: 0.08,
    great: 0.18,
    interesting: 0.04,
  ),
  GamePhase.middlegame: _PhaseThresholds(
    blunder: 0.40,
    inaccuracy: 0.06,
    great: 0.22,
    interesting: 0.05,
  ),
  GamePhase.endgame: _PhaseThresholds(
    blunder: 0.30,
    inaccuracy: 0.03,
    great: 0.15,
    interesting: 0.03,
  ),
};

double _advantageBuffer(int cp, {double factor = 0.03}) {
  final normalized = cp.abs() / 200.0;
  final sigmoid = 1.0 / (1.0 + math.exp(-normalized));
  return factor * sigmoid;
}

bool _inDrawBand(int cp) => cp.abs() <= 120;

AdvantageTier _advantageTier(int cp) {
  if (cp.abs() <= 120) return AdvantageTier.equal;
  if (cp.abs() <= 260) return AdvantageTier.slight;
  return AdvantageTier.winning;
}

bool _gaveAwayWin(int bestCp, int actualCp) {
  return bestCp >= 220 && actualCp <= 80;
}

bool _handedOverAdvantage(int bestCp, int actualCp) {
  if (bestCp > 0 &&
      _advantageTier(bestCp) == AdvantageTier.winning &&
      _advantageTier(actualCp) != AdvantageTier.winning &&
      actualCp <= 100) {
    return true;
  }

  if (_advantageTier(bestCp) == AdvantageTier.slight && actualCp <= -120) {
    return true;
  }

  if (_inDrawBand(bestCp) && actualCp <= -220) {
    return true;
  }

  return false;
}

/// Count how many moves in PVs are "near-best" (within threshold of best move)
/// Uses both centipawn and win-probability thresholds
int _countNearBestMoves(
  List<Pv> pvs, {
  int cpThreshold = 30,
  double wpThreshold = 0.02,
}) {
  if (pvs.isEmpty) return 0;

  final bestCp = pvs[0].cp;
  final bestWp = _cpToWinProb(bestCp);

  int count = 0;
  for (final pv in pvs) {
    final cp = pv.cp;
    final wp = _cpToWinProb(cp);

    // Consider "near-best" if within EITHER threshold
    if ((bestCp - cp).abs() <= cpThreshold || (bestWp - wp).abs() <= wpThreshold) {
      count++;
    }
  }

  return count;
}

/// Detect if position is already decided (outcome essentially determined)
/// Returns true if:
/// - Absolute eval ≥ 500cp
/// - Win probability ≥ 0.9 or ≤ 0.1
/// - Mate score detected
bool _isDecidedPosition(int cp) {
  if (cp.abs() >= 500) return true;
  if (cp.abs() >= 100000) return true; // Mate score

  final wp = _cpToWinProb(cp);
  if (wp >= 0.9 || wp <= 0.1) return true;

  return false;
}

/// Classify position outcome from player's perspective
/// Returns: 'winning', 'equal', or 'losing'
String _getOutcomeClass(int cpFromPlayerPerspective) {
  if (cpFromPlayerPerspective >= 300) return 'winning';
  if (cpFromPlayerPerspective <= -300) return 'losing';
  return 'equal';
}

/// Detect if a move flips the outcome class against the player
/// e.g., winning → equal, winning → losing, equal → losing
bool _flipsOutcomeClass(int cpBefore, int cpAfter) {
  final classBefore = _getOutcomeClass(cpBefore);
  final classAfter = _getOutcomeClass(cpAfter);

  if (classBefore == 'winning' && (classAfter == 'equal' || classAfter == 'losing')) {
    return true;
  }
  if (classBefore == 'equal' && classAfter == 'losing') {
    return true;
  }

  return false;
}

/// Check if a move is a sacrifice
/// Detects if material was lost but eval holds or improves
/// (Requires actual position analysis - this is a placeholder for now)
bool _isSacrifice({
  required String moveSan,
  required int cpBefore,
  required int cpAfter,
}) {
  // Placeholder: detect "x" in move (capture) combined with eval improvement
  // A real implementation would need actual board state to calculate material
  final isCapture = moveSan.contains('x');
  final evalImproves = cpAfter >= cpBefore - 50; // Eval doesn't crash

  // Very rough heuristic: if it's a capture and eval holds, might be sacrifice
  // TODO: Implement proper material counting
  return isCapture && evalImproves && (cpAfter - cpBefore).abs() < 100;
}

/// Check if a move is "quiet tactical"
/// - Non-capture, non-check move
/// - But creates significant eval swing
bool _isQuietTactical({
  required String moveSan,
  required int evalSwing,
}) {
  final isCapture = moveSan.contains('x');
  final isCheck = moveSan.contains('+') || moveSan.contains('#');

  // Quiet = not capture, not check
  // Tactical = creates ≥80cp swing or ≥0.08 win-prob swing
  if (isCapture || isCheck) return false;

  return evalSwing.abs() >= 80;
}
