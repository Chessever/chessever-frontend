import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';

part 'gamebase_repository.mapper.dart';

@MappableClass()
class GamebaseResponse with GamebaseResponseMappable {
  const GamebaseResponse({required this.status, required this.data});

  final String status;
  final GamebaseData data;

  static const fromJson = GamebaseResponseMapper.fromJson;
}

@MappableClass()
class GamebaseData with GamebaseDataMappable {
  const GamebaseData({required this.moves});

  final List<MoveAggregate> moves;

  static const fromJson = GamebaseDataMapper.fromJson;
}

class GamebaseRepository {
  final Dio _dio;
  final String _apiKey;
  final String _baseUrl;

  // NOTE: The backend requires an API key. Prefer supplying it via
  // `--dart-define=GAMEBASE_API_KEY=...` (release) or `.env` (debug).
  // This fallback preserves current behavior but should be removed once keys
  // are fully externalized.
  static const String _fallbackApiKey =
      '4e1b7d20-db18-41ae-8e48-5a35c127aeef';

  GamebaseRepository(
    this._dio, {
    String? baseUrl,
    String? apiKey,
  })  : _baseUrl = baseUrl ?? 'https://service.chessever.com',
        _apiKey = apiKey ?? _resolveApiKey();

  static String _resolveApiKey() {
    if (kDebugMode) {
      final envKey = dotenv.env['GAMEBASE_API_KEY']?.trim();
      if (envKey != null && envKey.isNotEmpty) return envKey;
    } else {
      const envKey =
          String.fromEnvironment('GAMEBASE_API_KEY', defaultValue: '');
      if (envKey.isNotEmpty) return envKey;
    }
    return _fallbackApiKey;
  }

  Future<GamebaseResponse> getMoveAggregates({
    required String fen,
    String? playerId,
    TimeControl? timeControl,
    int? minRating,
    int? maxRating,
  }) async {
    try {
      final queryParams = {
        'fen': fen,
        if (playerId != null && playerId.isNotEmpty) 'playerId': playerId,
        if (timeControl != null)
          'timeControl': timeControl.name.toUpperCase(),
        if (minRating != null) 'minRating': minRating,
        if (maxRating != null) 'maxRating': maxRating,
      };

      final response = await _dio.get(
        '$_baseUrl/api/game-position/aggregates',
        queryParameters: queryParams,
        options: Options(
          headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
        ),
      );

      return GamebaseResponseMapper.fromMap(response.data);
    } catch (e) {
      throw Exception('Failed to load gamebase stats: $e');
    }
  }

  Future<List<GamebasePlayer>> getPlayers({
    String? name,
    String? fideId,
    int pageNumber = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/player',
        queryParameters: {
          'pageNumber': pageNumber,
          'pageSize': pageSize,
          if (name != null && name.isNotEmpty) 'name': name,
          if (fideId != null && fideId.isNotEmpty) 'fideId': fideId,
        },
        options: Options(
          headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
        ),
      );

      final List data = response.data['data'] ?? [];
      return data.map((e) => GamebasePlayer.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to search players: $e');
    }
  }

  Future<GamebasePlayer?> getPlayerById(String id) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/player/$id',
        options: Options(
          headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
        ),
      );

      return GamebasePlayer.fromJson(response.data['data']);
    } catch (e) {
      return null;
    }
  }

  Future<GamebaseGame?> getGameById(String id) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/game/$id',
        options: Options(
          headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
        ),
      );

      return GamebaseGame.fromJson(response.data['data']);
    } catch (e) {
      return null;
    }
  }

  Future<GamebaseSearchMetadata> getSearchMetadata() async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/search/metadata',
        options: Options(
          headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
        ),
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }

      final map = Map<String, dynamic>.from(data);
      final payload = map['data'];
      if (payload is! Map) {
        throw Exception('Unexpected response payload');
      }

      return GamebaseSearchMetadata.fromJson(Map<String, dynamic>.from(payload));
    } catch (e) {
      throw Exception('Failed to load search metadata: $e');
    }
  }

  Future<GamebaseSearchQueryResponse> queryResource({
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/api/search/query',
        data: body,
        options: Options(
          headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
        ),
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }
      return GamebaseSearchQueryResponse.fromJson(
        Map<String, dynamic>.from(data),
      );
    } catch (e) {
      throw Exception('Failed to query resource: $e');
    }
  }
}

final gamebaseRepositoryProvider = Provider<GamebaseRepository>((ref) {
  return GamebaseRepository(Dio());
});
