import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/config/gamebase_environment.dart';
import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:chessever2/config/app_environment.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:chessever2/main.dart';
import 'package:logarte/logarte.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/repository/gamebase/collections/collections_models.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models_extra.dart';
import 'package:chessever2/repository/gamebase/memorial_player.dart';

import 'explorer_query.dart';

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

class MissingGamebaseApiKeyException implements Exception {
  const MissingGamebaseApiKeyException();

  @override
  String toString() {
    return 'Missing GAMEBASE_API_KEY. Generate a personal developer key from '
        'https://chessever.com/developers and pass it with --dart-define or '
        '--dart-define-from-file.';
  }
}

/// One HTTP request exactly as a [GamebaseRepository] method sends it: the
/// method, the full URL (base URL included) and the body or query map.
@immutable
class GamebaseWireRequest {
  const GamebaseWireRequest({
    required this.method,
    required this.url,
    required this.payload,
  });

  /// `GET` or `POST`.
  final String method;
  final String url;

  /// The POST body, or the GET query parameters.
  final Map<String, dynamic> payload;

  /// A stable text form of the whole request, with map keys sorted at every
  /// level, so two requests that would put the same bytes on the wire always
  /// produce the same identity whatever order their fields were built in.
  String get identity => jsonEncode(<String, Object?>{
    'method': method,
    'url': url,
    'payload': _canonicalJson(payload),
  });

  static Object? _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalJson(value[key]),
      };
    }
    if (value is Iterable) {
      return value.map(_canonicalJson).toList(growable: false);
    }
    return value;
  }

  @override
  String toString() => 'GamebaseWireRequest($method $url $payload)';
}

class GamebaseRepository {
  final Dio _dio;
  final String _apiKey;
  final String _baseUrl;

  GamebaseRepository(this._dio, {String? baseUrl, String? apiKey})
    : _baseUrl = baseUrl ?? GamebaseEnvironment.baseUrl,
      _apiKey = (apiKey ?? _resolveApiKey()).trim();

  static String _resolveApiKey() {
    if (AppEnvironment.isTest) return GamebaseEnvironment.testApiKey;
    const releaseKey = String.fromEnvironment(
      'GAMEBASE_API_KEY',
      defaultValue: '',
    );

    if (releaseKey.isNotEmpty) {
      return releaseKey;
    }

    if (kDebugMode && !AppEnvironment.isTest) {
      final envKey = dotenv.env['GAMEBASE_API_KEY']?.trim();
      if (envKey != null && envKey.isNotEmpty) return envKey;
    } else {
      if (releaseKey.isNotEmpty) return releaseKey;
    }
    return '';
  }

  bool get hasApiKey => _apiKey.isNotEmpty;

  /// Cold replay-backed aggregate queries (any position past the server's
  /// fast indexed window) can legitimately outlast the repository-wide
  /// 30s receive timeout, so this endpoint gets a wider per-request window
  /// and one retry. Without it a slow deep position surfaces as an error
  /// instead of a move table.
  static const Duration _aggregateReceiveTimeout = Duration(seconds: 75);
  static const Duration _aggregateTimeoutRetryDelay = Duration(
    milliseconds: 400,
  );
  static const int _aggregateReceiveTimeoutRetries = 1;

  Map<String, String> get _headers {
    if (_baseUrl.isEmpty) {
      throw StateError(
        'Set GAMEBASE_TEST_BASE_URL to the test Gamebase service.',
      );
    }
    if (!hasApiKey) throw const MissingGamebaseApiKeyException();
    return {'X-API-Key': _apiKey, 'Accept': 'application/json'};
  }

  /// Filter keys shared by aggregates and position-games requests.
  /// Null / empty values are omitted so the backend ANDs only present keys.
  @visibleForTesting
  static Map<String, dynamic> buildExplorerQueryFilterFields({
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    bool? isOnline,
  }) {
    return gamebaseExplorerFilterFields(
      timeControl: timeControl?.name,
      playerId: playerId,
      minRating: minRating,
      maxRating: maxRating,
      color: color,
      result: result,
      yearFrom: yearFrom,
      yearTo: yearTo,
      isOnline: isOnline,
    );
  }

  /// POST body for `/api/game-position/aggregates/query`.
  @visibleForTesting
  static Map<String, dynamic> buildMoveAggregatesQueryBody({
    required String fen,
    List<String> moves = const [],
    String? playerId,
    TimeControl? timeControl,
    int? minRating,
    int? maxRating,
    String? color,
    String? result,
    int? yearFrom,
    int? yearTo,
    bool? isOnline,
  }) {
    final position = GamebaseExplorerPosition.resolve(fen, moves);
    final normalizedMoves = position.moves;
    return <String, dynamic>{
      'fen': position.fen,
      'moves': normalizedMoves,
      ...buildExplorerQueryFilterFields(
        timeControl: timeControl,
        playerId: playerId,
        color: color,
        result: result,
        minRating: minRating,
        maxRating: maxRating,
        yearFrom: yearFrom,
        yearTo: yearTo,
        isOnline: isOnline,
      ),
    };
  }

  /// Request map for position-games: POST body when [moves] survive
  /// sanitization, otherwise GET query parameters.
  @visibleForTesting
  static Map<String, dynamic> buildPositionGamesQueryBody({
    required String fen,
    List<String> moves = const [],
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int notationPlies = 0,
    int pageNumber = 0,
    int pageSize = 20,
  }) {
    final position = GamebaseExplorerPosition.resolve(fen, moves);
    final normalizedMoves = position.moves;
    final trimmedPlayerId = playerId?.trim();
    final trimmedUci = position.continuationUci(uci);
    final filters = buildExplorerQueryFilterFields(
      timeControl: timeControl,
      playerId: trimmedPlayerId != null && trimmedPlayerId.isNotEmpty
          ? trimmedPlayerId
          : null,
      color: color,
      result: result,
      minRating: minRating,
      maxRating: maxRating,
      yearFrom: yearFrom,
      yearTo: yearTo,
      isOnline: isOnline,
    );

    if (normalizedMoves.isNotEmpty) {
      final orderBy = sortBy != null
          ? [
              {
                'field': sortBy.name,
                'direction': sortDirection == GamebaseSortDirection.asc
                    ? 'asc'
                    : 'desc',
              },
            ]
          : null;
      return <String, dynamic>{
        'fen': position.fen,
        'moves': normalizedMoves,
        ...gamebaseExplorerPageFields(
          pageNumber: pageNumber,
          pageSize: pageSize,
          notationPlies: notationPlies,
        ),
        if (trimmedUci != null && trimmedUci.isNotEmpty) 'uci': trimmedUci,
        ...filters,
        if (orderBy != null) 'orderBy': orderBy,
        if (sortBy != null) 'sortBy': sortBy.name,
        if (sortDirection != null) 'sortDirection': sortDirection.name,
      };
    }

    return <String, dynamic>{
      'fen': position.fen,
      ...gamebaseExplorerPageFields(
        pageNumber: pageNumber,
        pageSize: pageSize,
        notationPlies: notationPlies,
      ),
      if (trimmedUci != null && trimmedUci.isNotEmpty) 'uci': trimmedUci,
      ...filters,
      if (sortBy != null) 'sortBy': sortBy.name,
      if (sortDirection != null) 'sortDirection': sortDirection.name,
    };
  }

