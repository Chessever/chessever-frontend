import 'dart:async';
import 'package:chessever2/providers/event_video_provider.dart';

import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'games_app_bar_provider.dart'
    show pendingRoundNavigationProvider, userSelectedRoundProvider;
import 'initial_tour_round.dart';
import 'live_rounds_id_provider.dart';

import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final shouldStreamProvider = StateProvider((ref) => true);
// The board switcher can enable card streams while this route is covered.
// Its switch must never restart the tournament-wide safety-net poll.
final tournamentDetailVisibleProvider = StateProvider((ref) => false);
final tournamentDataActiveProvider = Provider<bool>(
  (ref) =>
      ref.watch(tournamentDetailVisibleProvider) &&
      ref.watch(shouldStreamProvider),
);
final liveGameCardsPauseReasonsProvider = StateProvider<Set<String>>(
  (ref) => const <String>{},
);
final liveGameCardsPausedProvider = Provider<bool>(
  (ref) => ref.watch(liveGameCardsPauseReasonsProvider).isNotEmpty,
);

void setLiveGameCardsPaused(
  WidgetRef ref, {
  required String reason,
  required bool paused,
}) {
  setLiveGameCardsPausedWithNotifier(
    ref.read(liveGameCardsPauseReasonsProvider.notifier),
    reason: reason,
    paused: paused,
  );
}

void setLiveGameCardsPausedWithNotifier(
  StateController<Set<String>> notifier, {
  required String reason,
  required bool paused,
}) {
  if (reason.isEmpty) return;

  final current = notifier.state;
  final hasReason = current.contains(reason);
  if (paused == hasReason) return;

  if (paused) {
    notifier.state = <String>{...current, reason};
  } else {
    notifier.state = <String>{...current}..remove(reason);
  }
}

bool _usesLiveEventData(TournamentDetailScreenMode mode) =>
    mode == TournamentDetailScreenMode.games ||
    mode == TournamentDetailScreenMode.bracket;

@visibleForTesting
List<Games> retainGamesAcrossTransientEmptyRefresh(
  List<Games> currentGames,
  List<Games> incomingGames,
) {
  if (currentGames.isNotEmpty && incomingGames.isEmpty) {
    return currentGames;
  }
  return incomingGames;
}

final gamesTourProvider = AutoDisposeStateNotifierProvider.family<
  GamesTourNotifier,
  AsyncValue<List<Games>>,
  String
>((ref, tourId) => GamesTourNotifier(ref: ref, tourId: tourId));

/// Consumers calculating event totals explicitly request a complete catalog.
/// Errors surface here without blanking the lazily loaded Games tab.
final completeGamesTourProvider = Provider.autoDispose
    .family<AsyncValue<List<Games>>, String>((ref, tourId) {
      final games = ref.watch(gamesTourProvider(tourId));
      final loader = ref.read(gamesTourProvider(tourId).notifier);
      if (loader.isCatalogComplete) return games;
      final error = loader.catalogError;
      if (error != null) return AsyncValue.error(error, StackTrace.current);
      unawaited(Future.microtask(loader.ensureCompleteCatalog));
      return const AsyncValue.loading();
    });

/// Awaitable complete catalog for standings. The preview never resolves this
/// future, so a loading/error state cannot become a table of partial totals.
final completeGamesTourFutureProvider = FutureProvider.autoDispose
    .family<List<Games>, String>((ref, tourId) {
      final complete = ref.watch(completeGamesTourProvider(tourId));
      if (complete.hasValue) return complete.requireValue;
      if (complete.hasError) {
        Error.throwWithStackTrace(complete.error!, complete.stackTrace!);
      }
      return ref
          .read(gamesTourProvider(tourId).notifier)
          .waitForCompleteCatalog();
    });

/// Notifier that manages the list of games for a tournament.
///
/// **Architecture:**
/// - Only requested rounds load; complete catalogs are explicitly requested
/// - It does NOT maintain individual Supabase Realtime streams per game
/// - Its safety net periodically fetches only game IDs, round IDs, and status;
///   a full snapshot is fetched only when game membership changes
/// - Individual game cards use `liveGameCardProvider` with `.autoDispose`
///   to get realtime updates only for VISIBLE games
/// - When a game card scrolls out of view, its stream is disposed
///
/// This approach minimizes Supabase Realtime connections while still
/// providing instant updates for games the user is actively viewing.
class GamesTourNotifier extends StateNotifier<AsyncValue<List<Games>>> {
  GamesTourNotifier({required this.ref, required this.tourId})
    : super(const AsyncValue.loading()) {
    _loadFinished = _loadInitialGames();

    // Listen to shouldStreamProvider changes
    _shouldStreamListener = ref.listen<bool>(tournamentDataActiveProvider, (
      previous,
      next,
    ) {
      if (next && _isEventDataTabVisible) {
        _startPeriodicRefresh();
      } else {
        _stopPeriodicRefresh();
      }
    });
    _selectedModeListener = ref.listen<TournamentDetailScreenMode>(
      selectedTourModeProvider,
      (_, next) {
        if (_usesLiveEventData(next) &&
            ref.read(tournamentDataActiveProvider)) {
          _startPeriodicRefresh();
        } else {
          _stopPeriodicRefresh();
        }
      },
    );
    _primaryTourListener = ref.listen<String?>(
      tourDetailScreenProvider.select(
        (value) => value.valueOrNull?.aboutTourModel.id,
      ),
      (previous, next) {
        if (previous == next || !_shouldRunSafetyNet) return;
        _startPeriodicRefresh();
      },
    );
  }

