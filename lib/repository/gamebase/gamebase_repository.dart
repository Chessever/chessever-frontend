import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:dio/dio.dart';
import 'package:chessever2/e2e/e2e_config.dart';
import 'package:chessever2/main.dart';
import 'package:logarte/logarte.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:dartchess/dartchess.dart';
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
    const releaseKey = String.fromEnvironment(
      'GAMEBASE_API_KEY',
      defaultValue: '',
    );

    if (E2eConfig.isEnabled && releaseKey.isNotEmpty) {
      return releaseKey;
    }

    if (kDebugMode) {
      final envKey = dotenv.env['GAMEBASE_API_KEY']?.trim();
      if (envKey != null && envKey.isNotEmpty) return envKey;
    } else {
      if (releaseKey.isNotEmpty) return releaseKey;
    }
    return _fallbackApiKey;
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
      final normalizedFen = _normalizeFenForLookup(fen);
      final normalizedMoves = _sanitizeMovesForFen(normalizedFen, moves);

      if (kDebugMode &&
          moves.isNotEmpty &&
          normalizedMoves.length != moves.length) {
        debugPrint(
          '[GamebaseRepository] Dropping mismatched move path for aggregates query',
        );
      }

      final body = <String, dynamic>{
        'fen': normalizedFen,
        'moves': normalizedMoves,
        if (playerId != null && playerId.isNotEmpty) 'playerId': playerId,
        if (timeControl != null) 'timeControl': timeControl.name.toUpperCase(),
        if (minRating != null) 'minRating': minRating,
        if (maxRating != null) 'maxRating': maxRating,
        if (color != null) 'color': color,
        if (result != null) 'result': result,
        if (yearFrom != null) 'yearFrom': yearFrom,
        if (yearTo != null) 'yearTo': yearTo,
        if (isOnline != null) 'isOnline': isOnline,
      };

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
      final response = await _dio.post(
        '$_baseUrl/api/game-position/aggregates/query',
        data: body,
        options: Options(
          headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
        ),
      );

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

  /// Canonicalize FEN for Gamebase lookups.
  ///
  /// The API expects a standard 6-field FEN. Some callers may provide only the
  /// first 4 fields (piece placement, side to move, castling rights, en
  /// passant). In that case, append halfmove/fullmove counters.
  ///
  /// When counters are present, preserve them. Some backends index/look up
  /// positions using the full FEN string; clamping counters can cause misses
  /// for progressed positions.
  static String _normalizeFenForLookup(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return fen.trim();

    if (parts.length == 4) return '${parts.join(' ')} 0 1';
    return parts.take(6).join(' ');
  }

  static String _positionKey(String fen) =>
      fen.trim().split(RegExp(r'\s+')).take(4).join(' ');

  static NormalMove? _normalMoveFromUci(String uci) {
    if (uci.length < 4) return null;

    final from = Square.fromName(uci.substring(0, 2));
    final to = Square.fromName(uci.substring(2, 4));

    Role? promotion;
    if (uci.length > 4) {
      promotion = Role.fromChar(uci[4]);
      if (promotion == null) return null;
    }

    return NormalMove(from: from, to: to, promotion: promotion);
  }

  static List<String> _sanitizeMovesForFen(String fen, List<String> moves) {
    if (moves.isEmpty) return const [];

    final normalizedMoves = moves
        .map((m) => m.trim().toLowerCase())
        .where((m) => RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(m))
        .toList(growable: false);

    if (normalizedMoves.isEmpty) return const [];

    try {
      Position position = Chess.initial;
      final replayed = <String>[];
      for (final uci in normalizedMoves) {
        final move = _normalMoveFromUci(uci);
        if (move == null || !position.isLegal(move)) {
          return const [];
        }
        // dartchess encodes castling king-to-rook (e1h1), but the backend
        // (chess.js) only accepts the standard king-to-g/c UCI. Emit the
        // standard form so deep-path queries (ply > indexed boundary) can
        // replay the move line server-side.
        replayed.add(_toStandardCastlingUci(position, move));
        position = position.play(move);
      }

      // Only require the replayed position to match the target FEN (first 4
      // fields — piece placement / turn / castling / en passant). Do NOT
      // compare move count against _pliesFromFen: variation paths that
      // replace a mainline move result in a move list shorter than the FEN's
      // fullmove-derived ply count, and the old strict equality silently
      // dropped the whole line at depth ≥ 21, collapsing the backend to the
      // position-only path which returns empty past the indexed boundary.
      return _positionKey(position.fen) == _positionKey(fen)
          ? List<String>.unmodifiable(replayed)
          : const [];
    } catch (_) {
      return const [];
    }
  }

  /// Returns the standard king-to-target UCI for a castling move, or the
  /// original [move]'s UCI for any non-castling move.
  ///
  /// dartchess normalizes castling to the Chess960 king-to-rook form (e.g.
  /// `e1h1`), but the Gamebase backend uses chess.js which only recognizes the
  /// classical king-to-g/c form (`e1g1`, `e1c1`, `e8g8`, `e8c8`). Without this
  /// rewrite, any move line containing a castle fails server-side replay and
  /// deep-path queries return empty aggregates.
  static String _toStandardCastlingUci(Position position, NormalMove move) {
    final piece = position.board.pieceAt(move.from);
    if (piece == null || piece.role != Role.king) return move.uci;

    final fromFile = move.from.file;
    final toFile = move.to.file;
    final fileDelta = (fromFile - toFile).abs();

    final targetPiece = position.board.pieceAt(move.to);
    final capturesOwnRook =
        targetPiece != null &&
        targetPiece.role == Role.rook &&
        targetPiece.color == piece.color;

    // File delta of 2+ (standard e1→g1/c1) or capturing own rook (Chess960
    // form e1→h1/a1) both indicate castling. For everything else (e1→f1,
    // e1→e2, etc.) fall through to the original UCI.
    if (fileDelta < 2 && !capturesOwnRook) return move.uci;

    final isKingSide = toFile > fromFile;
    final targetFile = isKingSide ? File.g : File.c;
    final targetSquare = Square.fromCoords(targetFile, move.from.rank);
    return move.from.name + targetSquare.name;
  }

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
    if (kDebugMode) {
      debugPrint('[GamebaseRepository] getGameWithPgn called with id: $id');
    }
    try {
      final response = await _dio.get(
        '$_baseUrl/api/game/$id',
        queryParameters: {'includePgn': true},
        options: Options(
          headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
        ),
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

  Future<CloudEval?> getEvalByFen(String fen) async {
    try {
      final normalizedFen = _normalizeEvalFenForLookup(fen);
      final response = await _dio.get(
        '$_baseUrl/api/eval',
        queryParameters: {'fen': normalizedFen},
        options: Options(
          headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
        ),
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
        options: Options(
          headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
        ),
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
        options: Options(
          headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
        ),
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
        '[GamebaseRepository] getPlayerGames: playerId=$playerId filters=$queryParams',
      );
    }

    final response = await _dio.get(
      '$_baseUrl/api/player/$playerId/games',
      queryParameters: queryParams,
      options: Options(
        headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
      ),
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
      options: Options(
        headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
      ),
    );

    return Map<String, dynamic>.from(response.data);
  }

  /// List example games for a given position (and optionally a specific move from that position).
  ///
  /// Pagination is 0-indexed per the API spec for this endpoint.
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
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    try {
      final normalizedFen = _normalizeFenForLookup(fen);
      final normalizedMoves = _sanitizeMovesForFen(normalizedFen, moves);

      if (kDebugMode &&
          moves.isNotEmpty &&
          normalizedMoves.length != moves.length) {
        debugPrint(
          '[GamebaseRepository] Dropping mismatched move path for games query',
        );
      }

      final orderBy =
          sortBy != null
              ? [
                {
                  'field': sortBy.name,
                  'direction':
                      sortDirection == GamebaseSortDirection.asc
                          ? 'asc'
                          : 'desc',
                },
              ]
              : null;

      final response =
          normalizedMoves.isNotEmpty
              ? await _dio.post(
                '$_baseUrl/api/game-position/games/query',
                data: {
                  'fen': normalizedFen,
                  'moves': normalizedMoves,
                  'pageNumber': pageNumber,
                  'pageSize': pageSize,
                  if (uci != null && uci.trim().isNotEmpty) 'uci': uci.trim(),
                  if (playerId != null && playerId.trim().isNotEmpty)
                    'playerId': playerId.trim(),
                  if (timeControl != null)
                    'timeControl': timeControl.name.toUpperCase(),
                  if (minRating != null) 'minRating': minRating,
                  if (maxRating != null) 'maxRating': maxRating,
                  if (color != null) 'color': color,
                  if (result != null) 'result': result,
                  if (yearFrom != null) 'yearFrom': yearFrom,
                  if (yearTo != null) 'yearTo': yearTo,
                  if (isOnline != null) 'isOnline': isOnline,
                  if (orderBy != null) 'orderBy': orderBy,
                  if (sortBy != null) 'sortBy': sortBy.name,
                  if (sortDirection != null)
                    'sortDirection': sortDirection.name,
                },
                options: Options(
                  headers: {'X-API-Key': _apiKey, 'Accept': 'application/json'},
                ),
              )
              : await _dio.get(
                '$_baseUrl/api/game-position/games',
                queryParameters: {
                  'fen': normalizedFen,
                  'pageNumber': pageNumber,
                  'pageSize': pageSize,
                  if (uci != null && uci.trim().isNotEmpty) 'uci': uci.trim(),
                  if (playerId != null && playerId.trim().isNotEmpty)
                    'playerId': playerId.trim(),
                  if (timeControl != null)
                    'timeControl': timeControl.name.toUpperCase(),
                  if (minRating != null) 'minRating': minRating,
                  if (maxRating != null) 'maxRating': maxRating,
                  if (color != null) 'color': color,
                  if (result != null) 'result': result,
                  if (yearFrom != null) 'yearFrom': yearFrom,
                  if (yearTo != null) 'yearTo': yearTo,
                  if (isOnline != null) 'isOnline': isOnline,
                  if (sortBy != null) 'sortBy': sortBy.name,
                  if (sortDirection != null)
                    'sortDirection': sortDirection.name,
                },
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
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    try {
      final normalizedFen = _normalizeFenForLookup(fen);
      final response = await _dio.get(
        '$_baseUrl/api/game-position/fen/games',
        queryParameters: {
          'fen': normalizedFen,
          'pageNumber': pageNumber,
          'pageSize': pageSize,
          if (uci != null && uci.trim().isNotEmpty) 'uci': uci.trim(),
          if (playerId != null && playerId.trim().isNotEmpty)
            'playerId': playerId.trim(),
          if (timeControl != null)
            'timeControl': timeControl.name.toUpperCase(),
          if (minRating != null) 'minRating': minRating,
          if (maxRating != null) 'maxRating': maxRating,
          if (color != null) 'color': color,
          if (result != null) 'result': result,
          if (yearFrom != null) 'yearFrom': yearFrom,
          if (yearTo != null) 'yearTo': yearTo,
          if (isOnline != null) 'isOnline': isOnline,
          if (sortBy != null) 'sortBy': sortBy.name,
          if (sortDirection != null) 'sortDirection': sortDirection.name,
        },
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
  dio.interceptors.add(LogarteDioInterceptor(logarte));
  return GamebaseRepository(dio);
});
