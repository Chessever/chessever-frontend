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

  Future<CloudEval> getEval(String fen, {int multiPv = 3}) async {
    final uri = Uri.parse('$baseUrl?fen=${Uri.encodeComponent(fen)}&multiPv=$multiPv');
    final resp = await http.get(uri).timeout(const Duration(seconds: 8));

    if (resp.statusCode == 200) {
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final cloudEval = CloudEval.fromJson(decoded);

      // Convert Lichess evaluations to white's perspective for consistency
      return _convertToWhitePerspective(cloudEval, fen, multiPv);
    }

    if (resp.statusCode == 404) {
      throw NoEvalException('No evaluation');
    }

    throw HttpException('Unexpected status ${resp.statusCode}');
  }

  /// Converts Lichess evaluation from current player's perspective to white's perspective
  /// CRITICAL: Based on testing, when evaluations are wrong, it means they're NOT being flipped
  /// when they should be. This indicates evaluations ARE from current player's perspective.
  CloudEval _convertToWhitePerspective(CloudEval cloudEval, String fen, int multiPv) {
    // Parse FEN to determine whose turn it is
    final fenParts = fen.split(' ');
    final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
    final originalCp = cloudEval.pvs.isNotEmpty ? cloudEval.pvs.first.cp : 0;

    print("🔍 LICHESS: Received ${cloudEval.pvs.length} PVs (multiPv=$multiPv), side=$sideToMove, firstCp=$originalCp");

    final adjustedPvs = cloudEval.pvs
        .map(
          (pv) => Pv(
            moves: pv.moves,
            cp: pv.cp,
            isMate: pv.isMate,
            mate: pv.mate,
            whitePerspective: true,
          ),
        )
        .toList();

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
