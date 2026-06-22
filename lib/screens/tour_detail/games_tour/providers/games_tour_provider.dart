import 'dart:async';

import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
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

final gamesTourProvider = AutoDisposeStateNotifierProvider.family<
  GamesTourNotifier,
  AsyncValue<List<Games>>,
  String
>((ref, tourId) => GamesTourNotifier(ref: ref, tourId: tourId));

/// Notifier that manages the list of games for a tournament.
///
/// **Architecture (Post-Revert):**
/// - This provider holds ALL games in memory as a list
/// - It does NOT maintain individual Supabase Realtime streams per game
/// - Instead, it uses periodic polling (every 10 seconds) to fetch updates
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
      if (next) {
        _startPeriodicRefresh();
      } else {
        _stopPeriodicRefresh();
      }
    });
  }

  final Ref ref;
  final String tourId;
  ProviderSubscription? _shouldStreamListener;
  Timer? _refreshTimer;
  bool _refreshLoopActive = false;

  Future<void> _loadInitialGames() async {
    try {
      // Gamebase-only event (sentinel tour id): build games from the cached
      // gamebase event view; these are finished games with no live feed, so
      // skip the Supabase fetch/cache and the periodic refresh entirely.
      if (isVirtualGamebaseId(tourId)) {
        final eventName = eventNameFromVirtualId(tourId);
        final view =
            eventName == null
                ? null
                : await ref.read(
                  gamebaseEventViewProvider(
                    GamebaseEventViewRequest(eventName: eventName),
                  ).future,
                );
        if (mounted) {
          state = AsyncValue.data(
            view == null ? const <Games>[] : virtualGamesFromView(view),
          );
        }
        return;
      }

      final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
      final games = await gamesLocalStorageProvider.fetchAndSaveGames(tourId);

      if (mounted) {
        state = AsyncValue.data(games);

        // Only start periodic refresh if streaming is enabled
        final shouldStream = ref.read(shouldStreamProvider);
        if (shouldStream) {
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
  // avoid starting a synchronized 10s network loop for every sibling stage in
  // multi-stage events.
  static const Duration _primarySafetyNetInterval = Duration(seconds: 10);
  static const Duration _siblingSafetyNetInterval = Duration(seconds: 45);
  static const Duration _primaryFirstSafetyNetDelay = Duration(seconds: 2);
  static const Duration _siblingFirstSafetyNetDelayBase = Duration(seconds: 24);

  bool get _isPrimaryTour {
    final primaryTourId =
        ref.read(tourDetailScreenProvider).valueOrNull?.aboutTourModel.id;
    return primaryTourId == null ||
        primaryTourId.isEmpty ||
        primaryTourId == tourId;
  }

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
    if (isVirtualGamebaseId(tourId)) return;

    _stopPeriodicRefresh();

    final interval = _safetyNetInterval;
    final firstDelay = _firstSafetyNetDelay;
    _refreshLoopActive = true;

    _refreshTimer = Timer(firstDelay, () async {
      await _checkForNewGames();
      if (!mounted || !_refreshLoopActive) return;

      _refreshTimer = Timer.periodic(interval, (_) async {
        if (!_refreshLoopActive) return;
        await _checkForNewGames();
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
    _refreshTimer?.cancel();
    _refreshTimer = null;
    debugPrint(
      '🔥 GamesTourNotifier: Stopped periodic refresh for tour $tourId',
    );
  }

  Future<void> _checkForNewGames() async {
    if (!mounted) return;
    try {
      final currentGames = state.valueOrNull;
      if (currentGames == null) return;

      // Fetch fresh games from the server
      final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
      final freshGames = await gamesLocalStorageProvider.fetchAndSaveGames(
        tourId,
        forceRefresh: true,
      );
      if (!mounted) return;

      final currentById = {for (final game in currentGames) game.id: game};
      final freshIds = <String>{};
      bool hasChanges = freshGames.length != currentGames.length;
      final mergedGames = <Games>[];

      if (freshGames.length != currentGames.length) {
        debugPrint(
          '🔥 GamesTourNotifier: Detected game count change! Current: ${currentGames.length}, Fresh: ${freshGames.length}',
        );
      }

      for (final fresh in freshGames) {
        freshIds.add(fresh.id);
        final current = currentById[fresh.id];

        if (current == null) {
          // New game added
          hasChanges = true;
          mergedGames.add(fresh);
          continue;
        }

        if (_hasSafetyNetChange(current, fresh)) {
          hasChanges = true;
        }

        mergedGames.add(_mergeSafetyNetSnapshot(current, fresh));
      }

      // Check for removed games
      for (final removedId in currentById.keys) {
        if (!freshIds.contains(removedId)) {
          hasChanges = true;
        }
      }

      if (hasChanges && mounted) {
        state = AsyncValue.data(mergedGames);
      }
    } catch (error, _) {
      // Suppress noise from races where the notifier is disposed mid-await.
      if (!mounted) return;
      debugPrint('🔥 GamesTourNotifier: Error checking for new games: $error');
    }
  }

  bool _hasSafetyNetChange(Games current, Games fresh) {
    // Per-move fields (FEN/PGN/last_move/clocks) are intentionally excluded
    // here. Visible cards receive those through batched realtime streams; if
    // the poll writes them into the parent list every 10s, the whole Games tab
    // rebuilds and can disturb scrolling. The poll only owns set-level changes
    // plus status/round movement for off-screen cards.
    return (fresh.status != null && current.status != fresh.status) ||
        current.roundId != fresh.roundId ||
        current.roundSlug != fresh.roundSlug;
  }

  Games _mergeSafetyNetSnapshot(Games current, Games fresh) {
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
    super.dispose();
  }
}