  /// Query parameters for the exact-FEN position-search games endpoint.
  ///
  /// Kept as a pure builder so the FEN surface is covered by the same complete
  /// filter/sort matrix as the move-line Opening Explorer surface.
  @visibleForTesting
  static Map<String, dynamic> buildFenPositionGamesQueryParameters({
    required String fen,
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int notationPlies = 0,
    int pageNumber = 0,
    int pageSize = 20,
  }) {
    final position = GamebaseExplorerPosition.resolve(fen, const []);
    final trimmedPlayerId = playerId?.trim();
    final trimmedUci = position.continuationUci(uci);
    return <String, dynamic>{
      'fen': position.fen,
      ...gamebaseExplorerPageFields(
        pageNumber: pageNumber,
        pageSize: pageSize,
        notationPlies: notationPlies,
      ),
      if (trimmedUci != null && trimmedUci.isNotEmpty) 'uci': trimmedUci,
      ...buildExplorerQueryFilterFields(
        timeControl: timeControl,
        playerId: trimmedPlayerId != null && trimmedPlayerId.isNotEmpty
            ? trimmedPlayerId
            : null,
        color: color,
        result: result,
        minRating: minRating,
        maxRating: maxRating,
        yearFrom: yearFrom,
        yearTo: yearTo,
        isOnline: isOnline,
      ),
      if (sortBy != null) 'sortBy': sortBy.name,
      if (sortDirection != null) 'sortDirection': sortDirection.name,
    };
  }

