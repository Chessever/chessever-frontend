import 'dart:convert';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';
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
      case GroupEventCategory.forYou:
        // ForYou shows games, not events, so use upcoming storage key for backwards compatibility
        return _LocalGroupBroadcastStorage.upcoming.name;
      case GroupEventCategory.current:
        return _LocalGroupBroadcastStorage.current.name;
      case GroupEventCategory.past:
        return _LocalGroupBroadcastStorage.past.name;
    }
  }

  String get localStorageTimeName {
    switch (category) {
      case GroupEventCategory.forYou:
        // ForYou shows games, not events, so use upcoming storage key for backwards compatibility
        return '${_LocalGroupBroadcastStorage.upcoming.name}_time';
      case GroupEventCategory.current:
        return '${_LocalGroupBroadcastStorage.current.name}_time';
      case GroupEventCategory.past:
        return '${_LocalGroupBroadcastStorage.past.name}_time';
    }
  }

  Future<void> fetchAndSaveGroupBroadcasts() async {
    try {
      List<GroupBroadcast> broadcasts = [];
      switch (category) {
        case GroupEventCategory.forYou:
          // ForYou shows games, not events, so return empty list
          broadcasts = [];
          break;
        case GroupEventCategory.current:
          broadcasts =
              await ref
                  .read(groupBroadcastRepositoryProvider)
                  .getCurrentGroupBroadcasts();
          break;
        case GroupEventCategory.past:
          final events = await ref
              .read(groupBroadcastRepositoryProvider)
              .getPastGroupBroadcasts(limit: 50);
          broadcasts = await _ensureStarredEventsIncluded(events);
          break;
      }

      await ref
          .read(sharedPreferencesRepository)
          .setStringList(
            localStorageName,
            _encodeGroupBroadcastsList(broadcasts),
          );
      await ref
          .read(sharedPreferencesRepository)
          .setInt(localStorageTimeName, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      rethrow;
    }
  }

  Future<List<GroupBroadcast>> fetchGroupBroadcasts() async {
    final lastFetched = await ref
        .read(sharedPreferencesRepository)
        .getInt(localStorageTimeName);
    final totalValues = await getGroupBroadcasts();
    if (lastFetched != null) {
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      final difference = currentTime - lastFetched;
      // If data is older than 25 minutes, refresh it
      if (difference > 25 * 60 * 1000 || totalValues.isEmpty) {
        await fetchAndSaveGroupBroadcasts();
        return getGroupBroadcasts();
      } else {
        return getGroupBroadcasts();
      }
    } else {
      await fetchAndSaveGroupBroadcasts();
      return getGroupBroadcasts();
    }
  }

  Future<List<GroupBroadcast>> _ensureStarredEventsIncluded(
    List<GroupBroadcast> tours,
  ) async {
    // Get starred event IDs
    final starredIds = ref.read(starredProvider(localStorageName));

    final allStarredIds = <String>{...starredIds};

    if (allStarredIds.isEmpty) return tours;

    // Find starred events that might not be in current tour list
    final currentIds = tours.map((t) => t.id).toSet();
    final missingStarredIds = allStarredIds.where(
      (id) => !currentIds.contains(id),
    );

    if (missingStarredIds.isEmpty) return tours;

    // Fetch missing starred events
    final missingStarredEvents = <GroupBroadcast>[];
    for (final id in missingStarredIds) {
      try {
        final event = await ref
            .read(groupBroadcastRepositoryProvider)
            .getPastGroupBroadcastById(id);
        missingStarredEvents.add(event);
      } catch (e) {
        continue;
      }
    }

    return [
      ...missingStarredEvents.where((e) => !currentIds.contains(e.id)),
      ...tours,
    ];
  }

  Future<List<GroupBroadcast>> getGroupBroadcasts() async {
    try {
      final jsonList = await ref
          .read(sharedPreferencesRepository)
          .getStringList(localStorageName);
      if (jsonList.isEmpty) {
        return <GroupBroadcast>[];
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
        return <GroupBroadcast>[];
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
}

List<String> _encodeGroupBroadcastsList(List<GroupBroadcast> list) =>
    list.map((e) => json.encode(e.toJson())).toList();

List<GroupBroadcast> _decodeGroupBroadcastsList(List<String> jsonList) =>
    jsonList.map((e) => GroupBroadcast.fromJson(json.decode(e))).toList();

/// Optional isolate-friendly decoder
List<GroupBroadcast> decodeGroupBroadcastsInIsolate(List<String> jsonStrings) =>
    jsonStrings.map((e) => GroupBroadcast.fromJson(json.decode(e))).toList();
