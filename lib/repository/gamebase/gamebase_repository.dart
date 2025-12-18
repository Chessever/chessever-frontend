import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models_extra.dart';

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
  static const String _fallbackApiKey = '4e1b7d20-db18-41ae-8e48-5a35c127aeef';

  GamebaseRepository(this._dio, {String? baseUrl, String? apiKey})
    : _baseUrl = baseUrl ?? 'https://service.chessever.com',
      _apiKey = apiKey ?? _resolveApiKey();

  static String _resolveApiKey() {
    if (kDebugMode) {
      final envKey = dotenv.env['GAMEBASE_API_KEY']?.trim();
      if (envKey != null && envKey.isNotEmpty) return envKey;
    } else {
      const envKey = String.fromEnvironment(
        'GAMEBASE_API_KEY',
        defaultValue: '',
      );
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
      final normalizedFen = _normalizeFenForLookup(fen);
      final queryParams = {
        'fen': normalizedFen,
        if (playerId != null && playerId.isNotEmpty) 'playerId': playerId,
        if (timeControl != null) 'timeControl': timeControl.name.toUpperCase(),
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

  /// Canonicalize FEN for Gamebase lookups by clamping the halfmove/fullmove
  /// counters to stable values. The database is indexed by position, not by
  /// move counters.
  static String _normalizeFenForLookup(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return fen.trim();
    return '${parts.take(4).join(' ')} 0 1';
  }

  /// Search players by name.
  /// Note: pageNumber is 0-indexed per the API spec.
  Future<List<GamebasePlayer>> getPlayers({
    String? name,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    try {
      final queryParams = {
        'pageNumber': pageNumber,
        'pageSize': pageSize,
        if (name != null && name.isNotEmpty) 'name': name,
      };

      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getPlayers: name="$name" page=$pageNumber');
      }

      final response = await _dio.get(
        '$_baseUrl/api/player',
        queryParameters: queryParams,
        options: Options(
          headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
        ),
      );

      final List data = response.data['data'] ?? [];
      return data.map((e) => GamebasePlayer.fromJson(e)).toList();
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getPlayers DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
        debugPrint('  Response: ${e.response?.data}');
      }
      throw Exception('Failed to search players: ${e.response?.statusCode ?? 'network error'} - ${e.message}');
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

  /// Fetch a game by ID with full PGN included.
  /// Returns a [GamebaseGameWithPgn] containing the game data and raw PGN.
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/game/$id',
        queryParameters: {'includePgn': true},
        options: Options(
          headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
        ),
      );

      final data = response.data['data'];
      if (data == null) return null;

      return GamebaseGameWithPgn.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getGameWithPgn DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getGameWithPgn error: $e');
      }
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
      // The backend returns { status: "success", data: { resources: [...] } }
      // So we need to dig into 'data' first.
      final payload = map['data'];
      if (payload is! Map) {
        throw Exception('Unexpected response payload');
      }

      return GamebaseSearchMetadata.fromJson(
        Map<String, dynamic>.from(payload),
      );
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

  Future<GamebaseGlobalSearchResponse> globalSearch({
    required String query,
    List<String>? resources,
    int pageNumber = 1,
    int pageSize = 20,
  }) async {
    try {
      final queryParams = {
        'q': query,
        'pageNumber': pageNumber,
        'pageSize': pageSize,
        if (resources != null) 'resources': resources,
      };

      if (kDebugMode) {
        debugPrint('[GamebaseRepository] globalSearch: q="$query" page=$pageNumber');
      }

      final response = await _dio.get(
        '$_baseUrl/api/search',
        queryParameters: queryParams,
        options: Options(
          headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
        ),
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }
      return GamebaseGlobalSearchResponse.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] globalSearch DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
        debugPrint('  Response: ${e.response?.data}');
      }
      throw Exception('Failed to perform global search: ${e.response?.statusCode ?? 'network error'} - ${e.message}');
    } catch (e) {
      throw Exception('Failed to perform global search: $e');
    }
  }
}

final gamebaseRepositoryProvider = Provider<GamebaseRepository>((ref) {
  return GamebaseRepository(Dio());
});