  Future<GamebaseResponse> getMoveAggregates({
    required String fen,
    List<String> moves = const [],
    String? playerId,
    TimeControl? timeControl,
    int? minRating,
    int? maxRating,
    String? color,
    String? result,
    int? yearFrom,
    int? yearTo,
    bool? isOnline,
  }) async {
    try {
      final body = buildMoveAggregatesQueryBody(
        fen: fen,
        moves: moves,
        playerId: playerId,
        timeControl: timeControl,
        minRating: minRating,
        maxRating: maxRating,
        color: color,
        result: result,
        yearFrom: yearFrom,
        yearTo: yearTo,
        isOnline: isOnline,
      );

      if (kDebugMode &&
          moves.isNotEmpty &&
          (body['moves'] as List).length != moves.length) {
        debugPrint(
          '[GamebaseRepository] Dropping mismatched move path for aggregates query',
        );
      }

      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getMoveAggregates:');
        debugPrint('  URL: $_baseUrl/api/game-position/aggregates/query');
        debugPrint(
          '  Body: ${{
            ...body,
            // Avoid dumping huge move lists in logs
            if (moves.length > 8) 'moves': '[${moves.length} moves]',
          }}',
        );
      }

      // Use POST /aggregates/query so the backend can compute deep move trees
      // beyond the pre-indexed opening window.
      late final Response<dynamic> response;
      for (var attempt = 0; ; attempt++) {
        try {
          response = await _dio.post(
            '$_baseUrl/api/game-position/aggregates/query',
            data: body,
            options: Options(
              headers: _headers,
              receiveTimeout: _aggregateReceiveTimeout,
            ),
          );
          break;
        } on DioException catch (e) {
          // Treat "no data for this position" as an empty result, not an
          // error. This is common for uncommon/midgame positions.
          if (e.response?.statusCode == 404) {
            return const GamebaseResponse(
              status: 'success',
              data: GamebaseData(moves: []),
            );
          }

          if (e.type == DioExceptionType.receiveTimeout &&
              attempt < _aggregateReceiveTimeoutRetries) {
            if (kDebugMode) {
              debugPrint(
                '[GamebaseRepository] aggregates receive timeout; retrying once',
              );
            }
            await Future<void>.delayed(_aggregateTimeoutRetryDelay);
            continue;
          }
          rethrow;
        }
      }

      if (kDebugMode) {
        final moves = response.data['data']?['moves'] as List?;
        debugPrint('  Response: ${moves?.length ?? 0} moves returned');
      }

      return GamebaseResponseMapper.fromMap(response.data);
    } on DioException catch (e) {
      // Treat "no data for this position" as an empty result, not an error.
      // This is common for uncommon/midgame positions.
      if (e.response?.statusCode == 404) {
        return const GamebaseResponse(
          status: 'success',
          data: GamebaseData(moves: []),
        );
      }
      throw Exception('Failed to load gamebase stats: $e');
    } catch (e) {
      throw Exception('Failed to load gamebase stats: $e');
    }
  }

  /// The other classical/dartchess spelling of a castling move.
  static String? alternateCastlingUci(String uci) =>
      alternateGamebaseCastlingUci(uci);

  /// Search players by name.
  /// Note: pageNumber is 0-indexed per the API spec.
  Future<List<GamebasePlayer>> getPlayers({
    String? name,
    String? fideId,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    try {
      final queryParams = {
        'pageNumber': pageNumber,
        'pageSize': pageSize,
        if (name != null && name.isNotEmpty) 'name': name,
        if (fideId != null && fideId.isNotEmpty) 'fideId': fideId,
      };

      if (kDebugMode) {
        debugPrint(
          '[GamebaseRepository] getPlayers: name="$name" page=$pageNumber',
        );
      }

      final response = await _dio.get(
        '$_baseUrl/api/player',
        queryParameters: queryParams,
        options: Options(headers: _headers),
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
      throw Exception(
        'Failed to search players: ${e.response?.statusCode ?? 'network error'} - ${e.message}',
      );
    } catch (e) {
      throw Exception('Failed to search players: $e');
    }
  }

  Future<GamebasePlayer?> getPlayerById(String id) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/player/$id',
        options: Options(headers: _headers),
      );

      return GamebasePlayer.fromJson(response.data['data']);
    } catch (e) {
      return null;
    }
  }

  Future<List<MemorialPlayer>> getMemorialPlayers({
    String? name,
    String? federation,
    bool includeWithoutGames = false,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    final response = await _dio.get(
      '$_baseUrl/api/player/memorial',
      queryParameters: <String, dynamic>{
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (federation != null && federation.trim().isNotEmpty)
          'fed': federation.trim().toUpperCase(),
        'includeWithoutGames': includeWithoutGames,
        'pageNumber': pageNumber,
        'pageSize': pageSize,
      },
      options: Options(headers: _headers),
    );
    final data = response.data['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => MemorialPlayer.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<GamebaseGame?> getGameById(String id) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/game/$id',
        options: Options(headers: _headers),
      );

      return GamebaseGame.fromJson(response.data['data']);
    } catch (e) {
      return null;
    }
  }

  /// Fetch a game by ID with full PGN included.
  /// Returns a [GamebaseGameWithPgn] containing the game data and raw PGN.
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async {
    if (kDebugMode) {
      debugPrint('[GamebaseRepository] getGameWithPgn called with id: $id');
    }
    try {
      final response = await _dio.get(
        '$_baseUrl/api/game/$id',
        queryParameters: {'includePgn': true},
        options: Options(headers: _headers),
      );

      final data = response.data['data'];
      if (data == null) {
        if (kDebugMode) {
          debugPrint('[GamebaseRepository] API returned null data for id: $id');
        }
        return null;
      }

      if (kDebugMode) {
        final dataMap = Map<String, dynamic>.from(data);
        debugPrint(
          '[GamebaseRepository] API response keys: ${dataMap.keys.toList()}',
        );
        debugPrint(
          '[GamebaseRepository] pgn present: ${dataMap['pgn'] != null}, length: ${(dataMap['pgn'] as String?)?.length ?? 0}',
        );
        debugPrint(
          '[GamebaseRepository] data field present: ${dataMap['data'] != null}',
        );
        if (dataMap['data'] != null) {
          final innerData = dataMap['data'];
          if (innerData is Map) {
            debugPrint(
              '[GamebaseRepository] inner data keys: ${innerData.keys.toList()}',
            );
          }
        }
      }

      return GamebaseGameWithPgn.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getGameWithPgn DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
        debugPrint('  URL: $_baseUrl/api/game/$id');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getGameWithPgn error: $e');
      }
      return null;
    }
  }

  /// Fetch decisive short games from the Gamebase miniatures index.
  ///
  /// The backend defines miniatures as decisive games ending by move 25.
  /// Pagination is offset-based; sorting/filtering happens server-side via
  /// [MiniatureGamesFilter.queryParameters] (mirrors the desktop app).
  Future<GamebaseMiniaturesPage> getMiniatures({
    MiniatureGamesFilter filter = MiniatureGamesFilter.defaultFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/miniatures',
        queryParameters: filter.queryParameters(limit: limit, offset: offset),
        options: Options(headers: _headers),
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }
      return GamebaseMiniaturesPage.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getMiniatures DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
      }
      throw Exception(
        'Failed to load miniatures: ${e.response?.statusCode ?? 'network error'} - ${e.message}',
      );
    } catch (e) {
      throw Exception('Failed to load miniatures: $e');
    }
  }

  /// Aggregate figures for the Miniatures About tab.
  ///
  /// The backend applies the same filter builder as the list endpoint, so the
  /// stats always describe the slice the user is currently looking at.
  Future<MiniatureStats> getMiniatureStats({
    MiniatureGamesFilter filter = MiniatureGamesFilter.defaultFilter,
    int dailyDays = 30,
    int openingLimit = 12,
    int notableLimit = 5,
  }) async {
    try {
      // Reuse the list query params, then drop the paging/sorting keys the
      // stats endpoint does not accept.
      final params =
          Map<String, dynamic>.from(filter.queryParameters(limit: 1, offset: 0))
            ..removeWhere(
              (key, _) =>
                  const {'limit', 'offset', 'sort', 'order'}.contains(key),
            );
      params['dailyDays'] = dailyDays;
      params['openingLimit'] = openingLimit;
      params['notableLimit'] = notableLimit;

      final response = await _dio.get(
        '$_baseUrl/api/miniatures/stats',
        queryParameters: params,
        options: Options(headers: _headers),
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }
      return MiniatureStats.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getMiniatureStats DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
      }
      throw Exception(
        'Failed to load miniature stats: ${e.response?.statusCode ?? 'network error'} - ${e.message}',
      );
    } catch (e) {
      throw Exception('Failed to load miniature stats: $e');
    }
  }

  /// Leaderboard of the players appearing in the most miniatures.
  Future<MiniaturePlayersPage> getMiniaturePlayers({
    MiniatureGamesWindow window = MiniatureGamesWindow.all,
    MiniaturePlayerSort sort = MiniaturePlayerSort.games,
    Set<MiniaturePlayerTitle> titles = const {},
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final searchClean = (search ?? '').trim();
      final response = await _dio.get(
        '$_baseUrl/api/miniatures/players',
        queryParameters: {
          'window': window.apiValue,
          'sort': sort.apiValue,
          'limit': limit,
          'offset': offset,
          if (titles.isNotEmpty)
            'title': titles.map((t) => t.apiValue).join(','),
          if (searchClean.isNotEmpty) 'q': searchClean,
        },
        options: Options(headers: _headers),
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }
      return MiniaturePlayersPage.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getMiniaturePlayers DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
      }
      throw Exception(
        'Failed to load miniature players: ${e.response?.statusCode ?? 'network error'} - ${e.message}',
      );
    } catch (e) {
      throw Exception('Failed to load miniature players: $e');
    }
  }

  Future<String> uploadProfileAvatar(
    Uint8List bytes, {
    required String bearer,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/api/collections/account/avatar',
        data: Stream.value(bytes),
        options: Options(
          headers: {
            ..._headers,
            'Authorization': 'Bearer $bearer',
            'Content-Type': 'image/png',
            'Content-Length': bytes.length.toString(),
          },
          followRedirects: false,
        ),
      );
      final data = unwrapCollectionsEnvelope(
        response.data,
        statusCode: response.statusCode,
      );
      if (data is! Map || data['avatarUrl'] is! String) {
        throw const FormatException('Invalid profile photo response');
      }
      return data['avatarUrl'] as String;
    } on DioException catch (error) {
      if (error.response?.data is Map) {
        unwrapCollectionsEnvelope(
          error.response!.data,
          statusCode: error.response?.statusCode,
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> recordCollectionEngagement(
    String slug,
    Map<String, dynamic> body, {
    String? bearer,
    bool star = false,
  }) async {
    final response = await _dio.request(
      '$_baseUrl/api/collections/${Uri.encodeComponent(slug)}/${star ? 'star' : 'view'}',
      data: body,
      options: Options(
        method: star ? 'PUT' : 'POST',
        headers: {
          ..._headers,
          if (bearer != null) 'Authorization': 'Bearer $bearer',
        },
      ),
    );
    return Map<String, dynamic>.from(
      unwrapCollectionsEnvelope(response.data) as Map,
    );
  }

  /// Folder publishing uses the existing native API transport. Browser
  /// challenges on the public website must not block Library operations.
  Future<Map<String, dynamic>> requestLibraryBookPublication({
    required String folderId,
    required String method,
    required String bearer,
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    if (!const {'GET', 'PUT', 'DELETE'}.contains(method)) {
      throw ArgumentError.value(method, 'method');
    }
    final response = await _dio.request<Map<String, dynamic>>(
      '$_baseUrl/api/library/folders/${Uri.encodeComponent(folderId)}/book',
      data: body,
      queryParameters: query,
      options: Options(
        method: method,
        followRedirects: false,
        receiveTimeout: const Duration(minutes: 5),
        headers: {..._headers, 'Authorization': 'Bearer $bearer'},
      ),
    );
    final data = response.data;
    if (data == null) throw const FormatException('Missing publication');
    return data;
  }

  /// One page of the published collections (`GET /api/collections`),
  /// ordered by the team's sort order, newest first within it.
  Future<CollectionsPage> getCollections({
    CollectionKind? kind,
    String? query,
    int limit = 30,
    int offset = 0,
  }) async {
    final q = (query ?? '').trim();
    final data = await _getCollectionsData(
      '/api/collections',
      what: 'collections',
      queryParameters: {
        if (kind != null) 'kind': kind.apiValue,
        if (q.isNotEmpty) 'q': q,
        'limit': limit,
        'offset': offset,
      },
    );
    return CollectionsPage.fromJson(data);
  }

  /// A published collection with its About text and section tree
  /// (`GET /api/collections/:slug`; an id works too). [bearer] is the
  /// viewer's session token: with it the server judges a Premium
  /// collection's `contentLocked` for them. [fresh] asks it to judge anew
  /// rather than repeat a "not Premium" it still holds (right after a
  /// purchase).
  Future<Collection> getCollection(
    String slug, {
    String? bearer,
    bool fresh = false,
  }) async {
    final data = await _getCollectionsData(
      '/api/collections/${Uri.encodeComponent(slug)}',
      what: 'collection',
      bearer: bearer,
      fresh: fresh,
    );
    if (data is! Map) {
      throw const FormatException('Unexpected collection response format');
    }
    return Collection.fromJson(Map<String, dynamic>.from(data));
  }

  /// One page of a collection's games in section-tree order
  /// (`GET /api/collections/:slug/games`). [includePgn] adds each game's
  /// whole PGN, which the board needs to replay it. A Premium collection
  /// answers only a [bearer] whose account is entitled; anyone else gets a
  /// [CollectionsRequestException] with [CollectionsRequestException.isPremiumGate].
  /// [fresh] as for [getCollection].
  Future<CollectionGamesPage> getCollectionGames(
    String slug, {
    String? section,
    String? playerKey,
    String? eco,
    CollectionSearchQuery search = const CollectionSearchQuery(),
    bool includePgn = false,
    int limit = 100,
    int offset = 0,
    String? bearer,
    bool fresh = false,
  }) async {
    final data = await _getCollectionsData(
      '/api/collections/${Uri.encodeComponent(slug)}/games',
      what: 'collection games',
      bearer: bearer,
      fresh: fresh,
      queryParameters: {
        ...search.parameters,
        if (section != null && section.isNotEmpty) 'section': section,
        if (playerKey != null && playerKey.isNotEmpty) 'player': playerKey,
        if (eco != null && eco.isNotEmpty) 'eco': eco,
        if (includePgn) 'include': 'pgn',
        'limit': limit,
        'offset': offset,
      },
    );
    return CollectionGamesPage.fromJson(data);
  }

  Future<({List<String> items, int total})> getCollectionAuthors({
    int offset = 0,
    int limit = 100,
  }) async {
    final data = await _getCollectionsData(
      '/api/collections/catalog/authors',
      what: 'collection authors',
      queryParameters: {'offset': offset, 'limit': limit},
    );
    if (data is! Map || data['items'] is! List || data['total'] is! num) {
      throw const FormatException('Invalid collection authors response');
    }
    return (
      items: [for (final item in data['items'] as List) item['name'] as String],
      total: (data['total'] as num).toInt(),
    );
  }

  Future<({List<CollectionAuthor> items, int total})> searchCollectionAuthors({
    CollectionSearchQuery search = const CollectionSearchQuery(),
    int offset = 0,
    int limit = 40,
  }) async {
    final data = await _getCollectionsData(
      '/api/collections/catalog/authors',
      what: 'collection authors',
      queryParameters: {...search.parameters, 'offset': offset, 'limit': limit},
    );
    if (data is! Map || data['items'] is! List || data['total'] is! num) {
      throw const FormatException('Invalid collection authors response');
    }
    return (
      items: [
        for (final item in data['items'] as List)
          if (item is Map)
            CollectionAuthor.fromJson(Map<String, dynamic>.from(item)),
      ],
      total: (data['total'] as num).toInt(),
    );
  }

  Future<CollectionsPage> searchCollectionBooks({
    CollectionSearchQuery search = const CollectionSearchQuery(),
    int limit = 40,
    int offset = 0,
  }) async => CollectionsPage.fromJson(
    await _getCollectionsData(
      '/api/collections/catalog/books',
      what: 'collection search',
      queryParameters: {...search.parameters, 'limit': limit, 'offset': offset},
    ),
  );

  Future<CollectionOpeningsPage> getCollectionOpenings({
    String? slug,
    CollectionSearchQuery search = const CollectionSearchQuery(),
    int limit = 100,
    int offset = 0,
  }) async {
    final data = await _getCollectionsData(
      slug == null
          ? '/api/collections/openings'
          : '/api/collections/${Uri.encodeComponent(slug)}/openings',
      what: 'collection openings',
      queryParameters: {...search.parameters, 'limit': limit, 'offset': offset},
    );
    return CollectionOpeningsPage.fromJson(data);
  }

  Future<CollectionsPage> getBooksForOpening(
    String eco, {
    int limit = 100,
    int offset = 0,
  }) async {
    final data = await _getCollectionsData(
      '/api/collections/for-opening',
      what: 'books for opening',
      queryParameters: {'eco': eco, 'limit': limit, 'offset': offset},
    );
    return CollectionsPage.fromJson(data);
  }

  /// A bounded page of readable games across published books. The server
  /// enforces access before including a PGN and supplies its source book.
  Future<CollectionGamesPage> getPublishedCollectionGames({
    CollectionSearchQuery search = const CollectionSearchQuery(),
    int limit = 40,
    int offset = 0,
    String? bearer,
  }) async {
    final data = await _getCollectionsData(
      '/api/collections/games',
      what: 'published collection games',
      bearer: bearer,
      queryParameters: {
        ...search.parameters,
        'include': 'pgn',
        'limit': limit,
        'offset': offset,
      },
    );
    return CollectionGamesPage.fromJson(data);
  }

  /// Everyone who played in a collection, most games first
  /// (`GET /api/collections/:slug/players`). Gated like the games;
  /// [fresh] as for [getCollection].
  Future<List<CollectionPlayer>> getCollectionPlayers(
    String slug, {
    String? bearer,
    bool fresh = false,
  }) async {
    final data = await _getCollectionsData(
      '/api/collections/${Uri.encodeComponent(slug)}/players',
      what: 'collection players',
      bearer: bearer,
      fresh: fresh,
    );
    return CollectionPlayer.listFromJson(data);
  }

  /// The published collections (books unless [kind] says otherwise) bound
  /// to the event [anchors] name (`GET /api/collections/for-event`), each
  /// with the team's note for the binding. Public: covers and titles are
  /// the preview.
  Future<List<Collection>> getCollectionsForEvent(
    CollectionEventAnchors anchors, {
    CollectionKind kind = CollectionKind.book,
  }) async {
    if (anchors.isEmpty) return const [];
    final data = await _getCollectionsData(
      '/api/collections/for-event',
      what: 'event collections',
      queryParameters: anchors.toQuery(kind: kind),
    );
    return collectionsForEventFromJson(data);
  }

  /// GETs a collections endpoint and returns its envelope's `data`. List
  /// values in [queryParameters] repeat their key (`?tour=a&tour=b`).
  /// [fresh] sends `Cache-Control: no-cache` (and `Pragma` for proxies that
  /// only read that), which gamebase takes as "check my Premium again".
  Future<Object?> _getCollectionsData(
    String path, {
    required String what,
    Map<String, dynamic>? queryParameters,
    String? bearer,
    bool fresh = false,
  }) async {
    try {
      final response = await _dio.get(
        '$_baseUrl$path',
        queryParameters: queryParameters,
        options: Options(
          headers: {
            ..._headers,
            if (bearer != null && bearer.isNotEmpty)
              'Authorization': 'Bearer $bearer',
            if (fresh) ...{'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
          },
          listFormat: ListFormat.multi,
        ),
      );
      return unwrapCollectionsEnvelope(
        response.data,
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] $what DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
      }
      // Gamebase answers every refusal (404 unpublished slug, 400 validation)
      // with a 4xx/5xx `{status: "error"}` envelope, which Dio throws on.
      // Surface that message; fall back only when the body is not one.
      final body = e.response?.data;
      if (body is Map && body['status'] == 'error') {
        unwrapCollectionsEnvelope(body, statusCode: e.response?.statusCode);
      }
      throw Exception(
        'Failed to load $what: ${e.response?.statusCode ?? 'network error'} - ${e.message}',
      );
    }
  }

  Future<CloudEval?> getEvalByFen(String fen) async {
    try {
      final normalizedFen = _normalizeEvalFenForLookup(fen);
      final response = await _dio.get(
        '$_baseUrl/api/eval',
        queryParameters: {'fen': normalizedFen},
        options: Options(headers: _headers),
      );

      if (response.data['status'] == 'success') {
        return CloudEval.fromJson(
          Map<String, dynamic>.from(response.data['data']),
        );
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getEvalByFen error: $e');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getEvalByFen error: $e');
      }
      return null;
    }
  }

  /// Canonicalize FEN for the eval endpoint.
  ///
  /// The backend accepts either 6-field or normalized 4-field FENs, but the
  /// client always sends the canonical 4-field form for stable cache keys.
  ///
  /// The eval service keys positions by the first four FEN fields only:
  /// board, side to move, castling rights, en passant square.
  static String _normalizeEvalFenForLookup(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return fen.trim();
    return parts.take(4).join(' ');
  }

  Future<GamebaseSearchMetadata> getSearchMetadata() async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/search/metadata',
        options: Options(headers: _headers),
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
        options: Options(headers: _headers),
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

  /// Fetch the synthesized event view for an exact event [name] from the
  /// gamebase (`GET /api/event`). Returns null when the event has no games.
  /// [refresh] forces a server-side rebuild + cache rewarm — used while
  /// verifying the view before the one-week cache is trusted.
  Future<GamebaseEventView?> getEventView(
    String name, {
    String? site,
    String? slug,
    bool refresh = false,
  }) async {
    try {
      final trimmedSite = site?.trim();
      final trimmedSlug = slug?.trim();
      final response = await _dio.get(
        '$_baseUrl/api/event',
        queryParameters: {
          'name': name,
          if (trimmedSite != null && trimmedSite.isNotEmpty)
            'site': trimmedSite,
          if (trimmedSlug != null && trimmedSlug.isNotEmpty)
            'slug': trimmedSlug,
          if (refresh) 'refresh': true,
        },
        options: Options(headers: _headers),
      );

      final body = response.data;
      if (body is! Map) return null;
      final data = body['data'];
      if (data is! Map) return null;
      return GamebaseEventView.fromData(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      // 404 = event not present in the gamebase. Treat as "no view".
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<GamebaseGlobalSearchResponse> globalSearch({
    required String query,
    List<String>? resources,
    int pageNumber = 1,
    int pageSize = 20,
    String? result,
    String? color,
    String? timeControl,
    int? yearFrom,
    int? yearTo,
    int? ratingFrom,
    int? ratingTo,
    bool? isOnline,
  }) async {
    try {
      final queryParams = {
        'q': query,
        'pageNumber': pageNumber,
        'pageSize': pageSize,
        if (resources != null) 'resources': resources,
        if (result != null) 'result': result,
        if (color != null) 'color': color,
        if (timeControl != null) 'timeControl': timeControl,
        if (yearFrom != null) 'yearFrom': yearFrom,
        if (yearTo != null) 'yearTo': yearTo,
        if (ratingFrom != null) 'ratingFrom': ratingFrom,
        if (ratingTo != null) 'ratingTo': ratingTo,
        if (isOnline != null) 'isOnline': isOnline,
      };

      if (kDebugMode) {
        debugPrint(
          '[GamebaseRepository] globalSearch: q="$query" page=$pageNumber',
        );
      }

      final response = await _dio.get(
        '$_baseUrl/api/search',
        queryParameters: queryParams,
        options: Options(headers: _headers),
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
      throw Exception(
        'Failed to perform global search: ${e.response?.statusCode ?? 'network error'} - ${e.message}',
      );
    } catch (e) {
      throw Exception('Failed to perform global search: $e');
    }
  }

  Future<GamebaseEventSearchResponse> searchEvents({
    required String query,
    int pageNumber = 1,
    int pageSize = 20,
    String? result,
    String? color,
    String? timeControl,
    int? yearFrom,
    int? yearTo,
    int? ratingFrom,
    int? ratingTo,
    bool? isOnline,
  }) async {
    try {
      final queryParams = {
        'q': query,
        'pageNumber': pageNumber,
        'pageSize': pageSize,
        if (result != null) 'result': result,
        if (color != null) 'color': color,
        if (timeControl != null) 'timeControl': timeControl,
        if (yearFrom != null) 'yearFrom': yearFrom,
        if (yearTo != null) 'yearTo': yearTo,
        if (ratingFrom != null) 'ratingFrom': ratingFrom,
        if (ratingTo != null) 'ratingTo': ratingTo,
        if (isOnline != null) 'isOnline': isOnline,
      };

      final response = await _dio.get(
        '$_baseUrl/api/search/events',
        queryParameters: queryParams,
        options: Options(headers: _headers),
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }
      return GamebaseEventSearchResponse.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] searchEvents DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
        debugPrint('  Response: ${e.response?.data}');
      }
      throw Exception(
        'Failed to search events: ${e.response?.statusCode ?? 'network error'} - ${e.message}',
      );
    } catch (e) {
      throw Exception('Failed to search events: $e');
    }
  }

  /// Fetch events for a specific player using player-id scoped aggregation.
  /// Maps to GET /api/player/{playerId}/events.
  ///
  /// [pageNumber] is 0-indexed, matching the other player endpoints.
  Future<GamebaseEventSearchResponse> getPlayerEvents({
    required String playerId,
    String? q,
    String color = 'all',
    String? timeControl,
    String? outcome,
    String? eco,
    String? opening,
    String? variation,
    String? event,
    String? site,
    String? dateFrom,
    String? dateTo,
    String? opponentId,
    int? ratingFrom,
    int? ratingTo,
    bool? isOnline,
    int pageNumber = 0,
    int pageSize = 24,
  }) async {
    final queryParams = <String, dynamic>{
      'color': color,
      if (q != null && q.isNotEmpty) 'q': q,
      'pageNumber': pageNumber,
      'pageSize': pageSize,
      if (timeControl != null) 'timeControl': timeControl,
      if (outcome != null) 'outcome': outcome,
      if (eco != null) 'eco': eco,
      if (opening != null) 'opening': opening,
      if (variation != null) 'variation': variation,
      if (event != null) 'event': event,
      if (site != null) 'site': site,
      if (dateFrom != null) 'dateFrom': dateFrom,
      if (dateTo != null) 'dateTo': dateTo,
      if (opponentId != null) 'opponentId': opponentId,
      if (ratingFrom != null) 'ratingFrom': ratingFrom,
      if (ratingTo != null) 'ratingTo': ratingTo,
      if (isOnline != null) 'isOnline': isOnline,
    };

    if (kDebugMode) {
      debugPrint(
        '[GamebaseRepository] getPlayerEvents: playerId=$playerId filters=$queryParams',
      );
    }

    try {
      final response = await _dio.get(
        '$_baseUrl/api/player/$playerId/events',
        queryParameters: queryParams,
        options: Options(headers: _headers),
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }
      return GamebaseEventSearchResponse.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[GamebaseRepository] getPlayerEvents DioException:');
        debugPrint('  Status: ${e.response?.statusCode}');
        debugPrint('  Message: ${e.message}');
        debugPrint('  Response: ${e.response?.data}');
      }
      throw Exception(
        'Failed to load player events: ${e.response?.statusCode ?? 'network error'} - ${e.message}',
      );
    } catch (e) {
      throw Exception('Failed to load player events: $e');
    }
  }

  /// Fetch games for a specific player with server-side filtering.
  /// Maps to GET /api/player/{playerId}/games.
  ///
  /// [pageNumber] is 0-indexed (unlike globalSearch which is 1-indexed).
  /// [outcome] uses 'win'/'loss'/'draw' (player perspective, not W/B/D).
  Future<Map<String, dynamic>> getPlayerGames({
    required String playerId,
    String? q,
    String color = 'all',
    String? timeControl,
    String? outcome,
    String? eco,
    String? opening,
    String? variation,
    String? event,
    String? site,
    String? dateFrom,
    String? dateTo,
    String? opponentId,
    int? ratingFrom,
    int? ratingTo,
    bool? isOnline,
    int pageNumber = 0,
    int pageSize = 100,
    bool includeData = false,
  }) async {
    final queryParams = <String, dynamic>{
      'color': color,
      if (q != null && q.isNotEmpty) 'q': q,
      'pageNumber': pageNumber,
      'pageSize': pageSize,
      if (includeData) 'includeData': true,
      if (timeControl != null) 'timeControl': timeControl,
      if (outcome != null) 'outcome': outcome,
      if (eco != null) 'eco': eco,
      if (opening != null) 'opening': opening,
      if (variation != null) 'variation': variation,
      if (event != null) 'event': event,
      if (site != null) 'site': site,
      if (dateFrom != null) 'dateFrom': dateFrom,
      if (dateTo != null) 'dateTo': dateTo,
      if (opponentId != null) 'opponentId': opponentId,
      if (ratingFrom != null) 'ratingFrom': ratingFrom,
      if (ratingTo != null) 'ratingTo': ratingTo,
      if (isOnline != null) 'isOnline': isOnline,
    };

    if (kDebugMode) {
      debugPrint(
        '[GamebaseRepository] getPlayerGames: playerId=$playerId filters=$queryParams',
      );
    }

    final response = await _dio.get(
      '$_baseUrl/api/player/$playerId/games',
      queryParameters: queryParams,
      options: Options(headers: _headers),
    );

    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> getMemorialPlayerGames({
    required String sourceIdentity,
    String? q,
    String color = 'all',
    String? timeControl,
    String? outcome,
    String? eco,
    String? opening,
    String? variation,
    String? event,
    String? site,
    String? dateFrom,
    String? dateTo,
    String? opponentId,
    int? ratingFrom,
    int? ratingTo,
    bool? isOnline,
    int pageNumber = 0,
    int pageSize = 100,
    bool includeData = false,
  }) async {
    final queryParams = <String, dynamic>{
      'color': color,
      if (q != null && q.isNotEmpty) 'q': q,
      'pageNumber': pageNumber,
      'pageSize': pageSize,
      if (includeData) 'includeData': true,
      if (timeControl != null) 'timeControl': timeControl,
      if (outcome != null) 'outcome': outcome,
      if (eco != null) 'eco': eco,
      if (opening != null) 'opening': opening,
      if (variation != null) 'variation': variation,
      if (event != null) 'event': event,
      if (site != null) 'site': site,
      if (dateFrom != null) 'dateFrom': dateFrom,
      if (dateTo != null) 'dateTo': dateTo,
      if (opponentId != null) 'opponentId': opponentId,
      if (ratingFrom != null) 'ratingFrom': ratingFrom,
      if (ratingTo != null) 'ratingTo': ratingTo,
      if (isOnline != null) 'isOnline': isOnline,
    };
    final response = await _dio.get(
      '$_baseUrl/api/player/memorial/${Uri.encodeComponent(sourceIdentity)}'
      '/games',
      queryParameters: queryParams,
      options: Options(headers: _headers),
    );
    return Map<String, dynamic>.from(response.data);
  }

  /// Fetch exact aggregated stats for a specific player with server-side filters.
  /// Maps to GET /api/player/{playerId}/stats.
  Future<Map<String, dynamic>> getPlayerStats({
    required String playerId,
    String? q,
    String color = 'all',
    String? timeControl,
    String? outcome,
    String? eco,
    String? opening,
    String? variation,
    String? event,
    String? site,
    String? dateFrom,
    String? dateTo,
    String? opponentId,
    int? ratingFrom,
    int? ratingTo,
    bool? isOnline,
  }) async {
    final queryParams = <String, dynamic>{
      'color': color,
      if (q != null && q.isNotEmpty) 'q': q,
      if (timeControl != null) 'timeControl': timeControl,
      if (outcome != null) 'outcome': outcome,
      if (eco != null) 'eco': eco,
      if (opening != null) 'opening': opening,
      if (variation != null) 'variation': variation,
      if (event != null) 'event': event,
      if (site != null) 'site': site,
      if (dateFrom != null) 'dateFrom': dateFrom,
      if (dateTo != null) 'dateTo': dateTo,
      if (opponentId != null) 'opponentId': opponentId,
      if (ratingFrom != null) 'ratingFrom': ratingFrom,
      if (ratingTo != null) 'ratingTo': ratingTo,
      if (isOnline != null) 'isOnline': isOnline,
    };

    final response = await _dio.get(
      '$_baseUrl/api/player/$playerId/stats',
      queryParameters: queryParams,
      options: Options(headers: _headers),
    );

    return Map<String, dynamic>.from(response.data);
  }

  /// Fetch exact reviewed-source statistics for a Memorial player. This path
  /// never falls back to a name or mutates the ordinary player stats cache.
  Future<Map<String, dynamic>> getMemorialPlayerStats({
    required String sourceIdentity,
    String? q,
    String color = 'all',
    String? timeControl,
    String? outcome,
    String? eco,
    String? opening,
    String? variation,
    String? event,
    String? site,
    String? dateFrom,
    String? dateTo,
    String? opponentId,
    int? ratingFrom,
    int? ratingTo,
    bool? isOnline,
  }) async {
    final queryParams = <String, dynamic>{
      'color': color,
      if (q != null && q.isNotEmpty) 'q': q,
      if (timeControl != null) 'timeControl': timeControl,
      if (outcome != null) 'outcome': outcome,
      if (eco != null) 'eco': eco,
      if (opening != null) 'opening': opening,
      if (variation != null) 'variation': variation,
      if (event != null) 'event': event,
      if (site != null) 'site': site,
      if (dateFrom != null) 'dateFrom': dateFrom,
      if (dateTo != null) 'dateTo': dateTo,
      if (opponentId != null) 'opponentId': opponentId,
      if (ratingFrom != null) 'ratingFrom': ratingFrom,
      if (ratingTo != null) 'ratingTo': ratingTo,
      if (isOnline != null) 'isOnline': isOnline,
    };
    final response = await _dio.get(
      '$_baseUrl/api/player/memorial/${Uri.encodeComponent(sourceIdentity)}'
      '/stats',
      queryParameters: queryParams,
      options: Options(headers: _headers),
    );
    return Map<String, dynamic>.from(response.data);
  }

  /// Start or reuse a backend-built player opening tree.
  Future<Map<String, dynamic>> startPlayerOpeningTreeBuild({
    required String playerId,
    int maxPly = 24,
    bool forceRebuild = false,
  }) async {
    final response = await _dio.post(
      '$_baseUrl/api/player/$playerId/opening-tree/build',
      data: <String, dynamic>{'maxPly': maxPly, 'forceRebuild': forceRebuild},
      options: Options(headers: _headers),
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> startMemorialOpeningTreeBuild({
    required String sourceIdentity,
    int maxPly = 24,
    bool forceRebuild = false,
  }) async {
    final response = await _dio.post(
      '$_baseUrl/api/player/memorial/${Uri.encodeComponent(sourceIdentity)}'
      '/opening-tree/build',
      data: <String, dynamic>{'maxPly': maxPly, 'forceRebuild': forceRebuild},
      options: Options(headers: _headers),
    );
    return Map<String, dynamic>.from(response.data);
  }

  /// Poll the backend player opening tree build status.
  Future<Map<String, dynamic>> getPlayerOpeningTreeStatus({
    required String playerId,
    required String treeId,
  }) async {
    final response = await _dio.get(
      '$_baseUrl/api/player/$playerId/opening-tree/status',
      queryParameters: <String, dynamic>{'treeId': treeId},
      options: Options(headers: _headers),
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> getMemorialOpeningTreeStatus({
    required String sourceIdentity,
    required String treeId,
  }) async {
    final response = await _dio.get(
      '$_baseUrl/api/player/memorial/${Uri.encodeComponent(sourceIdentity)}'
      '/opening-tree/status',
      queryParameters: <String, dynamic>{'treeId': treeId},
      options: Options(headers: _headers),
    );
    return Map<String, dynamic>.from(response.data);
  }

  /// Download a ready backend player opening tree.
  ///
  /// Returns `null` when the backend responds with HTTP 202, meaning the tree is
  /// still being prepared.
  Future<Map<String, dynamic>?> getPlayerOpeningTree({
    required String playerId,
    required String treeId,
  }) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/player/$playerId/opening-tree',
        queryParameters: <String, dynamic>{'treeId': treeId},
        options: Options(headers: _headers),
      );
      if (response.statusCode == 202) return null;
      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 202) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getMemorialOpeningTree({
    required String sourceIdentity,
    required String treeId,
  }) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/api/player/memorial/${Uri.encodeComponent(sourceIdentity)}'
        '/opening-tree',
        queryParameters: <String, dynamic>{'treeId': treeId},
        options: Options(headers: _headers),
      );
      if (response.statusCode == 202) return null;
      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 202) return null;
      rethrow;
    }
  }

  /// The request [getPositionGames] puts on the wire for these arguments:
  /// a POST of the body to `/games/query` when the move line survives
  /// sanitization, otherwise a GET of the same map to `/games`.
  ///
  /// Anything that caches position-games pages keys them by this, so a page
  /// is only ever reused for a request that is byte-for-byte the same.
  GamebaseWireRequest positionGamesRequest({
    required String fen,
    List<String> moves = const [],
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int notationPlies = 0,
    int pageNumber = 0,
    int pageSize = 20,
  }) {
    final body = buildPositionGamesQueryBody(
      fen: fen,
      moves: moves,
      uci: uci,
      timeControl: timeControl,
      playerId: playerId,
      color: color,
      result: result,
      minRating: minRating,
      maxRating: maxRating,
      yearFrom: yearFrom,
      yearTo: yearTo,
      sortBy: sortBy,
      sortDirection: sortDirection,
      isOnline: isOnline,
      notationPlies: notationPlies,
      pageNumber: pageNumber,
      pageSize: pageSize,
    );
    final normalizedMoves = (body['moves'] as List?) ?? const [];
    return normalizedMoves.isNotEmpty
        ? GamebaseWireRequest(
            method: 'POST',
            url: '$_baseUrl/api/game-position/games/query',
            payload: body,
          )
        : GamebaseWireRequest(
            method: 'GET',
            url: '$_baseUrl/api/game-position/games',
            payload: body,
          );
  }

  /// The request [getFenPositionGames] puts on the wire for these arguments.
  GamebaseWireRequest fenPositionGamesRequest({
    required String fen,
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int notationPlies = 0,
    int pageNumber = 0,
    int pageSize = 20,
  }) {
    return GamebaseWireRequest(
      method: 'GET',
      url: '$_baseUrl/api/game-position/fen/games',
      payload: buildFenPositionGamesQueryParameters(
        fen: fen,
        uci: uci,
        timeControl: timeControl,
        playerId: playerId,
        color: color,
        result: result,
        minRating: minRating,
        maxRating: maxRating,
        yearFrom: yearFrom,
        yearTo: yearTo,
        sortBy: sortBy,
        sortDirection: sortDirection,
        isOnline: isOnline,
        notationPlies: notationPlies,
        pageNumber: pageNumber,
        pageSize: pageSize,
      ),
    );
  }

  /// List example games for a given position (and optionally a specific move from that position).
  ///
  /// Pagination is 0-indexed per the API spec for this endpoint.
  ///
  /// [notationPlies] (1–20) asks the backend to include a `continuation`
  /// UCI-move slice per row, starting from the queried position. `0` (default)
  /// omits it.
  Future<GamebaseSearchQueryResponse> getPositionGames({
    required String fen,
    List<String> moves = const [],
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int notationPlies = 0,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    try {
      final request = positionGamesRequest(
        fen: fen,
        moves: moves,
        uci: uci,
        timeControl: timeControl,
        playerId: playerId,
        color: color,
        result: result,
        minRating: minRating,
        maxRating: maxRating,
        yearFrom: yearFrom,
        yearTo: yearTo,
        sortBy: sortBy,
        sortDirection: sortDirection,
        isOnline: isOnline,
        notationPlies: notationPlies,
        pageNumber: pageNumber,
        pageSize: pageSize,
      );
      final normalizedMoves = (request.payload['moves'] as List?) ?? const [];

      if (kDebugMode &&
          moves.isNotEmpty &&
          normalizedMoves.length != moves.length) {
        debugPrint(
          '[GamebaseRepository] Dropping mismatched move path for games query',
        );
      }

      final response = request.method == 'POST'
          ? await _dio.post(
              request.url,
              data: request.payload,
              options: Options(headers: _headers),
            )
          : await _dio.get(
              request.url,
              queryParameters: request.payload,
              options: Options(headers: _headers),
            );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }
      return GamebaseSearchQueryResponse.fromJson(
        Map<String, dynamic>.from(data),
      );
    } catch (e) {
      throw Exception('Failed to load position games: $e');
    }
  }

  /// List games containing the exact FEN position, independent of move order.
  ///
  /// Uses the FEN-specific endpoint so pasted/custom positions can be searched
  /// directly without requiring a move aggregate or next-move selection. Filter
  /// and sort surface mirrors `getPositionGames` — see the OpenAPI spec for
  /// `/api/game-position/fen/games` (and the POST `/query` variant for
  /// multi-key sort via `orderBy`).
  Future<GamebaseSearchQueryResponse> getFenPositionGames({
    required String fen,
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int notationPlies = 0,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    try {
      final request = fenPositionGamesRequest(
        fen: fen,
        uci: uci,
        timeControl: timeControl,
        playerId: playerId,
        color: color,
        result: result,
        minRating: minRating,
        maxRating: maxRating,
        yearFrom: yearFrom,
        yearTo: yearTo,
        sortBy: sortBy,
        sortDirection: sortDirection,
        isOnline: isOnline,
        notationPlies: notationPlies,
        pageNumber: pageNumber,
        pageSize: pageSize,
      );
      final response = await _dio.get(
        request.url,
        queryParameters: request.payload,
        options: Options(headers: _headers),
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected response format');
      }
      return GamebaseSearchQueryResponse.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return GamebaseSearchQueryResponse(
          status: 'success',
          data: const [],
          metadata: GamebasePaginationMetadata(
            pageNumber: pageNumber,
            pageSize: pageSize,
            hasMoreValue: false,
          ),
        );
      }
      throw Exception('Failed to load FEN position games: $e');
    } catch (e) {
      throw Exception('Failed to load FEN position games: $e');
    }
  }
}

final gamebaseRepositoryProvider = Provider<GamebaseRepository>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  // Dio's own adapter drops an idle connection after 3 s, so a reader who
  // pauses between taps pays a fresh TCP + TLS handshake (100-300 ms on a
  // phone) on the next explorer request. A minute of idle keep-alive covers
  // ordinary reading pauses; the socket still closes the moment the server
  // closes its end.
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () =>
        HttpClient()..idleTimeout = const Duration(seconds: 60),
  );
  dio.interceptors.add(LogarteDioInterceptor(logarte));
  return GamebaseRepository(dio);
});
