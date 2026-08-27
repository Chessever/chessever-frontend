import 'dart:async';

import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How long a just-finished board stays in the Live First tier with its
/// score overlay before the structured exit starts.
const Duration kLiveFocusFinishHoldDuration = Duration(seconds: 3);

/// Collapse / fade out of the held card. Only after this completes is the
/// board allowed to leave the live tier — the list never yanks it away.
const Duration kLiveFocusFinishExitDuration = Duration(milliseconds: 360);

enum LiveFocusFinishPhase { holding, exiting }

@immutable
class LiveFocusFinishHoldState {
  const LiveFocusFinishHoldState({
    this.phases = const <String, LiveFocusFinishPhase>{},
  });

  final Map<String, LiveFocusFinishPhase> phases;

  Set<String> get heldIds => phases.keys.toSet();

  LiveFocusFinishPhase? phaseOf(String gameId) => phases[gameId];

  bool contains(String gameId) => phases.containsKey(gameId);

  LiveFocusFinishHoldState withPhase(
    String gameId,
    LiveFocusFinishPhase phase,
  ) {
    return LiveFocusFinishHoldState(
      phases: <String, LiveFocusFinishPhase>{...phases, gameId: phase},
    );
  }

  LiveFocusFinishHoldState without(String gameId) {
    if (!phases.containsKey(gameId)) return this;
    return LiveFocusFinishHoldState(
      phases: <String, LiveFocusFinishPhase>{...phases}..remove(gameId),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LiveFocusFinishHoldState && mapEquals(phases, other.phases);
  }

  @override
  int get hashCode => Object.hashAll(
    phases.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}

final liveFocusFinishHoldProvider = StateNotifierProvider.autoDispose
    .family<LiveFocusFinishHold, LiveFocusFinishHoldState, String>((
      ref,
      tourId,
    ) {
      final notifier = LiveFocusFinishHold();
      ref.listen<GameDisplayMode>(gameDisplayModeProvider(tourId), (
        previous,
        next,
      ) {
        if (next != GameDisplayMode.hideFinishedGames) {
          notifier.reset();
        }
      });
      return notifier;
    });

/// Remembers boards that just finished while Live First is on so the grouped
/// list can keep them in the live tier through the overlay + exit animation.
///
/// [ingestFinishedIds] is safe to call during a provider build: it returns the
/// ids to keep in the live tier on this frame and only notifies listeners on
/// a later microtask (or when a timer expires). [hold] is the live-card path
/// and notifies immediately.
class LiveFocusFinishHold extends StateNotifier<LiveFocusFinishHoldState> {
  LiveFocusFinishHold({this.holdDuration = kLiveFocusFinishHoldDuration})
    : super(const LiveFocusFinishHoldState());

  final Duration holdDuration;

  final Map<String, Timer> _timers = <String, Timer>{};
  Set<String> _seenFinished = <String>{};
  bool _hasSnapshot = false;

  @visibleForTesting
  bool get hasSnapshot => _hasSnapshot;

  /// Record a finish as soon as a visible card sees it, before the parent
  /// games list has caught up. Does not restart an already-running hold.
  void hold(String gameId) {
    if (gameId.isEmpty) return;
    if (!_armHold(gameId)) return;
    _seenFinished.add(gameId);
    state = state.withPhase(gameId, LiveFocusFinishPhase.holding);
  }

  /// Fold the current finished set into the hold window.
  ///
  /// The first call only snapshots membership so already-finished boards are
  /// not treated as "just ended". Later calls hold newly finished ids.
  Set<String> ingestFinishedIds(Set<String> finishedIds) {
    if (!_hasSnapshot) {
      _seenFinished = <String>{...finishedIds, ...state.heldIds};
      _hasSnapshot = true;
      return state.heldIds;
    }

    final newlyFinished = finishedIds.difference(_seenFinished);
    _seenFinished = <String>{...finishedIds, ...state.heldIds};
    if (newlyFinished.isEmpty) return state.heldIds;

    var added = false;
    for (final gameId in newlyFinished) {
      if (_armHold(gameId)) added = true;
    }
    if (!added) return state.heldIds;

    final nextPhases = <String, LiveFocusFinishPhase>{
      ...state.phases,
      for (final gameId in newlyFinished)
        gameId: state.phaseOf(gameId) ?? LiveFocusFinishPhase.holding,
    };
    scheduleMicrotask(() {
      if (!mounted) return;
      var merged = state.phases;
      var changed = false;
      for (final gameId in newlyFinished) {
        if (merged.containsKey(gameId)) continue;
        merged = <String, LiveFocusFinishPhase>{
          ...merged,
          gameId: LiveFocusFinishPhase.holding,
        };
        changed = true;
      }
      if (changed) {
        state = LiveFocusFinishHoldState(phases: merged);
      }
    });
    return nextPhases.keys.toSet();
  }

  void release(String gameId) {
    _timers.remove(gameId)?.cancel();
    if (!state.contains(gameId)) return;
    state = state.without(gameId);
  }

  void reset() {
    _hasSnapshot = false;
    _seenFinished = <String>{};
    if (_timers.isEmpty && state.phases.isEmpty) return;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    state = const LiveFocusFinishHoldState();
  }

  bool _armHold(String gameId) {
    if (gameId.isEmpty || _timers.containsKey(gameId)) return false;
    _timers[gameId] = Timer(holdDuration, () => _beginExit(gameId));
    return true;
  }

  void _beginExit(String gameId) {
    _timers.remove(gameId);
    if (!state.contains(gameId)) return;
    state = state.withPhase(gameId, LiveFocusFinishPhase.exiting);
    _timers[gameId] = Timer(kLiveFocusFinishExitDuration, () {
      release(gameId);
    });
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}
