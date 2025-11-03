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
    try {
      final uri = Uri.parse('$baseUrl?fen=${Uri.encodeComponent(fen)}&multiPv=$multiPv');
      print('🌐 Lichess: Requesting eval from $uri');

      final resp = await http.get(uri).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          print('⏱️ Lichess: Request timeout after 8 seconds for $fen');
          throw TimeoutException('Lichess API timeout');
        },
      );

      print('📡 Lichess: Response status ${resp.statusCode} for $fen');

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        final cloudEval = CloudEval.fromJson(decoded);

        // Convert Lichess evaluations to white's perspective for consistency
        return _convertToWhitePerspective(cloudEval, fen, multiPv);
      }

      if (resp.statusCode == 404) {
        print('📭 Lichess: No cloud eval for $fen');
        throw NoEvalException('No evaluation');
      }

      // 429 = Lichess rate limiting - just throw exception, cascade will fallback to Stockfish
      if (resp.statusCode == 429) {
        print('⚡ Lichess: Rate limited (429), falling back to Stockfish');
        throw RateLimitException('Rate limited by Lichess');
      }

      print('❌ Lichess: Unexpected status ${resp.statusCode}');
      throw HttpException('Unexpected status ${resp.statusCode}');
    } on SocketException catch (e) {
      print('🔌 Lichess: Network error (SocketException) - $e');
      throw HttpException('Network connection failed: ${e.message}');
    } on TimeoutException catch (e) {
      print('⏱️ Lichess: Timeout - $e');
      rethrow;
    } catch (e) {
      print('❌ Lichess: Unexpected error - $e');
      rethrow;
    }
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

class RateLimitException implements Exception {
  final String message;

  RateLimitException(this.message);
}
