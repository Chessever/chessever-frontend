import 'dart:convert';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/tournaments/tournament_screen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final groupBroadcastLocalStorage = Provider.family<
  _GroupBroadcastLocalStorage,
  TournamentCategory
>((ref, category) => _GroupBroadcastLocalStorage(ref: ref, category: category));

enum _LocalGroupBroadcastStorage { upcoming, current }

class _GroupBroadcastLocalStorage {
  _GroupBroadcastLocalStorage({required this.ref, required this.category});

  final Ref ref;
  final TournamentCategory category;

  String get localStorageName =>
      category == TournamentCategory.upcoming
          ? _LocalGroupBroadcastStorage.upcoming.name
          : _LocalGroupBroadcastStorage.current.name;

  Future<void> fetchAndSaveGroupBroadcasts() async {
    try {
      final broadcasts =
          category == TournamentCategory.upcoming
              ? await ref
                  .read(groupBroadcastRepositoryProvider)
                  .getUpcomingGroupBroadcasts()
              : await ref
                  .read(groupBroadcastRepositoryProvider)
                  .getCurrentGroupBroadcasts();

      final encoded = _encodeGroupBroadcastsList(broadcasts);

      await ref
          .read(sharedPreferencesRepository)
          .setStringList(localStorageName, encoded);
    } catch (_) {
      rethrow;
    }
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
        return _decodeGroupBroadcastsList(fallback ?? []);
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

      final List<MapEntry<GroupBroadcast, double>> scored = [];

      for (final gb in broadcasts) {
        double score = 0.0;

        // Search tags
        for (final term in gb.search) {
          final termLower = term.toLowerCase();
          if (termLower == queryLower) {
            score += 120.0;
            break;
          } else if (termLower.startsWith(queryLower)) {
            score += 100.0;
          } else if (termLower.contains(queryLower)) {
            score += 80.0;
          }
        }

        // Name
        final nameLower = gb.name.toLowerCase();
        if (nameLower.contains(queryLower)) {
          score += nameLower.startsWith(queryLower) ? 60.0 : 40.0;
        }

        if (score > 0) {
          scored.add(MapEntry(gb, score));
        }
      }

      scored.sort((a, b) => b.value.compareTo(a.value));
      const maxResults = 20;
      return scored.take(maxResults).map((e) => e.key).toList();
    } catch (_) {
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