  final Ref ref;
  final String tourId;
  late Future<void> _loadFinished;
  bool isCatalogComplete = false;
  Object? catalogError;
  final Set<String> loadedRoundIds = {};
  Set<String> _activeRoundIds = {};
  final Map<String, Object> roundErrors = {};
  int _demandGeneration = 0;
  final Map<String, Future<void>> _roundLoads = {};
  Future<void>? _completeLoad;
  ProviderSubscription? _shouldStreamListener;
  ProviderSubscription? _selectedModeListener;
  ProviderSubscription? _primaryTourListener;
  Timer? _refreshTimer;
  bool _refreshLoopActive = false;
  bool _safetyNetRefreshInFlight = false;
  int _refreshGeneration = 0;

  Future<void> _loadInitialGames() async {
    try {
      if (isVirtualGamebaseId(tourId)) {
        final key = virtualEventKeyFromId(tourId);
        final view =
            key == null
                ? null
                : await ref.read(
                  gamebaseEventViewProvider(
                    GamebaseEventViewRequest(
                      eventName: key.eventName,
                      site: key.site,
                      slug: key.slug,
                    ),
                  ).future,
                );
        if (!mounted) return;
        isCatalogComplete = true;
        state = AsyncValue.data(
          view == null
              ? const <Games>[]
              : virtualGamesFromView(view, virtualId: tourId),
        );
        return;
      }
      // Structural checks for sibling categories must not fetch their games.
      if (!_isPrimaryTour) {
        state = const AsyncValue.data([]);
        return;
      }
      final rounds = await ref
          .read(roundRepositoryProvider)
          .getRoundsByTourId(tourId);
      if (!mounted) return;
      final selection = ref.read(userSelectedRoundProvider);
      final priorityRoundId =
          initialTourRoundId(
            rounds: rounds,
            now: DateTime.now(),
            requestedRoundId:
                ref.read(pendingRoundNavigationProvider) ??
                (selection?.userSelected == true ? selection!.id : null),
            liveRoundIds:
                ref.exists(liveRoundsIdProvider)
                    ? ref.read(liveRoundsIdProvider).valueOrNull ?? const []
                    : const [],
          ) ??
          (await ref
              .read(roundRepositoryProvider)
              .getLatestRoundByLastMove(tourId))?.id;
      if (!mounted) return;
      if (priorityRoundId == null) {
        state = const AsyncValue.data([]);
        return;
      }
      _activeRoundIds = {priorityRoundId};
      await _loadRound(priorityRoundId);
      if (mounted) _startPeriodicRefresh();
    } catch (error, stack) {
      if (mounted) state = AsyncValue.error(error, stack);
    }
  }

  /// Demand comes from visible or explicitly expanded display sections.
  Future<void> setActiveRounds(Set<String> roundIds) async {
    final generation = ++_demandGeneration;
    await _loadFinished;
    if (!mounted ||
        generation != _demandGeneration ||
        isVirtualGamebaseId(tourId)) {
      return;
    }
    final changed = !setEquals(_activeRoundIds, roundIds);
    _activeRoundIds = Set.of(roundIds);
    if (changed) _stopPeriodicRefresh();
    // Bound concurrency when Expand all is used on a large tournament.
    for (final id in roundIds) {
      if (!mounted || generation != _demandGeneration) return;
      if (!_activeRoundIds.contains(id)) continue;
      if (!loadedRoundIds.contains(id)) await _loadRound(id);
    }
    if (mounted && changed) _startPeriodicRefresh();
  }

  void deactivateRounds() {
    _demandGeneration++;
    _activeRoundIds = {};
    _stopPeriodicRefresh();
  }

  Future<void> _loadRound(String roundId, {bool refresh = false}) async {
    final pending = _roundLoads[roundId];
    if (pending != null) return pending;
    if (!refresh && loadedRoundIds.contains(roundId)) return;
    final load = _fetchRound(roundId);
    _roundLoads[roundId] = load;
    try {
      await load;
    } finally {
      _roundLoads.remove(roundId);
    }
  }

