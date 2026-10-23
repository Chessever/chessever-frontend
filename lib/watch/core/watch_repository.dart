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
  bool get configured => apiKey.isNotEmpty;

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
        'select': 'id,name,time_control',
        'order': 'max_avg_elo.desc.nullslast,id.asc',
        'offset': '$offset',
        'limit': '$pageSize',
      })).map(WatchEvent.fromJson).toList();

  Future<List<WatchTour>> tours(String eventId) async {
    // Sections are usually few, but do not silently drop large team events.
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += pageSize) {
      final page = await _get('tours', {
        'select': 'id,name,group_broadcast_id,players',
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

  Future<List<Games>> games(String roundId, {int offset = 0}) async =>
      (await _get('games', {
        'select': gameColumns,
        'round_id': 'eq.$roundId',
        'order': 'board_nr.asc.nullslast,id.asc',
        'offset': '$offset',
        'limit': '$pageSize',
      })).map(Games.fromJson).toList();

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
      'select': 'id,name,time_control',
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
