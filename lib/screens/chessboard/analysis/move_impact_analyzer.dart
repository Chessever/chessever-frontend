// DISABLED: Local move impact calculation - we get move impact from Supabase edge function
// This prevents phone from heating up by avoiding local Stockfish calculations for move impact
// The symbols (!, ?, !?, ??) are fetched from Supabase edge function, not calculated locally
//
// Only the data classes (MoveImpactType, MoveImpactAnalysis) are kept active
// for receiving and displaying data from Supabase

import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Enum representing different types of impactful chess moves with their visual properties
/// This is kept active for receiving move impact data from Supabase edge function
enum MoveImpactType {
  // DISABLED: Brilliant and great moves are no longer classified
  // // Brilliant move (!!) - Very smart move, not easy to find
  // brilliant(
  //   symbol: '!!',
  //   color: Color(0xFF1ABC9C), // Turquoise
  //   description: 'Brilliant move - Very hard to find, gains significant advantage',
  // ),
  //
  // // Great move (!) - Good move with less impact than brilliant
  // great(
  //   symbol: '!',
  //   color: Color(0xFF2ECC71), // Bright green
  //   description: 'Great move - Good move that gains advantage',
  // ),

  // Interesting move (!?) - Missed opportunity for a much better move
  interesting(
    symbol: '?!',
    color: Color(0xFF1565C0), // Blue
    description: 'Inaccuracy - Draw-range mistake',
  ),

  // Mistake (?) - Suboptimal move with major disadvantage
  inaccuracy(
    symbol: '?',
    color: Color(0xFFFFC107), // Yellow
    description: 'Mistake - Course-changing misplay',
  ),

  // Blunder (??) - Very bad move causing significant disadvantage
  blunder(
    symbol: '??',
    color: Color(0xFFE53935), // Red
    description: 'Blunder - Very bad move causing significant disadvantage',
  ),

