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

  /// Lichess API returns evaluations ALREADY in white's perspective
  /// This method just validates and marks them with whitePerspective flag
  /// NO CONVERSION NEEDED - Lichess API always gives white's perspective
  CloudEval _convertToWhitePerspective(CloudEval cloudEval, String fen, int multiPv) {
    // Parse FEN for logging only
    final fenParts = fen.split(' ');
    final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
    final originalCp = cloudEval.pvs.isNotEmpty ? cloudEval.pvs.first.cp : 0;

    print(
      "🔍 LICHESS: Received ${cloudEval.pvs.length} PVs (multiPv=$multiPv), side=$sideToMove, cp=$originalCp",
    );

    // CRITICAL: Lichess API already returns evaluations in white's perspective!
    // Positive = white advantage, Negative = black advantage
    // We just need to mark the PVs with whitePerspective flag
    final adjustedPvs = cloudEval.pvs.map((pv) {
      return Pv(
        moves: pv.moves,
        cp: pv.cp, // NO CONVERSION - already in white's perspective!
        isMate: pv.isMate,
        mate: pv.mate, // NO CONVERSION - already in white's perspective!
        whitePerspective: true,
      );
    }).toList();

    print(
      "✅ LICHESS: Already in white's perspective - side=$sideToMove, cp=$originalCp",
    );

    // Use the requested FEN to avoid mismatches on strict FEN equality checks elsewhere
    return CloudEval(
      fen: fen,
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
