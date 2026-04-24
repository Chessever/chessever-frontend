import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tourRepositoryProvider = AutoDisposeProvider<TourRepository>((ref) {
  return TourRepository();
});

class TourRepository extends BaseRepository {
  /// Fetch tours by group_broadcast_id or tour id.
  /// First tries matching by group_broadcast_id.
  /// If no results, falls back to matching by tour id directly.
  /// This handles cases where the passed ID is a raw tour_id (For You tab fallback).
  Future<List<Tour>> getTourByGroupId(String groupId) async {
    return handleApiCall(() async {
      // First try matching by group_broadcast_id
      final byGroupResponse = await supabase
          .from('tours')
          .select()
          .eq('group_broadcast_id', groupId)
          .order('avg_elo', ascending: false);

      final byGroupTours =
          (byGroupResponse as List).map((json) => Tour.fromJson(json)).toList();

      if (byGroupTours.isNotEmpty) {
        return byGroupTours;
      }

      // Fallback: the passed ID might be a raw tour_id
      // (happens when For You tab uses tour_id as event ID)
      final byIdResponse = await supabase
          .from('tours')
          .select()
          .eq('id', groupId);

      return (byIdResponse as List).map((json) => Tour.fromJson(json)).toList();
    });
  }

  // Fetch multiple tours by their IDs
  Future<List<Tour>> getToursByIds(List<String> tourIds) async {
    return handleApiCall(() async {
      if (tourIds.isEmpty) {
        return [];
      }

      final response = await supabase
          .from('tours')
          .select()
          .inFilter('id', tourIds);

      return (response as List).map((json) => Tour.fromJson(json)).toList();
    });
  }

  /// Fetch tours for multiple group_broadcast IDs in a single query.
  /// Returns a map of group_broadcast_id → List<Tour>.
  Future<Map<String, List<Tour>>> getToursByGroupBroadcastIds(
    List<String> groupBroadcastIds,
  ) async {
    if (groupBroadcastIds.isEmpty) return {};

    return handleApiCall(() async {
      final response = await supabase
          .from('tours')
          .select()
          .inFilter('group_broadcast_id', groupBroadcastIds)
          .order('avg_elo', ascending: false);

      final result = <String, List<Tour>>{};
      for (final json in response as List) {
        final tour = Tour.fromJson(json);
        final gbId = json['group_broadcast_id'] as String?;
        if (gbId != null && gbId.isNotEmpty) {
          result.putIfAbsent(gbId, () => []).add(tour);
        }
      }
      return result;
    });
  }

  /// Fetch tours by country location.
  /// Searches the info->location field which contains "City, Country" format.
  Future<List<Tour>> getToursByCountryLocation({
    required String countryName,
    String? searchQuery,
    int limit = 30,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      debugPrint(
        '[TourRepository] getToursByCountryLocation: countryName=$countryName, searchQuery=$searchQuery',
      );

      var query = supabase
          .from('tours')
          .select()
          .ilike('info->>location', '%$countryName%');

      // Add search filter if provided
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        query = query.ilike('name', '%${searchQuery.trim()}%');
      }

      final response = await query
          .order('dates->0', ascending: false) // Most recent first
          .range(offset, offset + limit - 1);

      final tours =
          (response as List).map((json) => Tour.fromJson(json)).toList();

      debugPrint(
        '[TourRepository] getToursByCountryLocation: found ${tours.length} tours',
      );
      return tours;
    });
  }

  /// Search tours by name with optional country filter.
  Future<List<Tour>> searchTours({
    required String query,
    String? countryName,
    int limit = 30,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      debugPrint(
        '[TourRepository] searchTours: query=$query, countryName=$countryName',
      );

      var dbQuery = supabase.from('tours').select();

      if (query.trim().isNotEmpty) {
        dbQuery = dbQuery.ilike('name', '%${query.trim()}%');
      }

      if (countryName != null && countryName.isNotEmpty) {
        dbQuery = dbQuery.ilike('info->>location', '%$countryName%');
      }

      final response = await dbQuery
          .order('dates->0', ascending: false)
          .range(offset, offset + limit - 1);

      final tours =
          (response as List).map((json) => Tour.fromJson(json)).toList();

      debugPrint('[TourRepository] searchTours: found ${tours.length} tours');
      return tours;
    });
  }

  /// Get recent tours (for featured/home screen).
  Future<List<Tour>> getRecentTours({int limit = 30, int offset = 0}) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('tours')
          .select()
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List).map((json) => Tour.fromJson(json)).toList();
    });
  }

  /// Search players within a specific tour using Supabase.
  /// This ensures search works correctly regardless of client-side pagination.
  Future<List<TournamentPlayer>> searchPlayersInTour(
    String tourId,
    String query,
  ) async {
    return handleApiCall(() async {
      if (query.trim().isEmpty) return [];

      // Note: Since players are stored in a JSONB array, performing a partial
      // text search directly in Supabase without an RPC requires fetching the
      // array and filtering. If an RPC 'search_tour_players' is added later,
      // it should be used here.
      final response =
          await supabase
              .from('tours')
              .select('players')
              .eq('id', tourId)
              .single();

      final playersRaw = response['players'];
      final playersList = playersRaw is List ? playersRaw : const <dynamic>[];
      final players = parsePlayersFromJson(playersList);

      final lowerQuery = query.toLowerCase().trim();
      return players.where((p) {
        return p.name.toLowerCase().contains(lowerQuery) ||
            (p.title?.toLowerCase().contains(lowerQuery) ?? false) ||
            (p.federation?.toLowerCase().contains(lowerQuery) ?? false);
      }).toList();
    });
  }

  /// Fetch the full tournament roster for a single tour from Supabase.
  /// Used to compute overall standings / ranks for search results when the
  /// local tour cache may be stale or partial.
  Future<List<TournamentPlayer>> getTourPlayers(String tourId) async {
    return handleApiCall(() async {
      final response =
          await supabase
              .from('tours')
              .select('players')
              .eq('id', tourId)
              .single();
      final playersRaw = response['players'];
      final playersList = playersRaw is List ? playersRaw : const <dynamic>[];
      return parsePlayersFromJson(playersList);
    });
  }
}
