import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class GamebaseApiKeyMissingException implements Exception {
  const GamebaseApiKeyMissingException();

  @override
  String toString() {
    return 'Missing GAMEBASE_API_KEY. Generate a personal developer key from '
        'https://chessever.com/developers and add it to .env.';
  }
}

/// Repository for Gamebase API calls.
/// Handles communication with the Chess Database API.
class GamebaseRepository {
  GamebaseRepository({http.Client? client, String? baseUrl, String? apiKey})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? 'https://service.chessever.com',
      _apiKey =
          (apiKey ?? const String.fromEnvironment('GAMEBASE_API_KEY')).trim();

  final http.Client _client;
  final String _baseUrl;
  final String _apiKey;

  Map<String, String> get _headers {
    if (_apiKey.isEmpty) throw const GamebaseApiKeyMissingException();
    return {'Content-Type': 'application/json', 'X-API-Key': _apiKey};
  }

  /// Get move aggregates for a given FEN position.
  ///
  /// [fen] - FEN notation of the position to query
  /// [timeControl] - Optional time control filter (CLASSICAL, RAPID, BLITZ)
  /// [minRating] - Optional minimum rating filter
  /// [maxRating] - Optional maximum rating filter
  /// [playerId] - Optional player UUID to filter by
  Future<List<MoveAggregate>> getPositionAggregates({
    required String fen,
    TimeControl? timeControl,
    int? minRating,
    int? maxRating,
    String? playerId,
  }) async {
    try {
      final queryParams = <String, String>{'fen': fen};

      if (timeControl != null) {
        queryParams['timeControl'] = timeControl.name.toUpperCase();
      }

      if (minRating != null) {
        queryParams['minRating'] = minRating.toString();
      }

      if (maxRating != null) {
        queryParams['maxRating'] = maxRating.toString();
      }

      if (playerId != null && playerId.isNotEmpty) {
        queryParams['playerId'] = playerId;
      }

      final uri = Uri.parse(
        '$_baseUrl/api/game-position/aggregates',
      ).replace(queryParameters: queryParams);

      final response = await _client.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = json.decode(response.body);
        final List<dynamic> moves = responseBody['data']['moves'] ?? [];
        return moves.map((e) => MoveAggregate.fromJson(e)).toList();
      } else if (response.statusCode == 404) {
        // No games found for this position - return empty list
        return [];
      } else {
        throw GamebaseApiException(
          'Failed to get position aggregates',
          statusCode: response.statusCode,
          body: response.body,
        );
      }
    } catch (e) {
      if (e is GamebaseApiException) rethrow;
      throw GamebaseApiException('Network error: $e');
    }
  }

  /// Get a list of players matching the search criteria.
  ///
  /// [name] - Optional name to search for
  /// [pageNumber] - Page number for pagination (0-indexed per API spec)
  /// [pageSize] - Results per page (default: 20)
  Future<List<GamebasePlayer>> getPlayers({
    String? name,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'pageNumber': pageNumber.toString(),
        'pageSize': pageSize.toString(),
      };

      if (name != null && name.isNotEmpty) {
        queryParams['name'] = name;
      }

      final uri = Uri.parse(
        '$_baseUrl/api/player',
      ).replace(queryParameters: queryParams);

      final response = await _client.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = json.decode(response.body);
        final List<dynamic> data = responseBody['data'] ?? [];
        return data.map((e) => GamebasePlayer.fromJson(e)).toList();
      } else {
        throw GamebaseApiException(
          'Failed to get players',
          statusCode: response.statusCode,
          body: response.body,
        );
      }
    } catch (e) {
      if (e is GamebaseApiException) rethrow;
      throw GamebaseApiException('Network error: $e');
    }
  }

  /// Get a player by their ID.
  ///
  /// [id] - The player's UUID
  Future<GamebasePlayer?> getPlayerById(String id) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/player/$id');
      final response = await _client.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = json.decode(response.body);
        return GamebasePlayer.fromJson(responseBody['data']);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw GamebaseApiException(
          'Failed to get player',
          statusCode: response.statusCode,
          body: response.body,
        );
      }
    } catch (e) {
      if (e is GamebaseApiException) rethrow;
      throw GamebaseApiException('Network error: $e');
    }
  }

  /// Get a game by its ID.
  ///
  /// [id] - The game's UUID
  Future<GamebaseGame?> getGameById(String id) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/game/$id');
      final response = await _client.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = json.decode(response.body);
        return GamebaseGame.fromJson(responseBody['data']);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw GamebaseApiException(
          'Failed to get game',
          statusCode: response.statusCode,
          body: response.body,
        );
      }
    } catch (e) {
      if (e is GamebaseApiException) rethrow;
      throw GamebaseApiException('Network error: $e');
    }
  }

  /// Dispose the HTTP client when done.
  void dispose() {
    _client.close();
  }
}

/// Exception thrown when Gamebase API calls fail.
class GamebaseApiException implements Exception {
  GamebaseApiException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() {
    final buffer = StringBuffer('GamebaseApiException: $message');
    if (statusCode != null) {
      buffer.write(' (status: $statusCode)');
    }
    if (body != null && kDebugMode) {
      buffer.write('\nResponse: $body');
    }
    return buffer.toString();
  }
}
