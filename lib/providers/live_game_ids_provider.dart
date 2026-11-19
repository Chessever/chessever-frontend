import 'dart:async';

import 'package:chessever2/providers/app_resume_signal_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The games in play right now, by the server's one rule
/// (`get_live_game_ids`: a game in a fresh live round, with a move, not
/// finished, not a mirror), for the "See N live" capsules over game lists.
///
/// One family per scope, each an id set that is null until the server's
/// first answer (the capsule reads "See live", never a guessed number) and
/// stays null on a backend without the function. After that it keeps its
/// last good answer through errors and refetches:
///
/// * on open;
/// * whenever the live rounds change ([liveRoundsIdProvider]);
/// * on app resume ([appResumedSignalProvider]);
/// * on a timer while the app is in the foreground and the list is
///   [LiveGameIdsNotifier.visible]: an event every 5 s (Combined, 12 s), a
///   player or country list every 30 s;
/// * on [LiveGameIdsNotifier.refresh] (pull to refresh, back from a board).
///
/// A list counts the ids it shows ([liveIdsAmong], [liveCountAmong]) and
/// lifts the same ids in Live first, so the label and the lift agree.
typedef LiveGameIds = Set<String>?;

/// An event's tours: the selected one, Combined's categories, sibling
/// stages. Equal for the same tours in any order.
@immutable
class EventLiveGamesScope {
  /// [poll] defaults to [eventPoll] for one tour and [combinedPoll] for
  /// several, the cadences the event's own status polls run at.
  factory EventLiveGamesScope(Iterable<String> tourIds, {Duration? poll}) {
    final ids = _sortedIds(tourIds);
    return EventLiveGamesScope._(
      ids,
      poll ?? (ids.length > 1 ? combinedPoll : eventPoll),
    );
  }

  const EventLiveGamesScope._(this.tourIds, this.poll);

  /// One event on screen.
  static const Duration eventPoll = Duration(seconds: 5);

  /// Combined: every category of the event at once.
  static const Duration combinedPoll = Duration(seconds: 12);

  /// Sorted, distinct, never blank.
  final List<String> tourIds;
  final Duration poll;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventLiveGamesScope &&
          listEquals(other.tourIds, tourIds) &&
          other.poll == poll;

  @override
  int get hashCode => Object.hash(Object.hashAll(tourIds), poll);

  @override
  String toString() => 'EventLiveGamesScope($tourIds, $poll)';
}

/// The reader's favorite players under the Favorites games list's filter.
@immutable
class FavoritesLiveGamesScope {
  factory FavoritesLiveGamesScope({
    required Iterable<String> fideIds,
    GameFilter? filter,
    Duration poll = listPoll,
  }) => FavoritesLiveGamesScope._(
    _sortedIds(fideIds),
    _countedFilter(filter),
    poll,
  );

  const FavoritesLiveGamesScope._(this.fideIds, this.filter, this.poll);

  /// A player or country list's cadence.
  static const Duration listPoll = Duration(seconds: 30);

  /// Sorted, distinct, never blank.
  final List<String> fideIds;

  /// The list's filter, its sort order dropped (it changes no count).
  final GameFilter? filter;
  final Duration poll;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoritesLiveGamesScope &&
          listEquals(other.fideIds, fideIds) &&
          other.filter == filter &&
          other.poll == poll;

  @override
  int get hashCode => Object.hash(Object.hashAll(fideIds), filter, poll);

  @override
  String toString() => 'FavoritesLiveGamesScope($fideIds, $filter, $poll)';
}

/// A federation under the Countrymen games list's rating floor and filter.
@immutable
class CountrymenLiveGamesScope {
  factory CountrymenLiveGamesScope({
    required String countryCode,
    int minElo = 0,
    GameFilter? filter,
    Duration poll = FavoritesLiveGamesScope.listPoll,
  }) => CountrymenLiveGamesScope._(
    countryCode.trim().toUpperCase(),
    minElo,
    _countedFilter(filter),
    poll,
  );

  const CountrymenLiveGamesScope._(
    this.countryCode,
    this.minElo,
    this.filter,
    this.poll,
  );

  /// Upper case, trimmed.
  final String countryCode;

  /// The list's rating floor (raised to the filter's minimum server-side).
  final int minElo;

  /// The list's filter, its sort order dropped (it changes no count).
  final GameFilter? filter;
  final Duration poll;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CountrymenLiveGamesScope &&
          other.countryCode == countryCode &&
          other.minElo == minElo &&
          other.filter == filter &&
          other.poll == poll;

  @override
  int get hashCode => Object.hash(countryCode, minElo, filter, poll);

  @override
  String toString() =>
      'CountrymenLiveGamesScope($countryCode, $minElo, $filter, $poll)';
}

/// The games in play in an event's tours. Null until the first answer.
final eventLiveGameIdsProvider = StateNotifierProvider.autoDispose
    .family<LiveGameIdsNotifier, LiveGameIds, EventLiveGamesScope>(
      (ref, scope) => LiveGameIdsNotifier(
        ref,
        poll: scope.poll,
        fetch: (repository) =>
            repository.getLiveGameIds(tourIds: scope.tourIds),
      ),
    );

