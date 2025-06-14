import 'dart:async';
import 'dart:convert';
import 'package:chessever2/repository/api_utils/api_exceptions.dart';
import 'package:http/http.dart' as http;
import 'package:hooks_riverpod/hooks_riverpod.dart';

abstract class ILichessCloudEvaluator {
  Future<Map<String, dynamic>> fetchData(String fen, int multiPv);
}

class LichessCloudEvaluator implements ILichessCloudEvaluator {
  final http.Client _client;
  LichessCloudEvaluator({http.Client? client}) : _client = client ?? http.Client();

  @override
  Future<Map<String, dynamic>> fetchData(String fen, int multiPv) async {
    final uri = Uri.https('lichess.org', '/api/cloud-eval', {
      'fen': fen,
      'multiPv': multiPv.toString(),
    });
    try {
      final resp = await _client.get(uri);
      if (resp.statusCode != 200) {
        throw NetworkException('Failed to fetch cloud eval: HTTP \\${resp.statusCode}');
      }
      return json.decode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      throw ParsingException('Failed to fetch or parse cloud eval: $e');
    }
  }

  void dispose() => _client.close();
}

final lichessCloudEvaluatorProvider = Provider<ILichessCloudEvaluator>((ref) {
  final evaluator = LichessCloudEvaluator();
  ref.onDispose(() => evaluator.dispose());
  return evaluator;
});