  Future<void> _fetchRound(String roundId) async {
    if (roundErrors.remove(roundId) != null && state.hasValue) {
      state = AsyncValue.data(state.requireValue);
    }
    try {
      final games = await ref
          .read(gameRepositoryProvider)
          .getRoundGamePreviews(
            tourId,
            roundId,
            hydrateFallbacks: isCatalogComplete,
          );
      if (!mounted) return;
      loadedRoundIds.add(roundId);
      roundErrors.remove(roundId);
      final current = state.valueOrNull ?? const <Games>[];
      final previous = current.where((g) => g.roundId == roundId).toList();
      state = AsyncValue.data([
        ...current.where((g) => g.roundId != roundId),
        ...retainGamesAcrossTransientEmptyRefresh(previous, games),
      ]);
      ref.read(eventVideoMetadataProvider.notifier).prefetch([
        EventVideoKey(tourId: tourId, roundId: roundId),
      ]);
    } catch (error, stack) {
      if (!mounted) return;
      roundErrors[roundId] = error;
      state =
          state.hasValue
              ? AsyncValue.data(state.requireValue)
              : AsyncValue.error(error, stack);
      // Keep already-visible rounds; a later expansion/refresh retries this one.
      debugPrint('Round $roundId could not load: $error');
    }
  }

  Future<void> ensureCompleteCatalog() async {
    await _loadFinished;
    if (!mounted || isCatalogComplete) return;
    if (_completeLoad != null) return _completeLoad;
    _completeLoad = _fetchCompleteCatalog();
    await _completeLoad;
  }

  Future<void> _fetchCompleteCatalog() async {
    try {
      final games = await ref
          .read(gamesLocalStorage)
          .fetchAndSaveGames(tourId, rethrowErrors: true);
      if (!mounted) return;
      isCatalogComplete = true;
      catalogError = null;
      loadedRoundIds.addAll(games.map((game) => game.roundId));
      state = AsyncValue.data(games);
    } catch (error, stack) {
      if (!mounted) return;
      catalogError = error;
      state =
          state.hasValue
              ? AsyncValue.data(state.requireValue)
              : AsyncValue.error(error, stack);
    }
  }

  // Per-MOVE updates for visible games come from batched Supabase Realtime
  // channels (see liveGameCardProvider / LiveGamesBatchKey), NOT this poll.
  // This timer is only a slow safety net for set-level changes the per-game
  // streams don't cover: newly added games, round rollovers, completions that
  // arrive while a card is off-screen. Keep the selected tour responsive, but
  // avoid starting a synchronized network loop for every sibling stage in
  // multi-stage events.
  static const Duration _primarySafetyNetInterval = Duration(seconds: 5);
  static const Duration _siblingSafetyNetInterval = Duration(seconds: 45);
  static const Duration _primaryFirstSafetyNetDelay = Duration(seconds: 2);
  static const Duration _siblingFirstSafetyNetDelayBase = Duration(seconds: 24);

  bool get _isPrimaryTour {
    final primaryTourId =
        ref.read(tourDetailScreenProvider).valueOrNull?.aboutTourModel.id;
    return primaryTourId != null &&
        primaryTourId.isNotEmpty &&
        primaryTourId == tourId;
  }

  bool get _isEventDataTabVisible =>
      _usesLiveEventData(ref.read(selectedTourModeProvider));

  bool get _shouldRunSafetyNet =>
      ref.read(tournamentDataActiveProvider) && _isEventDataTabVisible;

