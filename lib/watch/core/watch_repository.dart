import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../repository/supabase/game/games.dart';
import 'watch_models.dart';

/// Public, read-only projections from the production feed. Account queries stay
/// on the authenticated phone. Requests time out and lists paginate explicitly.
class WatchRepository {
  WatchRepository({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();
  static const productionUrl = 'https://oelbsuggrzyqwzmvidju.supabase.co';
  static const pageSize = 30;
  static const gameColumns =
      'id,round_id,round_slug,tour_id,tour_slug,name,fen,'
      'players,last_move,status,board_nr,last_move_time,last_clock_white,'
      'last_clock_black';
  String apiKey;
  final http.Client _client;
  final _artwork = <String, Future<String?>>{};
  bool get configured => apiKey.isNotEmpty;

  /// Only visible rows request artwork. Reuse it through navigation and keep
  /// images optional so a missing tournament photo never blocks the feed.
  Future<String?> eventArtwork(String eventId) =>
      _artwork.putIfAbsent(eventId, () async {
        try {
          final rows = await _get('tours', {
            'select': 'image',
            'group_broadcast_id': 'eq.$eventId',
            'image': 'not.is.null',
            'order': 'avg_elo.desc.nullslast,id.asc',
            'limit': '1',
          });
          final image = rows.firstOrNull?['image'];
          return image is String && Uri.tryParse(image)?.scheme == 'https'
              ? image
              : null;
        } catch (_) {
          _artwork.remove(eventId);
          return null;
        }
      });

  Future<List<Map<String, dynamic>>> _get(
    String table,
    Map<String, String> query,
  ) async {
    if (!configured) {
      throw const WatchDataException('Open ChessEver on iPhone to connect.');
    }
    final response = await _client
        .get(
          Uri.parse(
            '$productionUrl/rest/v1/$table',
          ).replace(queryParameters: query),
          headers: {'apikey': apiKey, 'Authorization': 'Bearer $apiKey'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const WatchDataException(
        'The live feed is unavailable. Try again.',
      );
    }
    final rows = jsonDecode(response.body) as List;
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<List<WatchEvent>> events({int offset = 0}) async =>
      (await _get('group_broadcasts_current', {
        'select': 'id,name,time_control,date_closest_round',
        'order': 'max_avg_elo.desc.nullslast,id.asc',
        'offset': '$offset',
        'limit': '$pageSize',
      })).map(WatchEvent.fromJson).toList();

  /// PostgREST `in.(…)` filter. Every id is quoted, so an id with a comma or
  /// a space still reads as one value.
  static String inList(Iterable<String> ids) =>
      'in.(${ids.map((id) => '"${id.replaceAll('"', '\\"')}"').join(',')})';

  Future<List<WatchTour>> tours(String eventId) async {
    // Sections are usually few, but do not silently drop large team events.
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += pageSize) {
      final page = await _get('tours', {
        'select':
            'id,name,slug,avg_elo,dates,is_mirror,group_broadcast_id,players',
        'group_broadcast_id': 'eq.$eventId',
        'order': 'avg_elo.desc.nullslast,id.asc',
        'offset': '$offset',
        'limit': '$pageSize',
      });
      rows.addAll(page);
      if (page.length < pageSize) break;
    }
    return rows.map(WatchTour.fromJson).toList();
  }

  Future<List<WatchRound>> rounds(String tourId) async {
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += pageSize) {
      final page = await _get('rounds', {
        'select': 'id,name,starts_at',
        'tour_id': 'eq.$tourId',
        'order': 'created_at.asc,id.asc',
        'offset': '$offset',
        'limit': '$pageSize',
      });
      rows.addAll(page);
      if (page.length < pageSize) break;
    }
    return rows.map(WatchRound.fromJson).toList();
  }

  /// Every round of [tourIds] in one request, schedule order within a tour.
  Future<List<WatchRound>> eventRounds(Iterable<String> tourIds) async {
    final ids = tourIds.toList();
    if (ids.isEmpty) return const [];
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += layoutPageSize) {
      final page = await _get('rounds', {
        'select': 'id,name,starts_at,tour_id',
        'tour_id': inList(ids),
        'order': 'tour_id.asc,created_at.asc,id.asc',
        'offset': '$offset',
        'limit': '$layoutPageSize',
      });
      rows.addAll(page);
      if (page.length < layoutPageSize) break;
    }
    return rows.map(WatchRound.fromJson).toList();
  }

  /// The compact layout of every board of [tourIds]: who plays whom on which
  /// board of which round, and whether it is being played, without the
  /// position. It lays the whole event out in one round trip; positions and
  /// clocks follow per board through [gamesByIds] as boards come on screen.
  static const layoutPageSize = 1000;
  static const layoutColumns =
      'id,round_id,round_slug,tour_id,tour_slug,status,board_nr,'
      'last_move,last_move_time,players';
  Future<List<Games>> eventBoards(Iterable<String> tourIds) async {
    final ids = tourIds.toList();
    if (ids.isEmpty) return const [];
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += layoutPageSize) {
      final page = await _get('games', {
        'select': layoutColumns,
        'tour_id': inList(ids),
        'order': 'board_nr.asc.nullslast,id.asc',
        'offset': '$offset',
        'limit': '$layoutPageSize',
      });
      rows.addAll(page);
      if (page.length < layoutPageSize) break;
    }
    return rows.map(Games.fromJson).toList();
  }

