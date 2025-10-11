import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final groupBroadcastRepositoryProvider =
    AutoDisposeProvider<GroupBroadcastRepository>((ref) {
      return GroupBroadcastRepository();
    });

class GroupBroadcastRepository extends BaseRepository {
  /// Fetch all group broadcasts with optional pagination and sorting
  Future<List<GroupBroadcast>> getCurrentGroupBroadcasts({
    int? limit,
    int? offset,
    String orderBy = 'max_avg_elo',
    bool ascending = false,
  }) async {
    return handleApiCall(() async {
      PostgrestTransformBuilder<PostgrestList> query =
          supabase.from('group_broadcasts_current').select();

      query = query.order(orderBy, ascending: ascending);

      if (limit != null) {
        query = query.limit(limit);
      }

      if (offset != null) {
        query = query.range(offset, offset + (limit ?? 100) - 1);
      }

      final response = await query;
      return (response as List)
          .map((json) => GroupBroadcast.fromJson(json))
          .toList();
    });
  }

  Future<List<GroupBroadcast>> getUpcomingGroupBroadcasts({
    int? limit,
    int? offset,
    String orderBy = 'max_avg_elo',
    bool ascending = false,
  }) async {
    return handleApiCall(() async {
      PostgrestTransformBuilder<PostgrestList> query =
          supabase.from('group_broadcasts_upcoming').select();

      query = query.order(orderBy, ascending: ascending);

      if (limit != null) {
        query = query.limit(limit);
      }

      if (offset != null) {
        query = query.range(offset, offset + (limit ?? 100) - 1);
      }

      final response = await query;
      return (response as List)
          .map((json) => GroupBroadcast.fromJson(json))
          .toList();
    });
  }

  // group_broadcast_repository.dart
  Future<List<GroupBroadcast>> getPastGroupBroadcasts({
    int? limit, // NEW
    int? offset, // NEW
    String orderBy = 'date_end',
    bool ascending = false,
  }) async {
    return handleApiCall(() async {
      PostgrestTransformBuilder<PostgrestList> query =
          supabase.from('group_broadcasts_past').select();

      query = query.order(orderBy, ascending: ascending);

      if (limit != null) query = query.limit(limit);
      if (offset != null) query = query.range(offset, offset + limit! - 1);

      final response = await query;

      return (response as List)
          .map((json) => GroupBroadcast.fromJson(json))
          .toList();
    });
  }

  Future<List<GroupBroadcast>> getCurrentMonthGroupBroadcasts({
    required int selectedYear,
    required int selectedMonth,
    int limit = 50,
    int? offset,
    String orderBy = 'date_end',
    bool ascending = false,
  }) async {
    return handleApiCall(() async {
      final supabaseClient = supabase; // assume this is your instance

      // Calculate first and last day of the selected month
      final startOfMonth = DateTime(selectedYear, selectedMonth, 1);
      final endOfMonth = DateTime(
        selectedYear,
        selectedMonth + 1,
        0,
        23,
        59,
        59,
      );

      // Build query
      PostgrestTransformBuilder<PostgrestList> query = supabaseClient
          .from('group_broadcasts')
          .select()
          .or(
            'and(date_start.gte.${startOfMonth.toIso8601String()},date_start.lte.${endOfMonth.toIso8601String()}),'
            'and(date_end.gte.${startOfMonth.toIso8601String()},date_end.lte.${endOfMonth.toIso8601String()})',
          )
          .order(orderBy, ascending: ascending)
          .limit(limit);

      if (offset != null) {
        query = query.range(offset, offset + limit - 1);
      }

      final response = await query;

      return (response as List)
          .map((json) => GroupBroadcast.fromJson(json))
          .toList();
    });
  }

  /// Fetch a single group broadcast by its [id]
  Future<GroupBroadcast> getGroupBroadcastById(String id) async {
    return handleApiCall(() async {
      final response =
          await supabase
              .from('group_broadcasts')
              .select()
              .eq('id', id)
              .single();

      return GroupBroadcast.fromJson(response);
    });
  }

  Future<List<GroupBroadcast>> searchGroupBroadcastsFromSupabase(
    String query,
  ) async {
    if (query.trim().isEmpty) return [];

    return handleApiCall(() async {
      final res = await supabase.rpc(
        'search_group_broadcasts',
        params: {'search_query': query.trim()},
      );

      return (res as List).map((e) => GroupBroadcast.fromJson(e)).toList();
    });
  }
}
