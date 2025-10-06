import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/analysis/move_impact_analyzer.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

/// Provider that calculates move impacts by analyzing engine alternatives
/// Uses the cascade eval provider to get multiple PV lines for each position
final simpleMoveImpactProvider = FutureProvider.family<Map<int, MoveImpactAnalysis>, SimpleMoveImpactParams>((ref, params) async {
  final Map<int, MoveImpactAnalysis> impactResults = {};

  debugPrint('🎨 COMPREHENSIVE IMPACT: Starting for ${params.positionFens.length} positions, ${params.moveSans.length} moves');

  // Get evaluations for ALL positions BEFORE moves using cascade provider
  final List<CloudEval?> evalsBefore = [];
  for (int i = 0; i < params.moveSans.length; i++) {
    final fenBefore = params.positionFens[i];
    try {
      final eval = await ref.read(cascadeEvalProviderForBoard(fenBefore).future);
      evalsBefore.add(eval);
      debugPrint('📊 Move $i: Got eval for position BEFORE move, ${eval.pvs.length} PVs, best cp=${eval.pvs.first.cp}');
    } catch (e) {
      debugPrint('⚠️ Move $i: Failed to get eval BEFORE: $e');
      evalsBefore.add(null);
    }
  }

  // Also get eval AFTER each move (for actual result comparison)
  final List<CloudEval?> evalsAfter = [];
  for (int i = 0; i < params.moveSans.length; i++) {
    final fenAfter = params.positionFens[i + 1];
    try {
      final eval = await ref.read(cascadeEvalProviderForBoard(fenAfter).future);
      evalsAfter.add(eval);
    } catch (e) {
      debugPrint('⚠️ Move $i: Failed to get eval AFTER: $e');
      evalsAfter.add(null);
    }
  }

  debugPrint('🎨 COMPREHENSIVE IMPACT: Got ${evalsBefore.where((e) => e != null).length} evals BEFORE, ${evalsAfter.where((e) => e != null).length} AFTER');

  // Now analyze each move
  for (int i = 0; i < params.moveSans.length; i++) {
    final evalBefore = evalsBefore[i];
    final evalAfter = evalsAfter[i];
    final isWhiteMove = params.isWhiteMoves[i];
    final actualMoveSan = params.moveSans[i];

    if (evalBefore == null || evalAfter == null) {
      debugPrint('🎨 Move $i: Skipping - missing eval');
      continue;
    }

    if (evalBefore.pvs.isEmpty || evalAfter.pvs.isEmpty) {
      debugPrint('🎨 Move $i: Skipping - empty PVs');
      continue;
    }

    // Get the best move from engine (first PV)
    final bestPv = evalBefore.pvs.first;
    final bestCp = bestPv.cp;

    // Convert best engine move UCI to SAN
    String? bestMoveSan;
    try {
      final fenBefore = params.positionFens[i];
      final pos = Chess.fromSetup(Setup.parseFen(fenBefore));
      if (bestPv.moves.isNotEmpty) {
        bestMoveSan = _uciToSan(bestPv.moves.split(' ').first, pos);
      }
    } catch (e) {
      debugPrint('⚠️ Move $i: Failed to convert best move UCI to SAN: $e');
    }

    // Get actual result after player's move
    final actualCp = evalAfter.pvs.first.cp;

    // Find player's move in the engine alternatives (PVs)
    int? playerMoveRank;
    int? playerMoveResultingCp;

    for (int pvIndex = 0; pvIndex < evalBefore.pvs.length; pvIndex++) {
      final pv = evalBefore.pvs[pvIndex];
      if (pv.moves.isEmpty) continue;

      try {
        final fenBefore = params.positionFens[i];
        final pos = Chess.fromSetup(Setup.parseFen(fenBefore));
        final pvMoveSan = _uciToSan(pv.moves.split(' ').first, pos);

        if (pvMoveSan != null && _movesMatch(pvMoveSan, actualMoveSan)) {
          playerMoveRank = pvIndex;
          playerMoveResultingCp = pv.cp;
          debugPrint('   Move $i: Found player move "$actualMoveSan" at rank $pvIndex, cp=$playerMoveResultingCp');
          break;
        }
      } catch (e) {
        debugPrint('⚠️ Move $i PV $pvIndex: Error converting UCI: $e');
      }
    }

    // If not found in engine alternatives, player made move outside top lines
    if (playerMoveRank == null) {
      playerMoveRank = 99;
      playerMoveResultingCp = actualCp; // Use actual resulting position eval
      debugPrint('   Move $i: Player move "$actualMoveSan" NOT in engine PVs, using actual cp=$actualCp');
    }

    // Convert to player's perspective (positive = advantage)
    final bestCpPlayer = isWhiteMove ? bestCp : -bestCp;
    final actualCpPlayer = isWhiteMove ? playerMoveResultingCp! : -playerMoveResultingCp!;

    // Calculate gap: how much WORSE is the played move compared to best
    final cpGap = bestCpPlayer - actualCpPlayer;

    debugPrint('   Move $i (${isWhiteMove ? "White" : "Black"}): bestCp=$bestCpPlayer, actualCp=$actualCpPlayer, gap=$cpGap, rank=$playerMoveRank');

    // === COMPREHENSIVE CLASSIFICATION ===
    final MoveImpactType impact;
    final bool isDecided = bestCp.abs() >= 500; // Position already winning/losing (5+ pawns)
    final bool hasManyAlternatives = evalBefore.pvs.length >= 3;

    // Count how many alternatives are near-best (within 30cp)
    int nearBestCount = 0;
    for (final pv in evalBefore.pvs) {
      if ((bestCp - pv.cp).abs() < 30) nearBestCount++;
    }
    final bool allSimilar = hasManyAlternatives && nearBestCount >= evalBefore.pvs.length - 1;

    if (cpGap >= 300) {
      // BLUNDER (??) - Lost 3+ pawns
      impact = MoveImpactType.blunder;
      debugPrint('      → BLUNDER (lost ${cpGap}cp)');
    } else if (cpGap >= 150) {
      // INACCURACY/MISTAKE (?) - Lost 1.5+ pawns
      impact = MoveImpactType.inaccuracy;
      debugPrint('      → INACCURACY (lost ${cpGap}cp)');
    } else if (playerMoveRank >= 2 && cpGap >= 50 && cpGap < 150) {
      // INTERESTING (!?) - Top 2-4 move but missed clearly better option
      impact = MoveImpactType.interesting;
      debugPrint('      → INTERESTING (rank $playerMoveRank, missed ${cpGap}cp)');
    } else if (playerMoveRank == 0 && !isDecided && hasManyAlternatives && !allSimilar) {
      // Check if it's BRILLIANT or GREAT
      final secondBestCp = evalBefore.pvs.length > 1 ? evalBefore.pvs[1].cp : bestCp;
      final thirdBestCp = evalBefore.pvs.length > 2 ? evalBefore.pvs[2].cp : bestCp;

      final gapTo2nd = (bestCp - secondBestCp).abs();
      final gapTo3rd = (bestCp - thirdBestCp).abs();

      // BRILLIANT (!!) - THE ONLY good move (huge gap to alternatives)
      if (gapTo2nd >= 100 && gapTo3rd >= 150) {
        impact = MoveImpactType.brilliant;
        debugPrint('      → BRILLIANT (gap to 2nd: ${gapTo2nd}cp, to 3rd: ${gapTo3rd}cp)');
      }
      // GREAT (!) - Best move with clear advantage over alternatives
      else if (gapTo2nd >= 50) {
        impact = MoveImpactType.great;
        debugPrint('      → GREAT (gap to 2nd: ${gapTo2nd}cp)');
      } else {
        impact = MoveImpactType.normal;
      }
    } else {
      // NORMAL - Everything else
      impact = MoveImpactType.normal;
    }

    impactResults[i] = MoveImpactAnalysis(
      impact: impact,
      evalChange: cpGap / 100.0,
      bestMoveEval: bestCpPlayer / 100.0,
      actualMoveEval: actualCpPlayer / 100.0,
      bestMoveSan: bestMoveSan,
      actualMoveSan: actualMoveSan,
      moveIndex: i,
    );
  }

  debugPrint('🎨 COMPREHENSIVE IMPACT: Classified ${impactResults.length} moves');
  final counts = {
    'brilliant': impactResults.values.where((r) => r.impact == MoveImpactType.brilliant).length,
    'great': impactResults.values.where((r) => r.impact == MoveImpactType.great).length,
    'interesting': impactResults.values.where((r) => r.impact == MoveImpactType.interesting).length,
    'inaccuracy': impactResults.values.where((r) => r.impact == MoveImpactType.inaccuracy).length,
    'blunder': impactResults.values.where((r) => r.impact == MoveImpactType.blunder).length,
  };
  debugPrint('🎨 COMPREHENSIVE IMPACT COUNTS: $counts');

  return impactResults;
});

