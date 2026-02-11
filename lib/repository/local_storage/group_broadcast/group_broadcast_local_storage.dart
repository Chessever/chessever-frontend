import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
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
        return _LocalGroupBroadcastStorage.upcoming.name;
      case GroupEventCategory.current:
        return _LocalGroupBroadcastStorage.current.name;
      case GroupEventCategory.past:
        return _LocalGroupBroadcastStorage.past.name;
      case GroupEventCategory.search:
        return _LocalGroupBroadcastStorage.current.name;
    }
  }

  String get _cacheKey => 'group_broadcast_$localStorageName';
  String get _cacheTimeKey => 'group_broadcast_${localStorageName}_time';

  Future<void> fetchAndSaveGroupBroadcasts() async {
    try {
      List<GroupBroadcast> broadcasts = [];
      switch (category) {
        case GroupEventCategory.forYou:
        case GroupEventCategory.search:
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
              .getPastGroupBroadcasts(limit: 300);
          broadcasts = await _ensureStarredEventsIncluded(events);
          break;
      }

      final db = ref.read(appDatabaseProvider);
      final encoded = _encodeGroupBroadcastsList(broadcasts);
      await db.setCacheAndInt(
        cacheKey: _cacheKey,
        cacheValue: jsonEncode(encoded),
        intKey: _cacheTimeKey,
        intValue: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // Local storage failure is not critical - Supabase is source of truth
    }
  }

  Future<List<GroupBroadcast>> fetchGroupBroadcasts() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final lastFetched = await db.getInt(_cacheTimeKey);
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
    } catch (_) {
      return <GroupBroadcast>[];
    }
  }

  Future<List<GroupBroadcast>> _ensureStarredEventsIncluded(
    List<GroupBroadcast> tours,
  ) async {
    final starredIds = ref.read(starredProvider(localStorageName));
    final allStarredIds = <String>{...starredIds};

    if (allStarredIds.isEmpty) return tours;

    final currentIds = tours.map((t) => t.id).toSet();
    final missingStarredIds = allStarredIds.where(
      (id) => !currentIds.contains(id),
    );

    if (missingStarredIds.isEmpty) return tours;

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
      final db = ref.read(appDatabaseProvider);
      final entry = await db.getCache(key: _cacheKey);
      if (entry == null) return <GroupBroadcast>[];

      final jsonList = jsonDecode(entry.value) as List;
      return _decodeGroupBroadcastsList(jsonList.cast<String>());
    } catch (_) {
      return <GroupBroadcast>[];
    }
  }

  Future<List<GroupBroadcast>> refresh() async {
    try {
      await fetchAndSaveGroupBroadcasts();
      return getGroupBroadcasts();
    } catch (_) {
      return <GroupBroadcast>[];
    }
  }

  Future<List<GroupBroadcast>> searchGroupBroadcastsByName(String query) async {
    try {
      final broadcasts = await getGroupBroadcasts();
      if (query.isEmpty) return broadcasts;

      final queryLower = query.toLowerCase().trim();
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
        return queryWords.every((word) => allText.contains(word));
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

List<GroupBroadcast> decodeGroupBroadcastsInIsolate(List<String> jsonStrings) =>
    jsonStrings.map((e) => GroupBroadcast.fromJson(json.decode(e))).toList();
