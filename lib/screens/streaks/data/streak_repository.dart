import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads the streak wall and one player's streak card from Supabase.
///
/// Read-only: every call is a plain `select` on world-readable relations
/// (`player_streak_class_leaderboard`, `player_streak`, `player_streak_class`).
/// The test-flavour project has none of them; a missing relation answers with
/// an empty wall / no player, quietly, and is not asked again this session.
final streakRepositoryProvider = Provider<StreakRepository>(
  (ref) => StreakRepository(),
);

/// Where the wall paints from before the network answers.
final streakWallCacheProvider = Provider<StreakWallCache>(
  (ref) => const SqliteStreakWallCache(),
);

/// Rows asked for per page (PostgREST's usual cap). Only a request size: the
/// server may hand out fewer, so the exact count, not a short page, ends a read.
const int kStreakWallPageSize = 1000;

/// One page of the wall as the server sent it.
@immutable
class StreakWallPage {
  const StreakWallPage(this.rows, [this.total]);

  final List<Map<String, dynamic>> rows;

  /// Exact row count of the whole wall (`count=exact`). A page without one
  /// cannot prove the wall complete, so the read refuses it.
  final int? total;
}

typedef StreakWallPageReader =
    Future<StreakWallPage> Function(int offset, int limit);

/// No attempt produced a whole, consistent wall: the hourly refresh was
/// rewriting it mid-read, or the server gave no exact count. Callers keep
/// what they already show.
class StreakWallInconsistent implements Exception {
  const StreakWallInconsistent();

  @override
  String toString() => 'The streak wall could not be read completely.';
}

class StreakRepository {
  StreakRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  static const _wallView = 'player_streak_class_leaderboard';
  static const _profileTable = 'player_streak';
  static const _classTable = 'player_streak_class';
  static const _timeout = Duration(seconds: 15);

  bool _wallMissing = false;
  bool _playerMissing = false;

  /// Every live run of [kStreakWallMin]+ in all three classes (≈1.9k rows),
  /// ranked per class. Empty when the view does not exist.
  Future<List<StreakRow>> fetchWall() async {
    if (_wallMissing) return const [];
    try {
      return await loadWall(_readWallPage);
    } on PostgrestException catch (e) {
      if (!isMissingRelation(e)) rethrow;
      _wallMissing = true;
      debugPrint('[Streaks] wall view missing, showing none: ${e.message}');
      return const [];
    }
  }

  Future<StreakWallPage> _readWallPage(int offset, int limit) async {
    final res = await _client
        .from(_wallView)
        .select(StreakRow.selectColumns)
        .gte('current_streak', kStreakWallMin)
        .order('time_class', ascending: true)
        .order('current_streak', ascending: false)
        .order('rating', ascending: false, nullsFirst: false)
        .order('fide_id', ascending: true)
        .range(offset, offset + limit - 1)
        .count(CountOption.exact)
        .timeout(_timeout);
    return StreakWallPage(res.data, res.count);
  }

  /// One player's card: profile plus every class with its latest games.
  /// Null when the player has no streak profile or the tables do not exist.
  Future<PlayerStreaks?> fetchPlayer(int fideId) async {
    if (_playerMissing || fideId <= 0) return null;
    try {
      final profileRead = _client
          .from(_profileTable)
          .select(PlayerStreaks.profileColumns)
          .eq('fide_id', fideId)
          .maybeSingle()
          .timeout(_timeout);
      final classesRead = _client
          .from(_classTable)
          .select(StreakClassRun.selectColumns)
          .eq('fide_id', fideId)
          .order('time_class', ascending: true)
          .timeout(_timeout);
      // Both in flight at once; Future.wait also owns the second error so a
      // failure on both reads never leaks an unhandled one.
      final results = await Future.wait<Object?>([profileRead, classesRead]);
      final profile = results[0] as Map<String, dynamic>?;
      final classes = results[1] as List<Map<String, dynamic>>;
      if (profile == null) return null;
      return PlayerStreaks.fromJson(profile, classes);
    } on PostgrestException catch (e) {
      if (!isMissingRelation(e)) rethrow;
      _playerMissing = true;
      debugPrint('[Streaks] player tables missing: ${e.message}');
      return null;
    }
  }