  // Normal move - No special annotation
  normal(
    symbol: '',
    color: Color(0xFFFAFAFA),
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
/// This is kept active for receiving move impact data from Supabase edge function
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

// =============================================================================
// DISABLED: All local calculation code below is commented out
// Move impact is now fetched from Supabase edge function instead of
// being calculated locally on the phone using Stockfish
// This prevents the phone from heating up during analysis
// =============================================================================

// import 'dart:math' as math;
// import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
// import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
// import 'package:dartchess/dartchess.dart';
// import 'package:hooks_riverpod/hooks_riverpod.dart';

// /// Parameters for analyzing all moves from PGN
// class PgnAnalysisParams {
//   final String pgn;
//   final String gameId; // Unique game identifier to prevent cross-game contamination
//
//   const PgnAnalysisParams({
//     required this.pgn,
//     required this.gameId,
//   });
//
//   @override
//   bool operator ==(Object other) =>
//       identical(this, other) ||
//       other is PgnAnalysisParams &&
//           runtimeType == other.runtimeType &&
//           pgn == other.pgn &&
//           gameId == other.gameId;
//
//   @override
//   int get hashCode => pgn.hashCode ^ gameId.hashCode;
// }

// /// Parameters for analyzing moves using positions (fallback when PGN has no evals)
// class PositionAnalysisParams {
//   final List<String> positionFens;
//   final List<String> moveSans;
//   final String gameId; // Unique game identifier to prevent cross-game contamination
//
//   const PositionAnalysisParams({
//     required this.positionFens,
//     required this.moveSans,
//     required this.gameId,
//   });
//
//   @override
//   bool operator ==(Object other) =>
//       identical(this, other) ||
//       other is PositionAnalysisParams &&
//           runtimeType == other.runtimeType &&
//           positionFens.length == other.positionFens.length &&
//           moveSans.length == other.moveSans.length &&
//           gameId == other.gameId;
//
//   @override
//   int get hashCode => positionFens.length.hashCode ^ moveSans.length.hashCode ^ gameId.hashCode;
// }

// /// Parameters for position FENs generation
// class PositionFensParams {
//   final List<Move> allMoves;
//   final Position? startingPosition;
//   final String gameId; // Unique game identifier to prevent cross-game contamination
//
//   const PositionFensParams({
//     required this.allMoves,
//     this.startingPosition,
//     required this.gameId,
//   });
//
//   @override
//   bool operator ==(Object other) =>
//       identical(this, other) ||
//       other is PositionFensParams &&
//           runtimeType == other.runtimeType &&
//           allMoves.length == other.allMoves.length &&
//           gameId == other.gameId;
//
//   @override
//   int get hashCode => allMoves.length.hashCode ^ gameId.hashCode;
// }

// /// Memoized provider to generate position FENs from game state
// /// Prevents rebuild loop by calculating FENs once and caching
// /// PERF: Added autoDispose to prevent memory buildup during rapid page swiping
// final positionFensProvider = Provider.family.autoDispose<List<String>, PositionFensParams>((ref, params) {
//   final List<String> positionFens = [];
//   Position currentPos = params.startingPosition ?? Chess.initial;
//   positionFens.add(currentPos.fen); // Starting position
//
//   for (Move move in params.allMoves) {
//     currentPos = currentPos.play(move);
//     positionFens.add(currentPos.fen);
//   }
//
//   return positionFens;
// });

// /// Provider for FULL position evaluation including all top moves
// /// Returns complete CloudEval with multiple PVs (top 5 moves)
// /// Uses cascade evaluation: cloud → Supabase → Lichess → Stockfish
// /// PERF: Added autoDispose to prevent memory buildup during rapid page swiping
// final fullPositionEvalProvider = FutureProvider.family.autoDispose<CloudEval?, String>((ref, fen) async {
//   try {
//     // Use the cascade eval provider for this position
//     // Request 3 PVs for move impact analysis
//     final evalResult = await ref.read(cascadeEvalProviderForBoard(
//       CascadeEvalParams(fen: fen, multiPV: 3),
//     ).future);
//     return evalResult;
//   } catch (e) {
//     debugPrint('Error evaluating position $fen: $e');
//     return null;
//   }
// });

// /// Provider that watches ONLY game moves and provides impact analysis
// /// This isolates impact calculation from frequent state changes (analysis mode, current move, etc.)
// /// Only depends on game ID - internally extracts moves from a game-specific source
// /// Must be overridden per-game to provide actual moves data
// final gameMoveImpactsProvider = FutureProvider.family.autoDispose<Map<int, MoveImpactAnalysis>?, String>((ref, gameId) async {
//   // NOTE: This provider should be overridden in each screen that needs impact analysis
//   // For now, return null to avoid errors
//   // The screen must provide a provider that returns PositionAnalysisParams for the given gameId
//   return null;
// });

// /// NEW: Fallback provider that evaluates all positions using FULL CloudEval (top moves comparison)
// /// Compares player's move vs best alternatives from engine
// /// Uses cascade eval in PARALLEL with 75 isolates
// /// PERF: Added autoDispose to prevent memory buildup during rapid page swiping
// final allMovesImpactFromPositionsProvider = FutureProvider.family.autoDispose<Map<int, MoveImpactAnalysis>, PositionAnalysisParams>((ref, params) async {
//   // LOCAL STOCKFISH CALCULATION DISABLED - use Supabase edge function instead
//   return {};
// });

// /// Provider to analyze ALL moves from PGN in parallel using worker isolates
// /// This parses evaluations from PGN comments and calculates move impacts
// /// PERF: Added autoDispose to prevent memory buildup during rapid page swiping
// final allMovesImpactFromPgnProvider = FutureProvider.family.autoDispose<Map<int, MoveImpactAnalysis>, PgnAnalysisParams>((ref, params) async {
//   // LOCAL STOCKFISH CALCULATION DISABLED - use Supabase edge function instead
//   return {};
// });

// /// Parse evaluations from PGN comments
// /// This will run in a worker isolate
// List<double?> _parseEvalsFromPgn(String pgn) {
//   // DISABLED - local calculation not used
//   return [];
// }

// MoveImpactAnalysis? _calculateMoveImpactFromAlternatives({
//   required CloudEval? positionEvalBeforeMove,
//   required CloudEval? positionEvalAfterMove,
//   required String positionFenBeforeMove,
//   required String? positionFenAfterMove,
//   required String playerMoveSan,
//   required int moveNumber,
// }) {
//   // DISABLED - local calculation not used
//   return null;
// }

// MoveImpactAnalysis? calculateMoveImpact({
//   required CloudEval? positionEvalBeforeMove,
//   required CloudEval? positionEvalAfterMove,
//   required String positionFenBeforeMove,
//   required String? positionFenAfterMove,
//   required String playerMoveSan,
//   required int moveNumber,
// }) {
//   // DISABLED - local calculation not used
//   return null;
// }

// MoveImpactAnalysis? _calculateMoveImpactFromEvals({
//   required double? evalBefore,
//   required double? evalAfter,
//   required String actualMoveSan,
//   required int moveIndex,
//   required bool isWhiteMove,
// }) {
//   // DISABLED - local calculation not used
//   return null;
// }

// // Helper functions - all disabled
// String? _extractSanFromPv(String pvMoves) => null;
// String? _uciToSan(String uci, Position position) => null;
// double _cpToWinProb(int cp, {double k = 0.004}) => 0.5;
// bool _isWhiteToMove(String fen) => true;
// String _normalizeSan(String san) => san;
// bool _sanMatches(String? sanA, String normalizedSanB) => false;
// enum PositionOutcome { losing, draw, winning }
// PositionOutcome _outcomeForPlayer(int cp) => PositionOutcome.draw;
// bool _isDecidedPosition(int cp) => false;
// bool _isSacrifice({required String moveSan, required int cpBefore, required int cpAfter, bool lostMaterial = false}) => false;
// bool _isQuietTactical({required String moveSan, required int evalSwing}) => false;
// enum GamePhase { opening, middlegame, endgame }
// enum AdvantageTier { equal, slight, winning }
