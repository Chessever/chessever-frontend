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

      final byGroupTours = (byGroupResponse as List)
          .map((json) => Tour.fromJson(json))
          .toList();

      if (byGroupTours.isNotEmpty) {
        return byGroupTours;
      }

      // Fallback: the passed ID might be a raw tour_id
      // (happens when For You tab uses tour_id as event ID)
      final byIdResponse = await supabase
          .from('tours')
          .select()
          .eq('id', groupId);

      return (byIdResponse as List)
          .map((json) => Tour.fromJson(json))
          .toList();
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

  /// Fetch tours by country location.
  /// Searches the info->location field which contains "City, Country" format.
  Future<List<Tour>> getToursByCountryLocation({
    required String countryName,
    String? searchQuery,
    int limit = 30,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      debugPrint('[TourRepository] getToursByCountryLocation: countryName=$countryName, searchQuery=$searchQuery');

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

      final tours = (response as List).map((json) => Tour.fromJson(json)).toList();

      debugPrint('[TourRepository] getToursByCountryLocation: found ${tours.length} tours');
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
      debugPrint('[TourRepository] searchTours: query=$query, countryName=$countryName');

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

      final tours = (response as List).map((json) => Tour.fromJson(json)).toList();

      debugPrint('[TourRepository] searchTours: found ${tours.length} tours');
      return tours;
    });
  }

  /// Get recent tours (for featured/home screen).
  Future<List<Tour>> getRecentTours({
    int limit = 30,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('tours')
          .select()
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List).map((json) => Tour.fromJson(json)).toList();
    });
  }
}