  /// "relation does not exist" (Postgres) or "not in the schema cache"
  /// (PostgREST): the project simply has no streaks.
  static bool isMissingRelation(PostgrestException e) =>
      e.code == '42P01' ||
      e.code == 'PGRST205' ||
      (e.message.contains('player_streak') &&
          e.message.contains('does not exist'));

  /// Reads the whole wall a page at a time, like the site's `loadWall`.
  ///
  /// Pages advance by the rows actually received and the read ends only at
  /// the exact count, so a server cap below [pageSize] cannot drop the tail.
  /// A snapshot that cannot be proven whole is read again from the top, at
  /// most [attempts] times, then refused: a missing count, a count that
  /// changes between pages, a read that runs short of or past its count, or
  /// a (player, class) seen twice (a row slid across a page boundary while
  /// the refresh rewrote the wall, so some other row was skipped). Rows that
  /// do not parse are dropped but still counted. The result is ranked with
  /// [sortStreakWall].
  static Future<List<StreakRow>> loadWall(
    StreakWallPageReader read, {
    int pageSize = kStreakWallPageSize,
    int attempts = 3,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      final rows = await _readSnapshot(read, pageSize);
      if (rows != null) return sortStreakWall(rows);
    }
    throw const StreakWallInconsistent();
  }

  /// Null when the snapshot moved while it was being read.
  static Future<List<StreakRow>?> _readSnapshot(
    StreakWallPageReader read,
    int pageSize,
  ) async {
    final byKey = <String, StreakRow>{};
    var offset = 0;
    var dropped = 0;
    int? first;
    for (var page = 0; page < 100; page++) {
      final batch = await read(offset, pageSize);
      final count = batch.total;
      // Without the exact count a capped page and the last page look alike.
      if (count == null || count < 0) return null;
      final total = first ??= count;
      if (count != total) return null;
      for (final raw in batch.rows) {
        final row = StreakRow.fromJson(raw);
        if (row == null) {
          dropped++;
          continue;
        }
        final key = '${row.fideId}:${row.timeClass.wire}';
        // Seen twice: the ranking moved under the read, and whoever it
        // pushed across the page boundary the other way was never read.
        if (byKey.containsKey(key)) return null;
        byKey[key] = row;
      }
      offset += batch.rows.length;
      // The count is the only end: a short page just means the server
      // hands out fewer rows per page than asked.
      if (offset == total) {
        return byKey.length + dropped == total ? byKey.values.toList() : null;
      }
      if (offset > total || batch.rows.isEmpty) return null;
    }
    return null;
  }
}

/// Class order (classical, rapid, blitz), then the wall's own ranking:
/// current streak desc, rating desc (unrated last), FIDE id asc.
List<StreakRow> sortStreakWall(Iterable<StreakRow> rows) {
  final out = rows.toList();
  out.sort(compareStreakRows);
  return out;
}

int compareStreakRows(StreakRow a, StreakRow b) {
  final tc = a.timeClass.index.compareTo(b.timeClass.index);
  if (tc != 0) return tc;
  final cur = b.currentStreak.compareTo(a.currentStreak);
  if (cur != 0) return cur;
  final ar = a.rating;
  final br = b.rating;
  if (ar != br) {
    if (ar == null) return 1;
    if (br == null) return -1;
    return br.compareTo(ar);
  }
  return a.fideId.compareTo(b.fideId);
}

// ------------------------------------------------------------------- cache --

/// A cached wall and when it was fetched.
@immutable
class StreakWallSnapshot {
  const StreakWallSnapshot(this.rows, this.savedAt);

