import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which of one collection's stories the reader has seen: the game ids of
/// its stories they watched past half (or to the result), kept to the
/// stories the collection shows, and how many games it held then.
///
/// A collection that gained games its stories show reads as new again,
/// from its first new story ([StorySeenNotifier.resumeIndex]).
@immutable
class StorySeen {
  const StorySeen({
    this.ids = const [],
    required this.count,
    required this.full,
    this.legacyNext,
  });

  /// The seen stories' game ids, at most the stories the collection shows.
  final List<String> ids;

  /// How many games the collection held when the record was last counted
  /// (its catalog row's `gameCount`).
  final int count;

  /// Every story the collection showed then had been seen.
  final bool full;

  /// A record from before seen games were kept by id (39.0.1): how many
  /// stories, from the first, the reader had moved past. Turned into ids
  /// the first time the collection's stories are read.
  final int? legacyNext;

  Map<String, Object> toJson() => {
    'i': ids,
    'c': count,
    'f': full,
    'n': ?legacyNext,
  };

  static StorySeen? fromJson(Object? json) {
    if (json is! Map) return null;
    final ids = json['i'];
    if (ids is List) {
      final count = json['c'];
      final full = json['f'];
      final next = json['n'];
      if (count is! int || full is! bool) return null;
      return StorySeen(
        ids: List.unmodifiable(ids.whereType<String>()),
        count: count,
        full: full,
        legacyNext: next is int ? next : null,
      );
    }
    return _fromLegacy(json);
  }

  /// 39.0.1's record: a signature (`gameCount:contentVersion`), the first
  /// story not moved past, and whether the ring went quiet. 39.0.1 quieted
  /// a ring after one story; a ring the reader saw go quiet stays quiet
  /// (every story it showed counts as seen), unless the collection really
  /// got new games since. A record whose ring was still lit keeps the
  /// stories moved past.
  static StorySeen? _fromLegacy(Map<dynamic, dynamic> json) {
    final signature = json['s'];
    final next = json['n'];
    final seen = json['v'];
    if (signature is! String || next is! int || seen is! bool) return null;
    final count = int.tryParse(signature.split(':').first) ?? 0;
    final shown = count < kStoryCap ? count : kStoryCap;
    final full = seen && shown > 0;
    return StorySeen(
      count: count,
      full: full,
      legacyNext: full ? shown : (next < 0 ? 0 : next),
    );
  }
}

/// Whether a collection that held [before] games and holds [now] has new
/// games among its stories: a book lists its latest games first, so any
/// new game is a new story; anything else adds its games after the ones its
/// stories already show, which are new stories only while those were fewer
/// than [kStoryCap].
bool storyGainedGames(CollectionKind kind, int before, int now) {
  if (now <= before) return false;
  return kind == CollectionKind.book || before < kStoryCap;
}

/// The store behind [storySeenProvider]: one JSON document on the device.
abstract class StorySeenStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPreferencesStorySeenStorage implements StorySeenStorage {
  const SharedPreferencesStorySeenStorage();

  static const String key = 'today_stories_seen_v1';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}

final storySeenStorageProvider = Provider<StorySeenStorage>(
  (ref) => const SharedPreferencesStorySeenStorage(),
);

/// What the reader has watched, per collection slug. Null until the
/// device's record is read (the row waits for it, so no ring flips on
/// launch).
final storySeenProvider =
    StateNotifierProvider<StorySeenNotifier, Map<String, StorySeen>?>(
      (ref) => StorySeenNotifier(ref.watch(storySeenStorageProvider)),
    );

class StorySeenNotifier extends StateNotifier<Map<String, StorySeen>?> {
  StorySeenNotifier(this._storage) : super(null) {
    unawaited(_load());
  }

  final StorySeenStorage _storage;

  /// Collections remembered at most; the longest untouched go first.
  static const int capacity = 200;

  /// The document's format: `{"v": 2, "c": {slug: record}}`. 39.0.1 wrote
  /// the records map bare, which is read and rewritten on the next change.
  static const int _version = 2;

