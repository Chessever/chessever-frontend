import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the reader has seen of one circle: the games whose stories they
/// watched, and whether they were caught up with it as it stood
/// ([signature]).
///
/// The device remembers watched games across visits so a collection can
/// feature something the reader hasn't seen yet.
@immutable
class StorySeen {
  const StorySeen({
    this.ids = const [],
    required this.signature,
    required this.caught,
  });

  /// The most recently watched game ids, including earlier visits.
  final List<String> ids;

  /// The circle's [storySignature] when the record was last counted. A
  /// record from before signatures (39.1.0 and older) holds `legacy:<n>`,
  /// the collection's game count then.
  final String signature;

  /// Every story the circle showed under [signature] was seen.
  final bool caught;

  /// Whether this record speaks for [collection] as it stands now.
  bool matches(Collection collection) {
    if (signature == storySignature(collection)) return true;
    if (!signature.startsWith(_legacy)) return false;
    return int.tryParse(signature.substring(_legacy.length)) ==
        collection.gameCount;
  }

  static const String _legacy = 'legacy:';

  Map<String, Object> toJson() => {'i': ids, 's': signature, 'k': caught};

  static StorySeen? fromJson(Object? json) {
    if (json is! Map) return null;
    final ids = json['i'];
    final signature = json['s'];
    final caught = json['k'];
    if (ids is List && signature is String && caught is bool) {
      return StorySeen(
        ids: List.unmodifiable(ids.whereType<String>()),
        signature: signature,
        caught: caught,
      );
    }
    return _fromLegacy(json);
  }

  /// 39.1.0's record (`{i, c, f}`: ids, game count, every story seen) and
  /// 39.0.1's (`{s: "count:version", n, v}`): a ring the reader saw go
  /// quiet stays quiet while the collection holds the same games.
  static StorySeen? _fromLegacy(Map<dynamic, dynamic> json) {
    final count = json['c'];
    final full = json['f'];
    if (count is int && full is bool) {
      final ids = json['i'];
      return StorySeen(
        ids: ids is List
            ? List.unmodifiable(ids.whereType<String>())
            : const [],
        signature: '$_legacy$count',
        caught: full,
      );
    }
    final signature = json['s'];
    final seen = json['v'];
    if (signature is String && seen is bool) {
      final games = int.tryParse(signature.split(':').first) ?? 0;
      return StorySeen(signature: '$_legacy$games', caught: seen);
    }
    return null;
  }
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

/// What the reader has watched, per circle slug. Null until the device's
/// record is read (the row waits for it, so no ring flips on launch).
final storySeenProvider =
    StateNotifierProvider<StorySeenNotifier, Map<String, StorySeen>?>(
      (ref) => StorySeenNotifier(ref.watch(storySeenStorageProvider)),
    );

class StorySeenNotifier extends StateNotifier<Map<String, StorySeen>?> {
  StorySeenNotifier(this._storage) : super(null) {
    unawaited(_load());
  }

  final StorySeenStorage _storage;

  /// The page each circle was last on ([StoryFrame.id]), by slug: a circle
  /// left part way through a story reopens on that position. Kept beside
  /// the records, never in [state], so moving through a story never
  /// rebuilds the row.
  final Map<String, String> _at = {};

  /// Circles remembered at most; the longest untouched go first.
  static const int capacity = 200;
  static const int gamesPerCollection = 64;

  /// The document's format: `{"v": 3, "c": {slug: record}, "a": {slug:
  /// page}}`, `a` the page each circle was left on ([markAt]). Older
  /// documents (v2, and 39.0.1's bare map) are read and rewritten on the
  /// next change.
  static const int _version = 3;

  Future<void> _load() async {
    // A map literal keeps insertion order: oldest first.
    final records = <String, StorySeen>{};
    final at = <String, String>{};
    try {
      final raw = await _storage.read();
      final json = raw == null ? null : jsonDecode(raw);
      final entries = json is Map && json['v'] is int ? json['c'] : json;
      if (entries is Map) {
        for (final MapEntry(:key, :value) in entries.entries) {
          final record = StorySeen.fromJson(value);
          if (key is String && record != null) records[key] = record;
        }
      }
      final places = json is Map ? json['a'] : null;
      if (places is Map) {
        for (final MapEntry(:key, :value) in places.entries) {
          if (key is String && value is String) at[key] = value;
        }
      }
    } catch (e) {
      debugPrint('[Stories] seen record unreadable: $e');
    }
    if (!mounted) return;
    // A mark made before the record was read wins over the read.
    final marked = Map.of(_at);
    _at
      ..clear()
      ..addAll(at)
      ..addAll(marked);
    state = {...records, ...?state};
  }

