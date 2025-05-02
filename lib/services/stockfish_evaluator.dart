// lib/services/stockfish_evaluator.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class LichessCloudEvaluator {
  LichessCloudEvaluator._();
  static final LichessCloudEvaluator instance = LichessCloudEvaluator._();

  Future<Map<String, dynamic>> fetchData(String fen, int multiPv) async {
    final uri = Uri.https('lichess.org', '/api/cloud-eval', {
      'fen': fen,
      'multiPv': multiPv.toString(),
    });

    try {
      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        // Non-OK → return an empty‐variation response
        return {'pvs': <dynamic>[]};
      }
      return json.decode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      // Network failure, JSON error, etc. → also return an empty set of PVs
      return {'pvs': <dynamic>[]};
    }
  }

  // /// Returns a pawn‑unit evaluation (e.g. "0.12") or "#3" for mate.
  // Future<String> evaluateFen(String fen) async {
  //   try {
  //     final uri = Uri.https('lichess.org', '/api/cloud-eval', {
  //       'fen': fen,
  //       'multiPv': '1',
  //     });

  //     final resp = await http.get(uri);
  //     if (resp.statusCode != 200) {
  //       return '?';
  //       // throw Exception('Lichess eval failed: ${resp.statusCode}');
  //     }

  //     final data = json.decode(resp.body) as Map<String, dynamic>;
  //     final List<dynamic> pvs = data['pvs'] as List<dynamic>;
  //     if (pvs.isEmpty) {
  //       return '?';
  //     }

  //     final firstPv = pvs.first as Map<String, dynamic>;
  //     // Lichess returns either "cp" or "mate"
  //     if (firstPv.containsKey('mate')) {
  //       return '#${firstPv['mate']}';
  //     } else if (firstPv.containsKey('cp')) {
  //       final cp = firstPv['cp'] as int;
  //       return (cp / 100.0).toStringAsFixed(2);
  //     }

  //     return '?';
  //   } catch (e) {
  //     print(e);
  //     return '?';
  //   }
  // }
}
