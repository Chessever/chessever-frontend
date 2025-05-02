// lib/services/lichess_api_service.dart
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../models/tournament.dart';
import '../models/game.dart';

/// Base exception for API errors
class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => 'ApiException: $message';
}

/// Thrown when HTTP status is 404
class NotFoundException extends ApiException {
  NotFoundException(String msg) : super(msg);
}

/// Thrown on network‐level errors
class NetworkException extends ApiException {
  NetworkException(String msg) : super(msg);
}

/// Thrown on JSON parse errors
class ParsingException extends ApiException {
  ParsingException(String msg) : super(msg);
}

class ChesseverApiService {
  /// Singleton instance
  static final ChesseverApiService instance = ChesseverApiService();

  /// Change this to wherever your Flask server is running
  static const _baseUrl = 'http://127.0.0.1:5000';
  // static const _baseUrl = 'http://localhost:5000';

  final http.Client _client;
  ChesseverApiService({http.Client? client}) : _client = client ?? http.Client();

  Future<Map<String, List<Tournament>>> fetchTournaments() async {
    final uri = Uri.parse('$_baseUrl/tournaments');
    http.Response res;
    try {
      res = await _client.get(uri).timeout(const Duration(seconds: 10));
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect to $_baseUrl: $e');
    }

    if (res.statusCode == 200) {
      try {
        final dynamic decoded = jsonDecode(res.body);
        if (decoded is! Map<String, dynamic>) {
          throw ParsingException('Expected JSON object, got ${decoded.runtimeType}');
        }
        final Map<String, dynamic> jsonMap = decoded;
        // Define categories
        const categories = ['upcoming', 'started', 'finished'];
        final result = <String, List<Tournament>>{};
        for (final category in categories) {
          final rawList = jsonMap[category];
          if (rawList is List) {
            result[category] = rawList
                .where((e) => e != null)
                .map((e) {
                  if (e is Map<String, dynamic>) {
                    return Tournament.fromJson(e);
                  } else {
                    throw ParsingException('Invalid tournament entry: $e');
                  }
                })
                .toList();
          } else {
            // handle missing or null category as empty list
            result[category] = <Tournament>[];
          }
        }
        return result;
      } catch (e) {
        throw ParsingException('Could not parse tournaments: $e');
      }
    }

    if (res.statusCode == 404) {
      throw NotFoundException('Tournaments endpoint not found (404)');
    }

    throw ApiException('Error fetching tournaments: HTTP ${res.statusCode}');
  }


  /// Fetch all rounds for one tournament from `GET /tournaments/:id/rounds`
  Future<List<BroadcastGame>> fetchBroadcastRoundGames(String broadcastId) async {
    final uri = Uri.parse('$_baseUrl/tournaments/$broadcastId/rounds');
    http.Response res;
    try {
      res = await _client.get(uri).timeout(const Duration(seconds: 10));
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect to $_baseUrl: $e');
    }

    if (res.statusCode == 200) {
      try {
        final List<dynamic> jsonList = jsonDecode(res.body);
        return jsonList
            .map((e) => BroadcastGame.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        throw ParsingException('Could not parse rounds for $broadcastId: $e');
      }
    }

    if (res.statusCode == 404) {
      throw NotFoundException(
          'Rounds for broadcast $broadcastId not found (404)');
    }

    throw ApiException(
        'Error fetching rounds: HTTP ${res.statusCode}');
  }

  void dispose() => _client.close();
}