  int get _stableTourJitterSeconds {
    var hash = 0;
    for (final codeUnit in tourId.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash % 12;
  }

  Duration get _safetyNetInterval =>
      _isPrimaryTour ? _primarySafetyNetInterval : _siblingSafetyNetInterval;

  Duration get _firstSafetyNetDelay =>
      _isPrimaryTour
          ? _primaryFirstSafetyNetDelay
          : _siblingFirstSafetyNetDelayBase +
              Duration(seconds: _stableTourJitterSeconds);

  void _startPeriodicRefresh() {
    // Gamebase-only events are finished with no live feed; never poll Supabase
    // for them (it would return nothing and wipe the synthesized games).
    _stopPeriodicRefresh();
    if (isVirtualGamebaseId(tourId) ||
        !_shouldRunSafetyNet ||
        _activeRoundIds.isEmpty ||
        state.valueOrNull == null) {
      return;
    }

    final interval = _safetyNetInterval;
    final firstDelay = _firstSafetyNetDelay;
    _refreshLoopActive = true;
    final generation = ++_refreshGeneration;

    _refreshTimer = Timer(firstDelay, () async {
      await _checkForNewGames(generation);
      if (!_isRefreshActive(generation)) return;

      _refreshTimer = Timer.periodic(interval, (_) async {
        if (!_isRefreshActive(generation)) return;
        await _checkForNewGames(generation);
      });
    });

    debugPrint(
      '🔥 GamesTourNotifier: Started safety-net refresh '
      '(${interval.inSeconds}s interval, first in ${firstDelay.inSeconds}s) '
      'for tour $tourId',
    );
  }

  void _stopPeriodicRefresh() {
    _refreshLoopActive = false;
    _refreshGeneration += 1;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    debugPrint(
      '🔥 GamesTourNotifier: Stopped periodic refresh for tour $tourId',
    );
  }

  bool _isRefreshActive(int generation) =>
      mounted &&
      _refreshLoopActive &&
      generation == _refreshGeneration &&
      _shouldRunSafetyNet;

  Future<void> _checkForNewGames(int generation) async {
    if (!_isRefreshActive(generation) || _safetyNetRefreshInFlight) return;
    _safetyNetRefreshInFlight = true;
    try {
      final currentGames =
          state.valueOrNull
              ?.where((g) => _activeRoundIds.contains(g.roundId))
              .toList();
      if (currentGames == null) return;

      final safetySnapshots = await ref
          .read(gameRepositoryProvider)
          .getTourGamesSafetyNet(tourId, roundIds: _activeRoundIds);
      if (!_isRefreshActive(generation)) return;

      final currentById = {for (final game in currentGames) game.id: game};
      final safetyById = {
        for (final snapshot in safetySnapshots) snapshot.id: snapshot,
      };
      final membershipChanged =
          safetyById.length != currentById.length ||
          safetyById.keys.any((id) => !currentById.containsKey(id));

      if (membershipChanged) {
        await _refreshAfterMembershipChange(currentGames, generation);
        return;
      }

      var hasChanges = false;
      final mergedGames = <Games>[];
      for (final current in currentGames) {
        final fresh = safetyById[current.id];
        if (fresh == null) continue;
        if (_hasSafetyNetChange(current, fresh)) {
          hasChanges = true;
        }
        mergedGames.add(_mergeSafetyNetSnapshot(current, fresh));
      }

      if (hasChanges && _isRefreshActive(generation)) {
        state = AsyncValue.data([
          ...?state.valueOrNull?.where(
            (g) => !_activeRoundIds.contains(g.roundId),
          ),
          ...mergedGames,
        ]);
      }
    } catch (error) {
      // Suppress noise from races where the notifier is disposed mid-await.
      if (!mounted) return;
      debugPrint('🔥 GamesTourNotifier: Error checking for new games: $error');
    } finally {
      _safetyNetRefreshInFlight = false;
    }
  }

  Future<void> _refreshAfterMembershipChange(
    List<Games> currentGames,
    int generation,
  ) async {
    for (final roundId in _activeRoundIds.toList()) {
      if (!_isRefreshActive(generation)) return;
      await _loadRound(roundId, refresh: true);
    }
  }

  bool _hasSafetyNetChange(Games current, TourGameSafetyNetSnapshot fresh) {
    // Per-move fields (FEN/PGN/last_move/clocks) are intentionally excluded
    // here. Visible cards receive those through batched realtime streams; if
    // the poll writes them into the parent list on every safety-net tick, the
    // whole Games tab rebuilds and can disturb scrolling. The poll only owns
    // set-level changes plus status/round movement for off-screen cards.
    return (fresh.status != null && current.status != fresh.status) ||
        current.roundId != fresh.roundId ||
        current.roundSlug != fresh.roundSlug;
  }

  Games _mergeSafetyNetSnapshot(
    Games current,
    TourGameSafetyNetSnapshot fresh,
  ) {
    return current.copyWith(
      roundId: fresh.roundId,
      roundSlug: fresh.roundSlug,
      status: fresh.status ?? current.status,
    );
  }

  Future<List<Games>> waitForCompleteCatalog() async {
    await ensureCompleteCatalog();
    if (!mounted) throw StateError('Tournament closed while loading');
    if (!isCatalogComplete) {
      throw catalogError ?? StateError('Catalog unavailable');
    }
    return state.requireValue;
  }

  Future<void> refreshGames() async {
    await _loadFinished;
    if (!mounted) return;
    for (final roundId in _activeRoundIds.toList()) {
      if (!mounted) return;
      await _loadRound(roundId, refresh: true);
    }
    if (isCatalogComplete || catalogError != null) {
      isCatalogComplete = false;
      catalogError = null;
      _completeLoad = null;
      await ensureCompleteCatalog();
    }
  }

  @override
  void dispose() {
    _stopPeriodicRefresh();
    _shouldStreamListener?.close();
    _selectedModeListener?.close();
    _primaryTourListener?.close();
    super.dispose();
  }
}
