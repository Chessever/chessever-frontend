import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle_model.dart';
import 'package:flutter/foundation.dart';

/// A puzzle as cached, with when it was fetched and when the Feed last
/// served it (null while the viewer has not been shown it).
@immutable
class CachedPuzzle {
  const CachedPuzzle(this.puzzle, this.fetchedAt, {this.servedAt});

  final FeedPuzzle puzzle;
  final DateTime fetchedAt;
  final DateTime? servedAt;

  /// This puzzle, served at [at].
  CachedPuzzle servedOn(DateTime at) =>
      CachedPuzzle(puzzle, fetchedAt, servedAt: at);

  Map<String, Object?> toJson() => {
    'at': fetchedAt.millisecondsSinceEpoch,
    if (servedAt case final served?) 'served': served.millisecondsSinceEpoch,
    'puzzle': puzzle.toJson(),
  };

  static CachedPuzzle? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'];
    final served = json['served'];
    final puzzle = FeedPuzzle.fromJson(json['puzzle']);
    if (at is! int || puzzle == null) return null;
    return CachedPuzzle(
      puzzle,
      DateTime.fromMillisecondsSinceEpoch(at),
      servedAt: served is int
          ? DateTime.fromMillisecondsSinceEpoch(served)
          : null,
    );
  }
}

/// The viewer's Feed puzzle strength: an Elo-style estimate that moves with
/// each finished puzzle, so the next puzzles are asked for around what they
/// have recently been solving.
@immutable
class FeedPuzzleRating {
  const FeedPuzzleRating(this.value, {this.finished = 0});

  /// Where a viewer with no finished puzzles starts.
  static const FeedPuzzleRating initial = FeedPuzzleRating(1200);

  static const double floor = 600;
  static const double ceiling = 2800;

  /// Half the width of the rating window puzzles are asked for in.
  static const int bandHalfWidth = 200;

  /// The window's centre is rounded to this step, so nearby viewers share
  /// the service's cached pages.
  static const int bandStep = 50;

  final double value;

  /// Puzzles finished so far; the first few move the rating faster.
  final int finished;

  /// After a puzzle rated [puzzleRating] (the viewer's own rating when
  /// unknown) ended with [score]: 1 solved unaided, 0.5 solved after a wrong
  /// move or a hint, 0 answer shown.
  FeedPuzzleRating after({int? puzzleRating, required double score}) {
    final opponent = puzzleRating?.toDouble() ?? value;
    final expected = 1 / (1 + math.pow(10, (opponent - value) / 400));
    final k = finished < 10 ? 80.0 : 40.0;
    final next = (value + k * (score - expected)).clamp(floor, ceiling);
    return FeedPuzzleRating(next.toDouble(), finished: finished + 1);
  }

  /// The rating window to ask the service for.
  ({int min, int max}) get band {
    final centre = (value / bandStep).round() * bandStep;
    return (min: centre - bandHalfWidth, max: centre + bandHalfWidth);
  }

  Map<String, Object?> toJson() => {'value': value, 'finished': finished};

