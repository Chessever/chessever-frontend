import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const kForYouFeedCacheMaxAge = Duration(minutes: 5);

String forYouFeedCacheFilterKey(FilterPopupState filters) {
  final formatsAndStates =
      filters.formatsAndStates
          .map((value) => value.toLowerCase())
          .toSet()
          .toList()
        ..sort();
  return jsonEncode({
    'formatsAndStates': formatsAndStates,
    'minElo': filters.hasEloFilter ? filters.minElo : null,
    'maxElo': filters.hasEloFilter ? filters.maxElo : null,
  });
}

class ForYouFeedCacheEntry {
  const ForYouFeedCacheEntry({
    required this.filterKey,
    required this.cachedAt,
    required this.broadcasts,
    required this.gamesByEventId,
    required this.hasMore,
  });

  final String filterKey;
  final DateTime cachedAt;
  final List<GroupBroadcast> broadcasts;
  final Map<String, List<Games>> gamesByEventId;
  final bool hasMore;

  bool isFreshFor(String requestedFilterKey, DateTime now) {
    final age = now.difference(cachedAt);
    return filterKey == requestedFilterKey &&
        age >= Duration.zero &&
        age <= kForYouFeedCacheMaxAge &&
        cachedAt.toLocal().year == now.toLocal().year &&
        cachedAt.toLocal().month == now.toLocal().month &&
        cachedAt.toLocal().day == now.toLocal().day;
  }

  Map<String, dynamic> toJson() => {
    'filterKey': filterKey,
    'cachedAt': cachedAt.toIso8601String(),
    'hasMore': hasMore,
    'broadcasts': broadcasts.map((broadcast) => broadcast.toJson()).toList(),
    'gamesByEventId': {
      for (final entry in gamesByEventId.entries)
        entry.key: entry.value.map((game) => game.toJson()).toList(),
    },
  };

  factory ForYouFeedCacheEntry.fromJson(Map<String, dynamic> json) {
    return ForYouFeedCacheEntry(
      filterKey: json['filterKey'] as String,
      cachedAt: DateTime.parse(json['cachedAt'] as String),
      hasMore: json['hasMore'] as bool,
      broadcasts: [
        for (final row in json['broadcasts'] as List)
          GroupBroadcast.fromJson(Map<String, dynamic>.from(row as Map)),
      ],
      gamesByEventId: {
        for (final entry in (json['gamesByEventId'] as Map).entries)
          entry.key as String: [
            for (final row in entry.value as List)
              Games.fromJson(Map<String, dynamic>.from(row as Map)),
          ],
      },
    );
  }
}

final forYouFeedLocalStorageProvider = Provider<ForYouFeedLocalStorage>(
  (ref) => ForYouFeedLocalStorage(ref.read(appDatabaseProvider)),
);

/// One bounded first page of public broadcast data. Favorites, pins and live
/// indicators are resolved for the current session, never restored from disk.
class ForYouFeedLocalStorage {
  ForYouFeedLocalStorage(this.database);

  final AppDatabase database;
  static const _cacheKey = 'for_you_first_page_v1';

  Future<ForYouFeedCacheEntry?> read({required String filterKey}) async {
    try {
      final stored = await database.getCache(key: _cacheKey);
      if (stored == null) return null;
      final entry = ForYouFeedCacheEntry.fromJson(
        jsonDecode(stored.value) as Map<String, dynamic>,
      );
      return entry.isFreshFor(filterKey, DateTime.now()) ? entry : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(ForYouFeedCacheEntry entry) async {
    try {
      await database.setCache(
        key: _cacheKey,
        value: jsonEncode(entry.toJson()),
      );
    } catch (_) {
      // Local storage must never turn a successful feed request into an error.
    }
  }
}