  Future<void> _load() async {
    // A map literal keeps insertion order: oldest first.
    final records = <String, StorySeen>{};
    try {
      final raw = await _storage.read();
      final json = raw == null ? null : jsonDecode(raw);
      final entries = json is Map && json['v'] == _version ? json['c'] : json;
      if (entries is Map) {
        for (final MapEntry(:key, :value) in entries.entries) {
          final record = StorySeen.fromJson(value);
          if (key is String && record != null) records[key] = record;
        }
      }
    } catch (e) {
      debugPrint('[Stories] seen record unreadable: $e');
    }
    if (!mounted) return;
    // A mark made before the record was read wins over the read.
    state = {...records, ...?state};
  }

  /// Whether [collection]'s circle reads as watched: every story it showed
  /// was seen, and it has no new game among its stories since.
  bool isSeen(Collection collection) {
    final record = state?[collection.slug];
    if (record == null || !record.full) return false;
    return !storyGainedGames(
      collection.kind,
      record.count,
      collection.gameCount,
    );
  }

  /// The game ids of [batch]'s stories the reader has seen.
  Set<String> seenIn(Collection collection, StoryBatch batch) {
    final record = state?[collection.slug];
    if (record == null) return const {};
    final shown = {for (final g in batch.games) g.id};
    return {
      for (final id in _idsOf(record, collection, batch))
        if (shown.contains(id)) id,
    };
  }

  /// The story [collection] opens on: its first story the reader has not
  /// seen (a book's newest games come first, so new games are where it
  /// opens), or its first when they have seen them all.
  int resumeIndex(Collection collection, StoryBatch batch) {
    final seen = seenIn(collection, batch);
    for (var i = 0; i < batch.games.length; i++) {
      if (!seen.contains(batch.games[i].id)) return i;
    }
    return 0;
  }

  /// The reader saw story [gameId] of [collection] (watched past half, or
  /// to its result).
  void markSeen(Collection collection, StoryBatch batch, String gameId) =>
      _count(collection, batch, add: gameId);

  /// [collection]'s stories are read: its record keeps only the stories it
  /// shows now, and says whether all of them are seen.
  void reconcile(Collection collection, StoryBatch batch) {
    if (state?[collection.slug] == null) return;
    _count(collection, batch);
  }

  void _count(Collection collection, StoryBatch batch, {String? add}) {
    final current = state?[collection.slug];
    final shown = [for (final g in batch.games) g.id];
    final seen = {
      if (current != null) ..._idsOf(current, collection, batch),
      ?add,
    };
    final ids = [
      for (final id in shown)
        if (seen.contains(id)) id,
    ];
    // Counted as of the stories in hand, whichever side is older: a batch
    // read before the catalog grew does not hold the new games, which stay
    // new; a batch read after the row was captured (a catalog re-read while
    // the viewer is open) holds them all, so the ring rests once they are
    // watched.
    final record = StorySeen(
      ids: List.unmodifiable(ids),
      count: batch.gameCount ?? collection.gameCount,
      full: ids.length == shown.length,
    );
    if (current != null &&
        current.legacyNext == null &&
        current.count == record.count &&
        current.full == record.full &&
        listEquals(current.ids, record.ids)) {
      return;
    }
    // Most recently touched last, so the cap drops the oldest.
    final records = LinkedHashMap<String, StorySeen>.of(state ?? const {})
      ..remove(collection.slug)
      ..[collection.slug] = record;
    while (records.length > capacity) {
      records.remove(records.keys.first);
    }
    state = records;
    unawaited(_save(records));
  }

  /// [record]'s seen ids; a 39.0.1 record's stories moved past, mapped onto
  /// [batch] as it is now: a book's games added since sit before them.
  static Iterable<String> _idsOf(
    StorySeen record,
    Collection collection,
    StoryBatch batch,
  ) {
    final next = record.legacyNext;
    if (next == null || record.ids.isNotEmpty) return record.ids;
    final added = collection.gameCount - record.count;
    final from = collection.kind == CollectionKind.book && added > 0
        ? added
        : 0;
    return batch.games.skip(from).take(next).map((g) => g.id);
  }

  Future<void> _save(Map<String, StorySeen> records) async {
    try {
      await _storage.write(
        jsonEncode({
          'v': _version,
          'c': {
            for (final MapEntry(:key, :value) in records.entries)
              key: value.toJson(),
          },
        }),
      );
    } catch (e) {
      debugPrint('[Stories] seen record not saved: $e');
    }
  }
}
