import 'dart:async';

import 'package:chessever2/providers/app_resume_signal_provider.dart';
import 'package:chessever2/screens/streaks/data/streak_repository.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How long a fetched wall counts as fresh. The worker refreshes hourly, so
/// ten minutes never shows anything meaningfully old.
const Duration kStreakWallMaxAge = Duration(minutes: 10);

/// How long an automatic freshness check waits after the last read started,
/// so a surface that mounts again and again while offline does not hammer
/// the view. Pull-to-refresh and [StreakWallNotifier.refreshIfStale] ignore it.
const Duration kStreakWallRetryGap = Duration(minutes: 1);

/// How long a player card outlives its last listener, so back/forward
/// between the wall and a card is instant.
const Duration kPlayerStreaksKeepAlive = Duration(minutes: 5);

/// The whole wall, all three time classes (≈1.9k rows): first paint from the
/// SQLite cache, then refreshed from `player_streak_class_leaderboard`
/// (current_streak >= [kStreakWallMin]) when the cache is older than
/// [kStreakWallMaxAge] or empty. Rows are ranked per class (classical, rapid,
/// blitz; current streak desc, rating desc, FIDE id asc).
///
/// The provider lives for the whole session, so the age check is not a
/// one-off at build: every new listener (the wall, a My Space tile, the
/// profile's streak line through [playerLiveStreaksProvider]) and every
/// return to the foreground re-reads the view once the rows are older than
/// [kStreakWallMaxAge].
final streakWallProvider =
    AsyncNotifierProvider<StreakWallNotifier, List<StreakRow>>(
      StreakWallNotifier.new,
    );

class StreakWallNotifier extends AsyncNotifier<List<StreakRow>> {
  late StreakRepository _repository;
  late StreakWallCache _cache;

  /// When the rows on screen were fetched (from the network or, for cached
  /// rows, when that cache was written).
  DateTime? _fetchedAt;

  /// The one network read in flight; every caller shares it.
  Future<List<StreakRow>>? _fetching;
  bool _disposed = false;

  /// When the last network read started, whether it landed or not.
  DateTime? _attemptedAt;

  /// True once [build] has wired the repository and cache. Before that there
  /// is nothing to refresh with, so freshness checks stay off.
  bool _wired = false;

  /// A freshness check is waiting for its timer; later requests join it.
  bool _checkQueued = false;

  /// When the rows on screen were fetched; null before the first answer.
  DateTime? get fetchedAt => _fetchedAt;

  bool get _isStale {
    final at = _fetchedAt;
    return at == null || DateTime.now().difference(at) > kStreakWallMaxAge;
  }

  @override
  Future<List<StreakRow>> build() async {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _repository = ref.watch(streakRepositoryProvider);
    _cache = ref.watch(streakWallCacheProvider);
    _wired = true;

    ref.onAddListener(_scheduleFreshnessCheck);
    ref.listen<int>(
      appResumedSignalProvider,
      (_, __) => _scheduleFreshnessCheck(),
    );

    final cached = await _cache.read();
    if (cached != null && cached.rows.isNotEmpty) {
      _fetchedAt = cached.savedAt;
      if (_isStale) _scheduleFreshnessCheck();
      return cached.rows;
    }
    return _fetch();
  }

  /// Re-reads the view when the rows are older than [kStreakWallMaxAge], at
  /// most once per [kStreakWallRetryGap]. Runs on a timer because listeners
  /// arrive while widgets build, and state may only change after; requests
  /// made before it fires share it. Skipped while a build or read is in
  /// flight, since that one decides the rows.
  void _scheduleFreshnessCheck() {
    if (!_wired || _checkQueued) return;
    _checkQueued = true;
    Timer.run(() {
      _checkQueued = false;
      if (_disposed || _fetching != null || state.isLoading || !_isStale) {
        return;
      }
      final tried = _attemptedAt;
      if (tried != null &&
          DateTime.now().difference(tried) < kStreakWallRetryGap) {
        return;
      }
      unawaited(refresh());
    });
  }

  /// Pull-to-refresh: re-reads the view, keeps the old rows on failure.
  /// Concurrent calls share one read. Never throws; with nothing to keep,
  /// a failure lands in the provider as an error the screen can retry from.
  Future<void> refresh() async {
    final previous = state.valueOrNull;
    if (previous == null && !state.isLoading) {
      state = const AsyncLoading<List<StreakRow>>();
    }
    try {
      final rows = await _fetch();
      if (_disposed) return;
      state = AsyncData(rows);
    } catch (e, st) {
      if (_disposed) return;
      debugPrint('[Streaks] wall refresh failed: $e');
      final current = state.valueOrNull;
      if (current == null) state = AsyncError(e, st);
    }
  }