/// The games in play among the reader's favorite players, under the
/// Favorites list's filter. Null until the first answer.
final favoritesLiveGameIdsProvider = StateNotifierProvider.autoDispose
    .family<LiveGameIdsNotifier, LiveGameIds, FavoritesLiveGamesScope>(
      (ref, scope) => LiveGameIdsNotifier(
        ref,
        poll: scope.poll,
        fetch: (repository) => repository.getLiveGameIds(
          fideIds: scope.fideIds,
          filter: scope.filter,
        ),
      ),
    );

/// The games in play with a player of a federation, under the Countrymen
/// list's rating floor and filter. Null until the first answer.
final countrymenLiveGameIdsProvider = StateNotifierProvider.autoDispose
    .family<LiveGameIdsNotifier, LiveGameIds, CountrymenLiveGamesScope>(
      (ref, scope) => LiveGameIdsNotifier(
        ref,
        poll: scope.poll,
        fetch: (repository) => repository.getLiveGameIds(
          countryCode: scope.countryCode,
          minElo: scope.minElo,
          filter: scope.filter,
        ),
      ),
    );

/// The ids in [live] that [shown] holds: what a list's capsule counts and
/// its Live first lifts. Null while [live] is unknown.
Set<String>? liveIdsAmong(Set<String>? live, Iterable<String> shown) {
  if (live == null) return null;
  if (live.isEmpty) return const <String>{};
  return {
    for (final id in shown)
      if (live.contains(id)) id,
  };
}

/// How many of [shown] are in play, by [live]. Null while [live] is unknown
/// (the capsule reads "See live").
int? liveCountAmong(Set<String>? live, Iterable<String> shown) =>
    liveIdsAmong(live, shown)?.length;

/// Keeps one scope's live-game ids: see [LiveGameIds].
class LiveGameIdsNotifier extends StateNotifier<LiveGameIds> {
  LiveGameIdsNotifier(
    this._ref, {
    required this._fetch,
    required this.poll,
    this._timeout = const Duration(seconds: 10),
    bool Function()? isForeground,
  }) : _isForeground = isForeground ?? _appInForeground,
       super(null) {
    _ref.listen<AsyncValue<List<String>>>(liveRoundsIdProvider, (
      previous,
      next,
    ) {
      final before = previous?.valueOrNull;
      final now = next.valueOrNull;
      // The first value is no change: the open already asked.
      if (before == null || now == null) return;
      if (setEquals(before.toSet(), now.toSet())) return;
      _wanted();
    });
    _ref.listen<int>(appResumedSignalProvider, (_, __) => _wanted());
    _timer = Timer.periodic(poll, (_) {
      if (_visible && _isForeground()) unawaited(refresh());
    });
    unawaited(refresh());
  }

  final Ref _ref;
  final Future<Set<String>?> Function(GameRepository repository) _fetch;
  final Duration _timeout;
  final bool Function() _isForeground;

  /// How often the ids are asked for while the list is in view.
  final Duration poll;

  Timer? _timer;
  Future<void>? _inFlight;
  bool _again = false;

  /// A change arrived while the list was out of view; asked once it is back.
  bool _missed = false;

  /// Whether the list reading these ids is on screen. Out of view, the
  /// timer and the live-round and resume triggers wait; coming back asks at
  /// once if anything was missed. True by default.
  bool get visible => _visible;
  bool _visible = true;
  set visible(bool value) {
    if (_visible == value) return;
    _visible = value;
    if (value && _missed) {
      _missed = false;
      unawaited(refresh());
    }
  }

  void _wanted() {
    if (!mounted) return;
    if (!_visible) {
      _missed = true;
      return;
    }
    unawaited(refresh());
  }

  /// Asks the server now. One request at a time; a call while one is out
  /// asks once more after it, and completes after that.
  Future<void> refresh() {
    if (!mounted) return Future<void>.value();
    final running = _inFlight;
    if (running != null) {
      _again = true;
      return running;
    }
    return _inFlight = () async {
      try {
        do {
          _again = false;
          await _ask();
        } while (_again && mounted);
      } finally {
        _inFlight = null;
      }
    }();
  }

  Future<void> _ask() async {
    try {
      final ids = await _fetch(
        _ref.read(gameRepositoryProvider),
      ).timeout(_timeout);
      if (!mounted) return;
      // Null: the backend cannot say (no function, no session). Never a
      // guess: the count stays unknown, or at its last good answer.
      if (ids == null) return;
      final current = state;
      if (current != null && setEquals(current, ids)) return;
      state = Set<String>.unmodifiable(ids);
    } catch (error) {
      // The last good answer stands; the next trigger asks again.
      debugPrint('[LiveGameIds] $error');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

bool _appInForeground() {
  final state = SchedulerBinding.instance.lifecycleState;
  return state == null || state == AppLifecycleState.resumed;
}

List<String> _sortedIds(Iterable<String> ids) => List<String>.unmodifiable(
  {
    for (final id in ids)
      if (id.trim().isNotEmpty) id.trim(),
  }.toList()..sort(),
);

GameFilter? _countedFilter(GameFilter? filter) =>
    filter == null || filter.sorts.isEmpty
    ? filter
    : filter.copyWith(sorts: const <GameSortCriterion>[]);
