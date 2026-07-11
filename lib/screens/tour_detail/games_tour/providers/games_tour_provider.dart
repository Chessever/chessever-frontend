import 'dart:async';

import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final shouldStreamProvider = StateProvider((ref) => true);
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

final gamesTourProvider = AutoDisposeStateNotifierProvider.family<
  GamesTourNotifier,
  AsyncValue<List<Games>>,
  String
>((ref, tourId) => GamesTourNotifier(ref: ref, tourId: tourId));

/// Notifier that manages the list of games for a tournament.
///
/// **Architecture:**
/// - This provider holds ALL games in memory as a list
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
    _loadInitialGames();

    // Listen to shouldStreamProvider changes
    _shouldStreamListener = ref.listen<bool>(shouldStreamProvider, (
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
        if (_usesLiveEventData(next) && ref.read(shouldStreamProvider)) {
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
  ProviderSubscription? _shouldStreamListener;
  ProviderSubscription? _selectedModeListener;
  ProviderSubscription? _primaryTourListener;
  Timer? _refreshTimer;
  bool _refreshLoopActive = false;
  bool _safetyNetRefreshInFlight = false;
  int _refreshGeneration = 0;

  Future<void> _loadInitialGames() async {
    try {
      // Gamebase-only event (sentinel tour id): build games from the cached
      // gamebase event view; these are finished games with no live feed, so
      // skip the Supabase fetch/cache and the periodic refresh entirely.
      if (isVirtualGamebaseId(tourId)) {
        final virtualKey = virtualEventKeyFromId(tourId);
        final view =
            virtualKey == null
                ? null
                : await ref.read(
                  gamebaseEventViewProvider(
                    GamebaseEventViewRequest(
                      eventName: virtualKey.eventName,
                      site: virtualKey.site,
                      slug: virtualKey.slug,
                    ),
                  ).future,
                );
        if (mounted) {
          state = AsyncValue.data(
            view == null
                ? const <Games>[]
                : virtualGamesFromView(view, virtualId: tourId),
          );
        }
        return;
      }

      final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
      final games = await gamesLocalStorageProvider.fetchAndSaveGames(tourId);

      if (mounted) {
        state = AsyncValue.data(games);

        // Only start periodic refresh if streaming is enabled
        if (_shouldRunSafetyNet) {
          _startPeriodicRefresh();
        }
      }
    } catch (error, stackTrace) {
      if (mounted) {
        state = AsyncValue.error(error, stackTrace);
      }
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
      ref.read(shouldStreamProvider) && _isEventDataTabVisible;

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
    if (isVirtualGamebaseId(tourId) ||
        !_shouldRunSafetyNet ||
        state.valueOrNull == null) {
      return;
    }

    _stopPeriodicRefresh();

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
      final currentGames = state.valueOrNull;
      if (currentGames == null) return;

      final safetySnapshots = await ref
          .read(gameRepositoryProvider)
          .getTourGamesSafetyNet(tourId);
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
        state = AsyncValue.data(mergedGames);
      }
    } catch (error, _) {
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
    final freshGames = await ref
        .read(gamesLocalStorage)
        .fetchAndSaveGames(tourId, forceRefresh: true);
    if (!_isRefreshActive(generation)) return;

    debugPrint(
      '🔥 GamesTourNotifier: Detected game count change! Current: '
      '${currentGames.length}, Fresh: ${freshGames.length}',
    );
    final currentById = {for (final game in currentGames) game.id: game};
    final mergedGames = freshGames
        .map((fresh) {
          final current = currentById[fresh.id];
          if (current == null) return fresh;
          return current.copyWith(
            roundId: fresh.roundId,
            roundSlug: fresh.roundSlug,
            status: fresh.status ?? current.status,
          );
        })
        .toList(growable: false);
    state = AsyncValue.data(mergedGames);
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

  Future<void> refreshGames() async {
    await _loadInitialGames();
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