/// Convert UCI move to SAN notation
String? _uciToSan(String uci, Chess position) {
  try {
    if (uci.length < 4) return null;

    final fromSquare = uci.substring(0, 2);
    final toSquare = uci.substring(2, 4);
    final promotion = uci.length > 4 ? uci[4] : null;

    final from = Square.fromName(fromSquare);
    final to = Square.fromName(toSquare);

    Move? move;
    if (promotion != null) {
      Role? promotionRole;
      switch (promotion.toLowerCase()) {
        case 'q': promotionRole = Role.queen; break;
        case 'r': promotionRole = Role.rook; break;
        case 'b': promotionRole = Role.bishop; break;
        case 'n': promotionRole = Role.knight; break;
        default: return null;
      }
      move = NormalMove(from: from, to: to, promotion: promotionRole);
    } else {
      move = NormalMove(from: from, to: to);
    }

    final result = position.makeSan(move);
    return result.$2; // Return just the SAN string from tuple
  } catch (e) {
    debugPrint('❌ ERROR converting UCI "$uci" to SAN: $e');
    return null;
  }
}

/// Check if two SAN moves match (ignoring check/checkmate symbols)
bool _movesMatch(String san1, String san2) {
  final clean1 = san1.replaceAll('+', '').replaceAll('#', '');
  final clean2 = san2.replaceAll('+', '').replaceAll('#', '');
  return clean1 == clean2;
}
