import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;

final lichessEvalRepoProvider = AutoDisposeProvider<_LichessEvalRepository>(
  (ref) => _LichessEvalRepository(),
);

class _LichessEvalRepository {
  final String baseUrl = 'https://lichess.org/api/cloud-eval';

  Future<CloudEval> getEval(String fen) async {
    final uri = Uri.parse('$baseUrl?fen=${Uri.encodeComponent(fen)}');
    final resp = await http.get(uri).timeout(const Duration(seconds: 8));

    if (resp.statusCode == 200) {
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final cloudEval = CloudEval.fromJson(decoded);

      // Convert Lichess evaluations to white's perspective for consistency
      return _convertToWhitePerspective(cloudEval, fen);
    }

    if (resp.statusCode == 404) {
      throw NoEvalException('No evaluation');
    }

    throw HttpException('Unexpected status ${resp.statusCode}');
  }

  /// Converts Lichess evaluation from current player's perspective to white's perspective
  /// CRITICAL: Based on testing, when evaluations are wrong, it means they're NOT being flipped
  /// when they should be. This indicates evaluations ARE from current player's perspective.
  CloudEval _convertToWhitePerspective(CloudEval cloudEval, String fen) {
    // Parse FEN to determine whose turn it is
    final fenParts = fen.split(' ');
    final isBlackToMove = fenParts.length >= 2 && fenParts[1] == 'b';
    final sideToMove = isBlackToMove ? 'b' : 'w';
    final originalCp = cloudEval.pvs.isNotEmpty ? cloudEval.pvs.first.cp : 0;

    if (!isBlackToMove) {
      // White to move - evaluation is from white's perspective, no conversion needed
      print("🔍 LICHESS CONVERSION: FEN=$fen, side=WHITE, originalCp=$originalCp, finalCp=$originalCp (no flip needed)");
      return cloudEval;
    }

    // Black to move - evaluation is from BLACK's perspective, MUST flip to white's perspective
    // Example: If black is winning, Lichess returns positive (good for black)
    // We need to flip it to negative (bad for white)
    final adjustedPvs = cloudEval.pvs.map((pv) {
      final flippedCp = -pv.cp;
      print("🔍 LICHESS CONVERSION: FEN=$fen, side=BLACK, originalCp=${pv.cp}, finalCp=$flippedCp (FLIPPED to white perspective)");
      return Pv(
        moves: pv.moves,
        cp: flippedCp, // Flip to white's perspective
        isMate: pv.isMate,
        mate: pv.mate != null ? -pv.mate! : null,
      );
    }).toList();

    return CloudEval(
      fen: cloudEval.fen,
      knodes: cloudEval.knodes,
      depth: cloudEval.depth,
      pvs: adjustedPvs,
    );
  }
}

class NoEvalException implements Exception {
  final String message;

  NoEvalException(this.message);
}
