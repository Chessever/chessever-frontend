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
      return CloudEval.fromJson(decoded);
    }

    if (resp.statusCode == 404) {
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      throw NoEvalException(decoded['error'] ?? 'No evaluation');
    }

    throw HttpException('Unexpected status ${resp.statusCode}');
  }
}

class NoEvalException implements Exception {
  final String message;

  NoEvalException(this.message);
}
