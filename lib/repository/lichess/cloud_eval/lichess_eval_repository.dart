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

  /// Converts Lichess evaluation from side-to-move perspective to WHITE'S perspective.
  /// Positive cp after conversion always means white is better; negative means black is better.
  CloudEval _convertToWhitePerspective(CloudEval cloudEval, String fen, int multiPv) {
    // Parse FEN to determine whose turn it is
    final fenParts = fen.split(' ');
    final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
    final isBlackToMove = sideToMove == 'b';
    final originalCp = cloudEval.pvs.isNotEmpty ? cloudEval.pvs.first.cp : 0;

    print(
      "🔍 LICHESS: Received ${cloudEval.pvs.length} PVs (multiPv=$multiPv), side=$sideToMove, firstCp=$originalCp",
    );

    final adjustedPvs = cloudEval.pvs.map((pv) {
      final correctedCp = isBlackToMove ? -pv.cp : pv.cp;
      final correctedMate = pv.mate != null
          ? (isBlackToMove ? -pv.mate! : pv.mate!)
          : null;
      return Pv(
        moves: pv.moves,
        cp: correctedCp,
        isMate: pv.isMate,
        mate: correctedMate,
        whitePerspective: true,
      );
    }).toList();

    final correctedFirst = adjustedPvs.isNotEmpty ? adjustedPvs.first.cp : 0;
    print(
      "✅ LICHESS NORMALIZED: side=$sideToMove, firstCpCorrected=$correctedFirst",
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