  final List<StreakRow> rows;
  final DateTime savedAt;
}

abstract class StreakWallCache {
  const StreakWallCache();

  /// Never throws; null when there is nothing usable.
  Future<StreakWallSnapshot?> read();

  /// Never throws.
  Future<void> write(List<StreakRow> rows);
}

/// The wall in SQLite under one user-agnostic key. Stored column-wise
/// (one header, then value arrays) so ~2k rows stay well under a megabyte,
/// and decoded through [StreakRow.fromJson] so a cached row is validated
/// exactly like a fresh one.
class SqliteStreakWallCache extends StreakWallCache {
  const SqliteStreakWallCache();

  static const cacheKey = 'streak_wall_v1';

  @override
  Future<StreakWallSnapshot?> read() async {
    try {
      final entry = await AppDatabase.instance.getCache(key: cacheKey);
      if (entry == null) return null;
      final rows = await compute(decodeStreakWallCache, entry.value);
      return StreakWallSnapshot(rows, entry.cachedAt);
    } catch (e) {
      debugPrint('[Streaks] wall cache read failed: $e');
      return null;
    }
  }

  @override
  Future<void> write(List<StreakRow> rows) async {
    try {
      final value = await compute(encodeStreakWallCache, rows);
      await AppDatabase.instance.setCache(key: cacheKey, value: value);
    } catch (e) {
      debugPrint('[Streaks] wall cache write failed: $e');
    }
  }
}

final List<String> _cacheColumns = StreakRow.selectColumns.split(',');

/// Rows → `{"v":1,"cols":[...],"rows":[[...],...]}`.
String encodeStreakWallCache(List<StreakRow> rows) {
  return jsonEncode({
    'v': 1,
    'cols': _cacheColumns,
    'rows': [
      for (final r in rows) [for (final c in _cacheColumns) _wireValue(r, c)],
    ],
  });
}

/// The inverse of [encodeStreakWallCache]. Anything unreadable → no rows.
List<StreakRow> decodeStreakWallCache(String raw) {
  try {
    final doc = jsonDecode(raw);
    if (doc is! Map || doc['v'] != 1) return const [];
    final cols = doc['cols'];
    final list = doc['rows'];
    if (cols is! List || list is! List) return const [];
    final names = cols.map((c) => c.toString()).toList(growable: false);
    final out = <StreakRow>[];
    for (final values in list) {
      if (values is! List || values.length != names.length) continue;
      final row = StreakRow.fromJson({
        for (var i = 0; i < names.length; i++) names[i]: values[i],
      });
      if (row != null) out.add(row);
    }
    return sortStreakWall(out);
  } catch (_) {
    return const [];
  }
}

Object? _wireValue(StreakRow r, String column) => switch (column) {
  'fide_id' => r.fideId,
  'time_class' => r.timeClass.wire,
  'name' => r.name,
  'title' => r.title,
  'fed' => r.fed,
  'sex' => r.sex,
  'rating' => r.rating,
  'birth_year' => r.birthYear,
  'age' => r.age,
  'current_streak' => r.currentStreak,
  'best_streak' => r.bestStreak,
  'best_streak_at' => r.bestStreakAt?.toIso8601String(),
  'wins' => r.wins,
  'losses' => r.losses,
  'anchor_loss_game_day' => r.anchorLossGameDay,
  'streak_start_game_day' => r.streakStartGameDay,
  'last_game_day' => r.lastGameDay,
  'last_result' => r.lastResult,
  'run_opp_avg' => r.runOppAvg,
  'run_opp_best' => r.runOppBest,
  'run_opp_best_name' => r.runOppBestName,
  'run_opp_best_title' => r.runOppBestTitle,
  'tracked_current' => r.trackedCurrent,
  'tracked_top500' => r.trackedTop500,
  'updated_at' => r.updatedAt?.toIso8601String(),
  _ => null,
};
