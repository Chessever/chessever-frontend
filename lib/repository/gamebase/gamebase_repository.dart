import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';

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
  final String _apiKey = '4e1b7d20-db18-41ae-8e48-5a35c127aeef';
  final String _baseUrl = 'https://service.chessever.com';

  GamebaseRepository(this._dio);

  Future<GamebaseResponse> getMoveAggregates({
    required String fen,
    List<String>? playerIds,
    List<String>? timeControls,
    int? minRating,
    int? maxRating,
  }) async {
    try {
      final queryParams = {
        'fen': fen,
        if (minRating != null) 'minRating': minRating,
        if (maxRating != null) 'maxRating': maxRating,
      };

      if (playerIds != null && playerIds.isNotEmpty) {
        queryParams['playerIds'] = playerIds.join(',');
      }

      if (timeControls != null && timeControls.isNotEmpty) {
        queryParams['timeControls'] = timeControls.join(',');
      }

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
    required String name,
    int limit = 20,
  }) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/players',
        queryParameters: {'name': name, 'limit': limit},
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
        '$_baseUrl/api/players/$id',
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
        '$_baseUrl/api/games/$id',
        options: Options(
          headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
        ),
      );

      return GamebaseGame.fromJson(response.data['data']);
    } catch (e) {
      return null;
    }
  }
}

final gamebaseRepositoryProvider = Provider<GamebaseRepository>((ref) {
  return GamebaseRepository(Dio());
});