  /// Full rows (position, clocks, last move) for up to [pageSize] boards.
  Future<List<Games>> gamesByIds(Iterable<String> gameIds) async {
    final ids = gameIds.toList();
    if (ids.isEmpty) return const [];
    return (await _get('games', {
      'select': gameColumns,
      'id': inList(ids),
      'limit': '${ids.length}',
    })).map(Games.fromJson).toList();
  }

  Future<List<Games>> games(String roundId, {int offset = 0}) async =>
      (await _get('games', {
        'select': gameColumns,
        'round_id': 'eq.$roundId',
        'order': 'board_nr.asc.nullslast,id.asc',
        'offset': '$offset',
        'limit': '$pageSize',
      })).map(Games.fromJson).toList();

  /// Load history only on demand; board lists and live polling stay compact.
  Future<String?> gamePgn(String id) async {
    final rows = await _get('games', {
      'select': 'pgn',
      'id': 'eq.$id',
      'limit': '1',
    });
    return rows.firstOrNull?['pgn'] as String?;
  }

  Future<Games?> game(String id) async {
    final rows = await _get('games', {
      'select': gameColumns,
      'id': 'eq.$id',
      'limit': '1',
    });
    return rows.isEmpty ? null : Games.fromJson(rows.first);
  }

  /// Fetch complete results, including every page, before calculating a
  /// player's round-by-round card. Never infer scores from a partial list.
  Future<List<Games>> scorecard(String tourId, WatchStanding player) async {
    final games = <Games>[];
    for (var offset = 0; ; offset += 1000) {
      final fideId = int.tryParse(player.fideId ?? '');
      final page = await _get('games', {
        'select': gameColumns,
        'tour_id': 'eq.$tourId',
        'order': 'round_id.asc,board_nr.asc.nullslast,id.asc',
        'players':
            'cs.${jsonEncode([
              fideId != null && fideId > 0 ? {'fideId': fideId} : {'name': player.name},
            ])}',
        'offset': '$offset',
        'limit': '1000',
      });
      games.addAll(
        page
            .map(Games.fromJson)
            .where(
              (game) =>
                  game.players?.any((p) => watchPlayerMatches(p, player)) ??
                  false,
            ),
      );
      if (page.length < 1000) break;
    }
    final schedule = await rounds(tourId);
    final order = {for (var i = 0; i < schedule.length; i++) schedule[i].id: i};
    games.sort(
      (a, b) => (order[a.roundId] ?? schedule.length).compareTo(
        order[b.roundId] ?? schedule.length,
      ),
    );
    return games;
  }

  Future<String?> eventFor({
    String? tourId,
    String? roundId,
    String? gameId,
  }) async {
    if (gameId != null) tourId = (await game(gameId))?.tourId;
    if (tourId == null && roundId != null) {
      final rows = await _get('rounds', {
        'select': 'tour_id',
        'id': 'eq.$roundId',
        'limit': '1',
      });
      tourId = rows.isEmpty ? null : rows.first['tour_id'] as String?;
    }
    if (tourId == null) return null;
    final rows = await _get('tours', {
      'select': 'group_broadcast_id',
      'id': 'eq.$tourId',
      'limit': '1',
    });
    return rows.isEmpty ? null : rows.first['group_broadcast_id'] as String?;
  }

  Future<WatchEvent?> currentEvent(String id) async {
    final rows = await _get('group_broadcasts_current', {
      'select': 'id,name,time_control,date_closest_round',
      'id': 'eq.$id',
      'limit': '1',
    });
    return rows.isEmpty ? null : WatchEvent.fromJson(rows.first);
  }

  void dispose() => _client.close();
}

class WatchDataException implements Exception {
  const WatchDataException(this.message);
  final String message;
  @override
  String toString() => message;
}
