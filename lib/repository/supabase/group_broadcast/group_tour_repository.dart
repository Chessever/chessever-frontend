import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final groupBroadcastRepositoryProvider =
    AutoDisposeProvider<GroupBroadcastRepository>((ref) {
      return GroupBroadcastRepository();
    });

class GroupBroadcastRepository extends BaseRepository {
  /// Get tour IDs that belong to current (non-past) events
  /// These are tours whose parent group_broadcast is ongoing or upcoming (not completed)
  /// Returns tour IDs that can be matched against games.tour_id
  Future<Set<String>> getCurrentTourIds() async {
    return handleApiCall(() async {
      // First get current group_broadcast IDs
      // Using dynamic type to prevent Dart from optimizing away null check
      final dynamic currentGroupsResponse = await supabase
          .from('group_broadcasts_current')
          .select('id');

      // Handle null response gracefully
      if (currentGroupsResponse == null) {
        return <String>{};
      }

      final currentGroupIds = (currentGroupsResponse as List)
          .map((row) => row['id'] as String)
          .toSet();

      if (currentGroupIds.isEmpty) {
        return <String>{};
      }

      // Then get tour IDs that belong to these group_broadcasts
      // Using dynamic type to prevent Dart from optimizing away null check
      final dynamic toursResponse = await supabase
          .from('tours')
          .select('id, group_broadcast_id')
          .inFilter('group_broadcast_id', currentGroupIds.toList());

      // Handle null response gracefully
      if (toursResponse == null) {
        return <String>{};
      }

      return (toursResponse as List)
          .map((row) => row['id'] as String)
          .toSet();
    });
  }

  /// Get group_broadcast IDs that contain tours with any of the given favorite player FIDE IDs
  Future<Set<String>> getEventIdsWithFavoritePlayers(List<int> favoriteFideIds) async {
    if (favoriteFideIds.isEmpty) return {};

    return handleApiCall(() async {
      // Query tours that have players matching any favorite FIDE ID
      // and return their group_broadcast_id
      final response = await supabase
          .from('tours')
          .select('group_broadcast_id, players')
          .not('group_broadcast_id', 'is', null);

      final matchingIds = <String>{};

      for (final row in response as List) {
        final groupBroadcastId = row['group_broadcast_id'] as String?;
        if (groupBroadcastId == null || groupBroadcastId.isEmpty) continue;

        final players = row['players'] as List?;
        if (players == null || players.isEmpty) continue;

        // Check if any player's fideId matches our favorites
        for (final player in players) {
          if (player is Map) {
            final fideId = player['fideId'];
            if (fideId != null) {
              final fideIdInt = fideId is int ? fideId : int.tryParse(fideId.toString());
              if (fideIdInt != null && favoriteFideIds.contains(fideIdInt)) {
                matchingIds.add(groupBroadcastId);
                break; // Found a match, no need to check other players
              }
            }
          }
        }
      }

      return matchingIds;
    });
  }

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
      // 1) Direct match on group_broadcasts (existing behaviour)
      final directMatch = await _getGroupBroadcastByIdOrNull(id);
      if (directMatch != null) return directMatch;

      // 2) The incoming ID might actually be a tour_id (common for For You tab)
      final tourRow = await _getTourRowById(id);
      if (tourRow != null) {
        // If the tour knows its group_broadcast_id, prefer the canonical record
        final groupBroadcastId = tourRow['group_broadcast_id'] as String?;
        if (groupBroadcastId != null && groupBroadcastId.isNotEmpty) {
          final fromGroupId = await _getGroupBroadcastByIdOrNull(groupBroadcastId);
          if (fromGroupId != null) return fromGroupId;
        }

        // Fall back to a synthesized GroupBroadcast from the tour row
        return _mapTourRowToGroupBroadcast(tourRow);
      }

      // 3) The provided ID might already be the group_broadcast_id stored on tours
      final tourByGroupId = await _getTourRowByGroupId(id);
      if (tourByGroupId != null) {
        return _mapTourRowToGroupBroadcast(
          tourByGroupId,
          overrideGroupBroadcastId: id,
        );
      }