  static FeedPuzzleRating? fromJson(Object? json) {
    if (json is! Map) return null;
    final value = json['value'];
    final finished = json['finished'];
    if (value is! num || !value.isFinite) return null;
    return FeedPuzzleRating(
      value.toDouble().clamp(floor, ceiling),
      finished: finished is int && finished > 0 ? finished : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FeedPuzzleRating &&
      other.value == value &&
      other.finished == finished;

  @override
  int get hashCode => Object.hash(value, finished);

  @override
  String toString() => 'FeedPuzzleRating(${value.round()}, $finished)';
}

/// Local persistence for Feed puzzles: a small pool of fetched ones, the ids
/// the viewer finished (solved or had shown), and their puzzle rating.
abstract class FeedPuzzleStore {
  Future<List<CachedPuzzle>> readPool();
  Future<void> writePool(List<CachedPuzzle> pool);
  Future<Set<String>> readDone();
  Future<void> addDone(String id);
  Future<FeedPuzzleRating?> readRating();
  Future<void> writeRating(FeedPuzzleRating rating);
}

/// [FeedPuzzleStore] on the app's SQLite cache table
/// ([AppDatabase.setCache] / [AppDatabase.getCache]). Device-local: nothing
/// here belongs to the viewer's account.
///
/// Earlier versions also kept Lichess's daily puzzle under
/// `feed_puzzles_daily_v1`; that entry is simply no longer read.
class SqliteFeedPuzzleStore implements FeedPuzzleStore {
  SqliteFeedPuzzleStore(this._db);

  final AppDatabase _db;

  static const String _poolKey = 'feed_puzzles_pool_v1';
  static const String _doneKey = 'feed_puzzles_done_v1';
  static const String _ratingKey = 'feed_puzzles_rating_v1';

  /// Finished ids kept; the oldest fall off first.
  static const int _doneCap = 1000;

  Future<void> _doneWrites = Future<void>.value();

  @override
  Future<List<CachedPuzzle>> readPool() async {
    final json = await _readJson(_poolKey);
    if (json is! List) return const [];
    return [
      for (final entry in json)
        if (CachedPuzzle.fromJson(entry) case final cached?) cached,
    ];
  }

  @override
  Future<void> writePool(List<CachedPuzzle> pool) =>
      _writeJson(_poolKey, [for (final p in pool) p.toJson()]);

  @override
  Future<Set<String>> readDone() async => (await _readDoneList()).toSet();

  @override
  Future<void> addDone(String id) {
    // Read-modify-write, one at a time, so two quick finishes both land.
    final write = _doneWrites.then((_) async {
      final ids = await _readDoneList();
      if (ids.contains(id)) return;
      ids.add(id);
      final kept = ids.length > _doneCap
          ? ids.sublist(ids.length - _doneCap)
          : ids;
      await _writeJson(_doneKey, kept);
    });
    _doneWrites = write.then<void>((_) {}, onError: (Object _) {});
    return write;
  }

  @override
  Future<FeedPuzzleRating?> readRating() async =>
      FeedPuzzleRating.fromJson(await _readJson(_ratingKey));

  @override
  Future<void> writeRating(FeedPuzzleRating rating) =>
      _writeJson(_ratingKey, rating.toJson());

  Future<List<String>> _readDoneList() async {
    final json = await _readJson(_doneKey);
    if (json is! List) return <String>[];
    return json.whereType<String>().toList();
  }

  Future<Object?> _readJson(String key) async {
    try {
      final entry = await _db.getCache(key: key);
      if (entry == null) return null;
      return jsonDecode(entry.value);
    } catch (error) {
      debugPrint('[FeedPuzzles] cache read $key failed: $error');
      return null;
    }
  }

  Future<void> _writeJson(String key, Object value) async {
    try {
      await _db.setCache(key: key, value: jsonEncode(value));
    } catch (error) {
      debugPrint('[FeedPuzzles] cache write $key failed: $error');
    }
  }
}

/// In-memory [FeedPuzzleStore] (tests, previews).
class MemoryFeedPuzzleStore implements FeedPuzzleStore {
  MemoryFeedPuzzleStore({
    List<CachedPuzzle> pool = const [],
    Set<String> done = const {},
    this.rating,
  }) : _pool = List.of(pool),
       done = {...done};

  List<CachedPuzzle> _pool;
  final Set<String> done;
  FeedPuzzleRating? rating;

  List<CachedPuzzle> get pool => List.unmodifiable(_pool);

  @override
  Future<List<CachedPuzzle>> readPool() async => List.of(_pool);

  @override
  Future<void> writePool(List<CachedPuzzle> pool) async =>
      _pool = List.of(pool);

  @override
  Future<Set<String>> readDone() async => {...done};

  @override
  Future<void> addDone(String id) async => done.add(id);

  @override
  Future<FeedPuzzleRating?> readRating() async => rating;

  @override
  Future<void> writeRating(FeedPuzzleRating rating) async =>
      this.rating = rating;
}
