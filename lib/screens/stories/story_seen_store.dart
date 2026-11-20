import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the reader is in one collection's stories, as of its [signature]
/// (`storySignature`).
///
/// A collection whose signature moved on (new games) reads as never
/// watched: unseen, from its first story.
@immutable
class StorySeen {
  const StorySeen({
    required this.signature,
    required this.next,
    required this.seen,
  });

  final String signature;

  /// The first story the reader has not moved past: where the collection
  /// resumes.
  final int next;

  /// The reader watched a game story through (or reached the last story):
  /// the circle's ring goes quiet.
  final bool seen;

  Map<String, Object> toJson() => {'s': signature, 'n': next, 'v': seen};

  static StorySeen? fromJson(Object? json) {
    if (json is! Map) return null;
    final signature = json['s'];
    final next = json['n'];
    final seen = json['v'];
    if (signature is! String || next is! int || seen is! bool) return null;
    return StorySeen(signature: signature, next: next, seen: seen);
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

  Future<void> _load() async {
    // A map literal keeps insertion order: oldest first.
    final records = <String, StorySeen>{};
    try {
      final raw = await _storage.read();
      final json = raw == null ? null : jsonDecode(raw);
      if (json is Map) {
        for (final MapEntry(:key, :value) in json.entries) {
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

  /// Whether the circle of collection [id] reads as watched. With
  /// [signature] unknown the last record stands.
  bool isSeen(String id, String? signature) {
    final record = state?[id];
    if (record == null || !record.seen) return false;
    return signature == null || record.signature == signature;
  }

  /// The story a collection of [count] stories opens on: the first one the
  /// reader has not moved past, or the first when they had seen them all.
  int resumeIndex(String id, String signature, int count) {
    final record = state?[id];
    if (record == null || record.signature != signature) return 0;
    return record.next >= count || record.next < 0 ? 0 : record.next;
  }

  /// The reader moved on from story [from] of collection [id]. [game] says
  /// it was a game story: moving past one is what marks a collection seen.
  void advanced(
    String id,
    String signature, {
    required int from,
    required bool game,
  }) => _update(id, signature, next: from + 1, seen: game);

  /// The reader watched game story [index] a good part of the way: the
  /// collection reads as seen, and opens on that story again.
  void watched(String id, String signature, int index) =>
      _update(id, signature, next: index, seen: true);

  /// Story [index], the collection's last, is on screen: it reads as seen.
  void reachedLast(String id, String signature, int index) =>
      _update(id, signature, next: index, seen: true);

  void _update(
    String id,
    String signature, {
    required int next,
    required bool seen,
  }) {
    final current = state?[id];
    final same = current != null && current.signature == signature;
    final record = StorySeen(
      signature: signature,
      next: same && current.next > next ? current.next : next,
      seen: (same && current.seen) || seen,
    );
    if (same && current.next == record.next && current.seen == record.seen) {
      return;
    }
    // Most recently touched last, so the cap drops the oldest.
    final records = LinkedHashMap<String, StorySeen>.of(state ?? const {})
      ..remove(id)
      ..[id] = record;
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
          for (final MapEntry(:key, :value) in records.entries)
            key: value.toJson(),
        }),
      );
    } catch (e) {
      debugPrint('[Stories] seen record not saved: $e');
    }
  }
}