      throw PostgrestException(
        message: 'No rows found',
        code: 'PGRST116',
        details: null,
        hint: null,
      );
    });
  }

  Future<GroupBroadcast> getPastGroupBroadcastById(String id) async {
    return handleApiCall(() async {
      final response =
          await supabase
              .from('group_broadcasts_past')
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

  Future<List<GroupBroadcast>> getGroupBroadcastsForYear({
    required int year,
    int limit = 500,
    String orderBy = 'date_start',
    bool ascending = true,
  }) async {
    return handleApiCall(() async {
      final startOfYear = DateTime(year, 1, 1);
      final endOfYear = DateTime(year, 12, 31, 23, 59, 59);

      final startDateStr = startOfYear.toIso8601String();
      final endDateStr = endOfYear.toIso8601String();

      final response = await supabase
          .from('group_broadcasts')
          .select()
          .or(
            'and(date_start.gte.$startDateStr,date_start.lte.$endDateStr),'
            'and(date_end.gte.$startDateStr,date_end.lte.$endDateStr)',
          )
          .order(orderBy, ascending: ascending)
          .limit(limit);

      return (response as List)
          .map((json) => GroupBroadcast.fromJson(json))
          .toList();
    });
  }

  Future<GroupBroadcast?> _getGroupBroadcastByIdOrNull(String id) async {
    final response =
        await supabase
            .from('group_broadcasts')
            .select()
            .eq('id', id)
            .maybeSingle();

    if (response == null) return null;
    return GroupBroadcast.fromJson(response);
  }

  Future<Map<String, dynamic>?> _getTourRowById(String id) async {
    return supabase.from('tours').select().eq('id', id).maybeSingle();
  }

  Future<Map<String, dynamic>?> _getTourRowByGroupId(String id) async {
    // Use limit(1) instead of maybeSingle() because events with categories
    // (U17, U19, Open, etc.) have multiple tours with the same group_broadcast_id
    final response = await supabase
        .from('tours')
        .select()
        .eq('group_broadcast_id', id)
        .limit(1);
    if (response.isEmpty) return null;
    return response.first;
  }

  /// Get tour IDs that belong to a specific group_broadcast
  /// Used to fetch games for a single event in the For You tab
  Future<List<String>> getTourIdsForGroupBroadcast(String groupBroadcastId) async {
    return handleApiCall(() async {
      final dynamic response = await supabase
          .from('tours')
          .select('id')
          .eq('group_broadcast_id', groupBroadcastId);

      if (response == null) return <String>[];

      return (response as List)
          .map((row) => row['id'] as String)
          .toList();
    });
  }

  /// Get mapping from tour_id to group_broadcast_id for given tour IDs
  /// This is used to group games by their parent event (group_broadcast) in For You tab
  Future<Map<String, String>> getTourToGroupBroadcastMapping(List<String> tourIds) async {
    if (tourIds.isEmpty) return {};

    return handleApiCall(() async {
      // Using dynamic type to prevent Dart from optimizing away null check
      final dynamic response = await supabase
          .from('tours')
          .select('id, group_broadcast_id')
          .inFilter('id', tourIds);

      // Handle null response gracefully
      if (response == null) {
        return <String, String>{};
      }

      final mapping = <String, String>{};
      for (final row in response as List) {
        final tourId = row['id'] as String?;
        final groupBroadcastId = row['group_broadcast_id'] as String?;
        if (tourId != null && groupBroadcastId != null && groupBroadcastId.isNotEmpty) {
          mapping[tourId] = groupBroadcastId;
        }
      }
      return mapping;
    });
  }

  /// Get GroupBroadcast details with average ELO for given group_broadcast IDs
  /// Returns a map of group_broadcast_id → GroupBroadcast (with maxAvgElo populated)
  Future<Map<String, GroupBroadcast>> getGroupBroadcastsWithElo(List<String> groupBroadcastIds) async {
    if (groupBroadcastIds.isEmpty) return {};

    return handleApiCall(() async {
      final response = await supabase
          .from('group_broadcasts')
          .select('id, name, max_avg_elo, date_start, date_end, time_control, created_at, search')
          .inFilter('id', groupBroadcastIds);

      final result = <String, GroupBroadcast>{};
      for (final row in response as List) {
        final broadcast = GroupBroadcast.fromJson(row);
        result[broadcast.id] = broadcast;
      }
      return result;
    });
  }

  /// Get group broadcasts by country location.
  /// Queries tours table for location match, then fetches corresponding group_broadcasts.
  /// Returns results sorted with current+upcoming events first, then past events by date.
  Future<List<GroupBroadcast>> getGroupBroadcastsByCountry({
    required String countryName,
    String? searchQuery,
    int limit = 30,
    int offset = 0,
  }) async {
    return handleApiCall(() async {
      // Step 1: Query tours with country location filter to get group_broadcast_ids
      var tourQuery = supabase
          .from('tours')
          .select('id, group_broadcast_id, name, slug, info, dates, avg_elo, search, created_at')
          .ilike('info->>location', '%$countryName%');

      // Add search filter if provided
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        tourQuery = tourQuery.ilike('name', '%${searchQuery.trim()}%');
      }

      final tourResponse = await tourQuery;

      if ((tourResponse as List).isEmpty) {
        return <GroupBroadcast>[];
      }

      // Step 2: Collect unique group_broadcast_ids and tour data for fallback
      final groupBroadcastIds = <String>{};
      final tourDataById = <String, Map<String, dynamic>>{};

      for (final tour in tourResponse) {
        final groupId = tour['group_broadcast_id'] as String?;
        final tourId = tour['id'] as String;
        tourDataById[tourId] = tour;

        if (groupId != null && groupId.isNotEmpty) {
          groupBroadcastIds.add(groupId);
        }
      }

      // Step 3: Fetch actual group_broadcasts for those that have group_broadcast_id
      Map<String, GroupBroadcast> groupBroadcastsMap = {};
      if (groupBroadcastIds.isNotEmpty) {
        groupBroadcastsMap = await getGroupBroadcastsWithElo(groupBroadcastIds.toList());
      }

      // Step 4: Build result list - use group_broadcast if available, otherwise create from tour
      final seenIds = <String>{};
      final results = <GroupBroadcast>[];

      for (final tour in tourResponse) {
        final groupId = tour['group_broadcast_id'] as String?;
        final tourId = tour['id'] as String;

        GroupBroadcast? broadcast;

        if (groupId != null && groupId.isNotEmpty && groupBroadcastsMap.containsKey(groupId)) {
          // Use the actual group_broadcast
          if (!seenIds.contains(groupId)) {
            broadcast = groupBroadcastsMap[groupId];
            seenIds.add(groupId);
          }
        } else {
          // Create synthetic GroupBroadcast from tour data
          if (!seenIds.contains(tourId)) {
            broadcast = _mapTourRowToGroupBroadcast(tour);
            seenIds.add(tourId);
          }
        }

        if (broadcast != null) {
          results.add(broadcast);
        }
      }

      // Step 5: Sort with current+upcoming first, then past events
      final now = DateTime.now();
      results.sort((a, b) {
        final aIsCurrent = _isCurrentOrUpcoming(a, now);
        final bIsCurrent = _isCurrentOrUpcoming(b, now);

        // Current/upcoming events come first
        if (aIsCurrent && !bIsCurrent) return -1;
        if (!aIsCurrent && bIsCurrent) return 1;

        // Within same category, sort by start date (most recent first for past, soonest first for upcoming)
        final aDate = a.dateStart ?? a.dateEnd ?? a.createdAt;
        final bDate = b.dateStart ?? b.dateEnd ?? b.createdAt;

        if (aIsCurrent) {
          // For current/upcoming: soonest first
          return aDate.compareTo(bDate);
        } else {
          // For past: most recent first
          return bDate.compareTo(aDate);
        }
      });

      // Step 6: Apply pagination
      final paginatedResults = results.skip(offset).take(limit).toList();

      return paginatedResults;
    });
  }

  /// Check if event is current or upcoming (not past)
  bool _isCurrentOrUpcoming(GroupBroadcast broadcast, DateTime now) {
    final endDate = broadcast.dateEnd;
    final startDate = broadcast.dateStart;

    // If we have end date and it's in the past, it's completed
    if (endDate != null && now.isAfter(endDate)) {
      return false;
    }

    // If we only have start date and it's more than a week in the past, consider it past
    if (endDate == null && startDate != null) {
      final weekAfterStart = startDate.add(const Duration(days: 7));
      if (now.isAfter(weekAfterStart)) {
        return false;
      }
    }

    return true;
  }

  GroupBroadcast _mapTourRowToGroupBroadcast(
    Map<String, dynamic> tourRow, {
    String? overrideGroupBroadcastId,
  }) {
    final dates = (tourRow['dates'] as List?)
            ?.whereType<String>()
            .map((d) => DateTime.tryParse(d))
            .whereType<DateTime>()
            .toList() ??
        <DateTime>[];

    final info = tourRow['info'] as Map<String, dynamic>?;
    final timeControl = info?['fideTc'] as String? ?? info?['tc'] as String?;

    final search = (tourRow['search'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        <String>[];

    final fallbackSearch = <String?>[
      tourRow['slug'] as String?,
      tourRow['name'] as String?,
      tourRow['id'] as String?,
    ].whereType<String>().where((e) => e.isNotEmpty).toList();

    // Get group_broadcast_id, treating empty string as null
    final groupBroadcastIdFromRow = tourRow['group_broadcast_id'] as String?;
    final effectiveGroupBroadcastId =
        (groupBroadcastIdFromRow?.isNotEmpty == true) ? groupBroadcastIdFromRow : null;

    return GroupBroadcast(
      id: overrideGroupBroadcastId ?? effectiveGroupBroadcastId ?? tourRow['id'] as String,
      createdAt:
          tourRow['created_at'] != null
              ? DateTime.tryParse(tourRow['created_at'] as String) ??
                  DateTime.now()
              : DateTime.now(),
      name:
          (tourRow['name'] as String?) ??
          (tourRow['slug'] as String?) ??
          'Tournament',
      search: {...search, ...fallbackSearch}.toList(),
      maxAvgElo: tourRow['avg_elo'] as int?,
      dateStart: dates.isNotEmpty ? dates.first : null,
      dateEnd:
          dates.length > 1
              ? dates.last
              : dates.isNotEmpty
                  ? dates.first
                  : null,
      timeControl: timeControl,
    );
  }
}
