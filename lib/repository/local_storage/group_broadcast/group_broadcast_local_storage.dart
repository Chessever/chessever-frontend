import 'dart:convert';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final groupBroadcastLocalStorage = Provider.family<
  GroupBroadcastLocalStorage,
  GroupEventCategory
>((ref, category) => GroupBroadcastLocalStorage(ref: ref, category: category));

enum _LocalGroupBroadcastStorage { upcoming, current, past }

class GroupBroadcastLocalStorage {
  GroupBroadcastLocalStorage({required this.ref, required this.category});

  final Ref ref;
  final GroupEventCategory category;

  String get localStorageName {
    switch (category) {
      case GroupEventCategory.upcoming:
        return _LocalGroupBroadcastStorage.upcoming.name;
      case GroupEventCategory.current:
        return _LocalGroupBroadcastStorage.current.name;
      case GroupEventCategory.past:
        return _LocalGroupBroadcastStorage.past.name;
    }
  }

  Future<void> fetchAndSaveGroupBroadcasts() async {
    try {
      final broadcasts;
      switch (category) {
        case GroupEventCategory.upcoming:
          broadcasts =
              await ref
                  .read(groupBroadcastRepositoryProvider)
                  .getUpcomingGroupBroadcasts();
          break;
        case GroupEventCategory.current:
          broadcasts =
              await ref
                  .read(groupBroadcastRepositoryProvider)
                  .getCurrentGroupBroadcasts();
          break;
        case GroupEventCategory.past:
          broadcasts = await ref
              .read(groupBroadcastRepositoryProvider)
              .getPastGroupBroadcasts(limit: 50);
          break;
      }

      broadcasts.sort((GroupBroadcast a, GroupBroadcast b) {
        // If both have null maxAvgElo, maintain original order
        if (a.maxAvgElo == null && b.maxAvgElo == null) return 0;

        // If a is null, put it after b
        if (a.maxAvgElo == null) return 1;

        // If b is null, put it after a
        if (b.maxAvgElo == null) return -1;

        // Both are non-null, sort in descending order
        return b.maxAvgElo!.compareTo(a.maxAvgElo!);
      });

      final encoded = _encodeGroupBroadcastsList(broadcasts);

      await ref
          .read(sharedPreferencesRepository)
          .setStringList(localStorageName, encoded);
    } catch (_) {
      rethrow;
    }
  }

  Future<List<GroupBroadcast>> fetchGroupBroadcasts() async {
    await fetchAndSaveGroupBroadcasts();
    return getGroupBroadcasts();
  }

  Future<List<GroupBroadcast>> getGroupBroadcasts() async {
    try {
      final jsonList = await ref
          .read(sharedPreferencesRepository)
          .getStringList(localStorageName);

      if (jsonList.isEmpty) {
        await fetchAndSaveGroupBroadcasts();
        return getGroupBroadcasts();
      }

      return _decodeGroupBroadcastsList(jsonList);
    } catch (_) {
      return <GroupBroadcast>[];
    }
  }

  /// Refreshes the cached data from the network and returns the fresh list
  Future<List<GroupBroadcast>> refresh() async {
    try {
      await fetchAndSaveGroupBroadcasts();
      final jsonList = await ref
          .read(sharedPreferencesRepository)
          .getStringList(localStorageName);
      if (jsonList.isNotEmpty) {
        return _decodeGroupBroadcastsList(jsonList);
      } else {
        await fetchAndSaveGroupBroadcasts();
        final fallback = await ref
            .read(sharedPreferencesRepository)
            .getStringList(localStorageName);
        return _decodeGroupBroadcastsList(fallback);
      }
    } catch (_) {
      return <GroupBroadcast>[];
    }
  }

  /// Case-insensitive search by name or search tags (same scoring logic as tours)
  Future<List<GroupBroadcast>> searchGroupBroadcastsByName(String query) async {
    try {
      final broadcasts = await getGroupBroadcasts();
      if (query.isEmpty) return broadcasts;

      final queryLower = query.toLowerCase().trim();

      // Split into words for flexible matching
      final queryWords =
          queryLower
              .split(RegExp(r'\s+'))
              .where((word) => word.isNotEmpty)
              .toList();

      return broadcasts.where((gb) {
        final nameLower = gb.name.toLowerCase();
        final allText = [
          nameLower,
          ...gb.search.map((s) => s.toLowerCase()),
        ].join(' ');

        // Option 1: All words must be present (AND search)
        return queryWords.every((word) => allText.contains(word));

        // Option 2: Any word can be present (OR search) - uncomment if preferred
        // return queryWords.any((word) => allText.contains(word));
      }).toList();
    } catch (e) {
      return <GroupBroadcast>[];
    }
  }

  /// Paginated loader for PAST tab (25 at a time)
  Future<List<GroupBroadcast>> fetchPastGroupBroadcastsPaginated({
    required int limit,
    required int offset,
  }) async {
    try {
      final broadcasts = await ref
          .read(groupBroadcastRepositoryProvider)
          .getPastGroupBroadcasts(limit: limit, offset: offset);

      // keep the same maxAvgElo sort & cache overwrite as the full fetch
      broadcasts.sort((a, b) {
        if (a.maxAvgElo == null && b.maxAvgElo == null) return 0;
        if (a.maxAvgElo == null) return 1;
        if (b.maxAvgElo == null) return -1;
        return b.maxAvgElo!.compareTo(a.maxAvgElo!);
      });

      final encoded = _encodeGroupBroadcastsList(broadcasts);
      await ref
          .read(sharedPreferencesRepository)
          .setStringList(localStorageName, encoded);

      return broadcasts;
    } catch (_) {
      rethrow;
    }
  }
}

List<String> _encodeGroupBroadcastsList(List<GroupBroadcast> list) =>
    list.map((e) => json.encode(e.toJson())).toList();

List<GroupBroadcast> _decodeGroupBroadcastsList(List<String> jsonList) =>
    jsonList.map((e) => GroupBroadcast.fromJson(json.decode(e))).toList();

/// Optional isolate-friendly decoder
List<GroupBroadcast> decodeGroupBroadcastsInIsolate(List<String> jsonStrings) =>
    jsonStrings.map((e) => GroupBroadcast.fromJson(json.decode(e))).toList();