  /// Re-reads only when what is on screen is older than [maxAge] (or missing).
  /// For screens that open onto a wall the app has held for a while.
  Future<void> refreshIfStale({Duration maxAge = kStreakWallMaxAge}) {
    final at = _fetchedAt;
    final fresh =
        at != null && state.hasValue && DateTime.now().difference(at) <= maxAge;
    return fresh ? Future<void>.value() : refresh();
  }

  Future<List<StreakRow>> _fetch() {
    return _fetching ??= _fetchAndStore().whenComplete(() => _fetching = null);
  }

  Future<List<StreakRow>> _fetchAndStore() async {
    _attemptedAt = DateTime.now();
    final rows = await _repository.fetchWall();
    _fetchedAt = DateTime.now();
    unawaited(_cache.write(rows));
    return rows;
  }
}

/// Hands a derived provider's new listeners to the wall's freshness check.
/// Derived providers are never disposed, so the wall itself only hears about
/// their first listener; without this, a surface that reads the wall only
/// through one (the profile's streak line) would keep the rows it first saw.
void _checkWallOnListen(Ref<Object?> ref) {
  ref.onAddListener(
    ref.read(streakWallProvider.notifier)._scheduleFreshnessCheck,
  );
}

/// Every row of one time class, strongest run first (current streak desc,
/// then rating desc, then FIDE id), with no rating floor. Only the wall's
/// explicit filters read this ([StreakWallFilter.looksPastFloor]).
final streakAllClassRowsProvider =
    Provider.family<List<StreakRow>, StreakTimeClass>((ref, tc) {
      final rows = ref.watch(streakWallProvider).valueOrNull ?? const [];
      _checkWallOnListen(ref);
      return rows.where((r) => r.timeClass == tc).toList(growable: false);
    });

/// Rows of one time class as every streak list shows them by default: only
/// players rated [kStreakFeaturedMinRating]+ in that class, in wall order.
final streakClassRowsProvider =
    Provider.family<List<StreakRow>, StreakTimeClass>((ref, tc) {
      return ref
          .watch(streakAllClassRowsProvider(tc))
          .where(passesStreakFloor)
          .toList(growable: false);
    });

/// Players on each class's wall as shown by default (the switch labels:
/// "Classical 1,105"), so the count matches the list under it.
final streakClassCountsProvider = Provider<Map<StreakTimeClass, int>>((ref) {
  final rows = ref.watch(streakWallProvider).valueOrNull ?? const [];
  _checkWallOnListen(ref);
  final counts = {for (final tc in StreakTimeClass.values) tc: 0};
  for (final r in rows) {
    if (!passesStreakFloor(r)) continue;
    counts[r.timeClass] = counts[r.timeClass]! + 1;
  }
  return counts;
});

/// Wall screen state: the selected class and the filter.
final streakSelectedClassProvider = StateProvider<StreakTimeClass>(
  (ref) => StreakTimeClass.standard,
);
final streakWallFilterProvider = StateProvider<StreakWallFilter>(
  (ref) => const StreakWallFilter(),
);

/// The visible wall: selected class + filter applied, ranked. By default only
/// the 2650+ players; a filter that looks for someone searches everyone.
final streakVisibleRowsProvider = Provider<List<StreakRow>>((ref) {
  final tc = ref.watch(streakSelectedClassProvider);
  final filter = ref.watch(streakWallFilterProvider);
  _checkWallOnListen(ref);
  final base =
      filter.looksPastFloor
          ? streakAllClassRowsProvider(tc)
          : streakClassRowsProvider(tc);
  return ref.watch(base).where(filter.matches).toList(growable: false);
});

/// A player's live runs in every class, strongest first. Empty when the
/// player is not on any wall. Cheap: derived from [streakWallProvider], and
/// each new listener (a profile line, a My Space tile) re-checks its age.
final playerLiveStreaksProvider = Provider.family<List<StreakRow>, int>((
  ref,
  fideId,
) {
  final rows = ref.watch(streakWallProvider).valueOrNull ?? const [];
  _checkWallOnListen(ref);
  final mine = rows.where((r) => r.fideId == fideId).toList()
    ..sort((a, b) => b.currentStreak.compareTo(a.currentStreak));
  return mine;
});

/// One player's streak card (profile + all classes with their games).
/// Null when the player has no streak profile (or the project has no streak
/// tables). Kept for [kPlayerStreaksKeepAlive] after the last listener leaves;
/// a failed read is not kept, so reopening the card retries.
final playerStreaksProvider = FutureProvider.autoDispose
    .family<PlayerStreaks?, int>((ref, fideId) async {
      final link = ref.keepAlive();
      Timer? release;
      ref.onCancel(() {
        release?.cancel();
        release = Timer(kPlayerStreaksKeepAlive, link.close);
      });
      ref.onResume(() {
        release?.cancel();
        release = null;
      });
      ref.onDispose(() => release?.cancel());

      try {
        return await ref.watch(streakRepositoryProvider).fetchPlayer(fideId);
      } catch (_) {
        link.close();
        rethrow;
      }
    });
