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
    String orderBy = 'created_at',
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
        query = query.range(offset, offset + (limit ?? 50) - 1);
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
    String orderBy = 'created_at',
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
        query = query.range(offset, offset + (limit ?? 50) - 1);
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

  /// Search group broadcasts whose name matches [searchQuery] (case-insensitive)
  Future<List<GroupBroadcast>> searchGroupBroadcastsByName(
    String searchQuery,
  ) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('group_broadcasts')
          .select()
          .ilike('name', '%$searchQuery%')
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => GroupBroadcast.fromJson(json))
          .toList();
    });
  }

  /// Filter group broadcasts that are active for the current date
  Future<List<GroupBroadcast>> getActiveGroupBroadcasts() async {
    final now = DateTime.now();
    return handleApiCall(() async {
      final response = await supabase
          .from('group_broadcasts')
          .select()
          .order('created_at', ascending: false);

      final broadcasts =
          (response as List)
              .map((json) => GroupBroadcast.fromJson(json))
              .toList();

      return broadcasts.where((gb) {
        final starts = gb.dateStart;
        final ends = gb.dateEnd;

        if (starts == null || ends == null) return false;
        return now.isAfter(starts) && now.isBefore(ends);
      }).toList();
    });
  }

  /// Fetch the most recently created group broadcasts
  Future<List<GroupBroadcast>> getRecentGroupBroadcasts({
    int limit = 10,
  }) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('group_broadcasts')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);

      return (response as List)
          .map((json) => GroupBroadcast.fromJson(json))
          .toList();
    });
  }

  /// Filter by maximum average ELO ceiling
  Future<List<GroupBroadcast>> getGroupBroadcastsByMaxAvgElo(
    int maxAvgElo,
  ) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('group_broadcasts')
          .select()
          .lte('max_avg_elo', maxAvgElo)
          .order('max_avg_elo', ascending: true);

      return (response as List)
          .map((json) => GroupBroadcast.fromJson(json))
          .toList();
    });
  }

  /// Filter by time control
  Future<List<GroupBroadcast>> getGroupBroadcastsByTimeControl(
    String timeControl,
  ) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('group_broadcasts')
          .select()
          .eq('time_control', timeControl)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => GroupBroadcast.fromJson(json))
          .toList();
    });
  }
}