  /// Whether [collection]'s circle reads as watched: the reader caught up
  /// with it, and nothing new arrived since.
  bool isSeen(Collection collection) {
    final record = state?[collection.slug];
    return record != null && record.caught && record.matches(collection);
  }

  Set<String> watchedGames(String slug) => {...?state?[slug]?.ids};

  /// Resume an unfinished game in a stable collection when it is still in
  /// the candidate pool. New content gets the first chance after an update.
  String? unfinishedGame(Collection collection) {
    final at = _at[collection.slug];
    final separator = at?.lastIndexOf('#') ?? -1;
    if (at == null || separator < 0) return null;
    final last = at.substring(0, separator);
    final current = state?[collection.slug];
    if (current != null &&
        (!current.matches(collection) || current.ids.contains(last))) {
      return null;
    }
    return last;
  }

  /// The game ids of [batch]'s stories the reader has seen.
  Set<String> seenIn(Collection collection, StoryBatch batch) {
    final record = state?[collection.slug];
    if (record == null) return const {};
    final shown = {for (final g in batch.games) g.id};
    return {
      for (final id in record.ids)
        if (shown.contains(id)) id,
    };
  }

  /// The page [collection] opens on: the position the reader left it on
  /// part way through a story ([markAt]); else the first page of its first
  /// story the reader has not seen (its latest game leads, so a new game is
  /// where it opens), or its first when they have seen them all.
  int resumeIndex(Collection collection, StoryBatch batch) {
    final seen = seenIn(collection, batch);
    // Left part way through a story it has not finished: that position.
    final at = _at[collection.slug];
    if (at != null) {
      final index = batch.frames.indexWhere((f) => f.id == at);
      if (index >= 0 && !seen.contains(batch.frames[index].game.id)) {
        return index;
      }
    }
    for (var s = 0; s < batch.games.length; s++) {
      if (!seen.contains(batch.games[s].id)) {
        final frame = batch.firstFrameOf(s);
        return frame < 0 ? 0 : frame;
      }
    }
    return 0;
  }

  /// The reader is on page [frameId] ([StoryFrame.id]) of [collection]:
  /// reopened before that story is seen, the circle opens here.
  void markAt(Collection collection, String frameId) {
    if (_at[collection.slug] == frameId) return;
    // Most recently touched last, so the cap drops the oldest.
    _at
      ..remove(collection.slug)
      ..[collection.slug] = frameId;
    while (_at.length > capacity) {
      _at.remove(_at.keys.first);
    }
    // Before the device's record is read, a write would drop it: the place
    // is kept here and saved with the next change after the read.
    final records = state;
    if (records != null) unawaited(_save(records));
  }

  /// The reader saw story [gameId] of [collection].
  void markSeen(Collection collection, StoryBatch batch, String gameId) =>
      _count(collection, batch, add: gameId);

  /// [collection]'s stories are read: its record keeps to the stories it
  /// shows now.
  void reconcile(Collection collection, StoryBatch batch) {
    if (state?[collection.slug] == null) return;
    _count(collection, batch);
  }

  void _count(Collection collection, StoryBatch batch, {String? add}) {
    final current = state?[collection.slug];
    final shown = [for (final g in batch.games) g.id];
    // Counted as of the stories in hand: a batch read before the catalog
    // grew does not hold the new games, which stay new.
    final signature = batch.signature ?? storySignature(collection);
    final seen = {...?current?.ids};
    if (add != null) {
      seen
        ..remove(add)
        ..add(add);
    }
    final same = current != null && current.signature == signature;
    final caught =
        (shown.isNotEmpty && shown.every(seen.contains)) ||
        (!batch.featuredGame && same && current.caught);
    final ids = seen.skip(
      seen.length > gamesPerCollection ? seen.length - gamesPerCollection : 0,
    );
    final record = StorySeen(
      ids: List.unmodifiable(ids),
      signature: signature,
      caught: caught,
    );
    if (current != null &&
        current.signature == record.signature &&
        current.caught == record.caught &&
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

  Future<void> _save(Map<String, StorySeen> records) async {
    try {
      await _storage.write(
        jsonEncode({
          'v': _version,
          'c': {
            for (final MapEntry(:key, :value) in records.entries)
              key: value.toJson(),
          },
          if (_at.isNotEmpty) 'a': _at,
        }),
      );
    } catch (e) {
      debugPrint('[Stories] seen record not saved: $e');
    }
  }
}
