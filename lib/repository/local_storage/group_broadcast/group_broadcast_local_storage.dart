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

/// Upcoming is read soonest-first and capped: the far end of the schedule is
/// what a cap should drop, and the cache stays a bounded blob.
const int kUpcomingEventsFetchLimit = 300;

class GroupBroadcastLocalStorage {
  GroupBroadcastLocalStorage({required this.ref, required this.category});

  final Ref ref;
  final GroupEventCategory category;

  String get localStorageName {
    switch (category) {
      case GroupEventCategory.upcoming:
        return _LocalGroupBroadcastStorage.upcoming.name;
      case GroupEventCategory.past:
        return _LocalGroupBroadcastStorage.past.name;
      // Search keeps no event list of its own. It aliases Current so a refresh
      // through it re-reads Current instead of saving an empty list over the
      // Current cache.
      case GroupEventCategory.current:
      case GroupEventCategory.search:
        return _LocalGroupBroadcastStorage.current.name;
    }
  }

  String get _cacheKey => 'group_broadcast_$localStorageName';
  String get _cacheTimeKey => 'group_broadcast_${localStorageName}_time';

  /// Background warm-up: a failure here is silent because the tab's own load
  /// fetches again and reports it.
  Future<void> fetchAndSaveGroupBroadcasts() async {
    try {
      await _fetchSaveAndReturnGroupBroadcasts();
    } catch (_) {}
  }

  Future<List<GroupBroadcast>> _fetchGroupBroadcastsFromSource() async {
    switch (category) {
      case GroupEventCategory.current:
      case GroupEventCategory.search:
        return ref
            .read(groupBroadcastRepositoryProvider)
            .getCurrentGroupBroadcasts();
      case GroupEventCategory.upcoming:
        return ref
            .read(groupBroadcastRepositoryProvider)
            .getUpcomingGroupBroadcasts(
              orderBy: 'date_start',
              ascending: true,
              limit: kUpcomingEventsFetchLimit,
            );
      case GroupEventCategory.past:
        final events = await ref
            .read(groupBroadcastRepositoryProvider)
            .getPastGroupBroadcasts(limit: 300);
        return _ensureStarredEventsIncluded(events);
    }
  }

  /// Only the server read can fail this call. The list is returned even when
  /// the cache write fails: the write is best effort, and letting it throw
  /// would turn fetched events into an error.
  Future<List<GroupBroadcast>> _fetchSaveAndReturnGroupBroadcasts() async {
    final broadcasts = await _fetchGroupBroadcastsFromSource();
    _memoize(broadcasts);
    try {
      final db = ref.read(appDatabaseProvider);
      final encoded = _encodeGroupBroadcastsList(broadcasts);
      await db.setCacheAndInt(
        cacheKey: _cacheKey,
        cacheValue: jsonEncode(encoded),
        intKey: _cacheTimeKey,
        intValue: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
    return broadcasts;
  }

  /// Serves the cache while it is fresh, otherwise reads the server.
  ///
  /// A failed server read falls back to the cache. With nothing cached it
  /// throws instead of returning an empty list, so the caller shows an error
  /// with Retry rather than an empty state that says there are no events.
  Future<List<GroupBroadcast>> fetchGroupBroadcasts() async {
    final cachedBroadcasts = await getGroupBroadcasts();
    int? lastFetched;
    try {
      lastFetched = await ref.read(appDatabaseProvider).getInt(_cacheTimeKey);
    } catch (_) {
      // An unreadable timestamp counts as stale.
    }
    final isFresh =
        lastFetched != null &&
        cachedBroadcasts.isNotEmpty &&
        (DateTime.now().millisecondsSinceEpoch - lastFetched) <=
            25 * 60 * 1000;
    if (isFresh) return cachedBroadcasts;

    try {
      return await _fetchSaveAndReturnGroupBroadcasts();
    } catch (_) {
      if (cachedBroadcasts.isNotEmpty) return cachedBroadcasts;
      rethrow;
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

  // Decoding the cached list is expensive (full jsonDecode + model parsing
  // on the UI isolate) and search hits this on every debounced query.
  // Memoize briefly; writers refresh the memo below.
  List<GroupBroadcast>? _memoizedBroadcasts;
  DateTime? _memoizedAt;
  static const _memoTtl = Duration(seconds: 60);

  void _memoize(List<GroupBroadcast> broadcasts) {
    _memoizedBroadcasts = broadcasts;
    _memoizedAt = DateTime.now();
  }

  Future<List<GroupBroadcast>> getGroupBroadcasts() async {
    final memo = _memoizedBroadcasts;
    final memoAt = _memoizedAt;
    if (memo != null &&
        memoAt != null &&
        DateTime.now().difference(memoAt) < _memoTtl) {
      return memo;
    }
    try {
      final db = ref.read(appDatabaseProvider);
      final entry = await db.getCache(key: _cacheKey);
      if (entry == null) return <GroupBroadcast>[];

      final jsonList = jsonDecode(entry.value) as List;
      final decoded = _decodeGroupBroadcastsList(jsonList.cast<String>());
      _memoize(decoded);
      return decoded;
    } catch (_) {
      return <GroupBroadcast>[];
    }
  }

  /// Reads the server, bypassing the cache TTL. A failure falls back to the
  /// cache and, like [fetchGroupBroadcasts], throws when nothing is cached.
  Future<List<GroupBroadcast>> refresh() async {
    try {
      return await _fetchSaveAndReturnGroupBroadcasts();
    } catch (_) {
      final cached = await getGroupBroadcasts();
      if (cached.isNotEmpty) return cached;
      rethrow;
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
