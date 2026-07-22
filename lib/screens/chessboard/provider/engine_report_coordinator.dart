import 'dart:async';

import 'package:flutter/foundation.dart';

/// Time-shares the single shared Stockfish engine between the on-board
/// **eval bar / engine lines** (which always take precedence) and the
/// whole-game **report generator** (which only runs in the gaps).
///
/// The model, in the user's words: the eval bar and engine lines analyze the
/// viewed position first; once they reach a quality threshold ([handoffDepth])
/// the report is allowed to run and quickly finish; when the report is done the
/// engine goes back to deepening the eval bar / lines per the user's engine
/// settings.
///
/// How the two sides cooperate:
/// 1. The board is the high-priority Stockfish consumer, so its jobs already
///    preempt the report in [StockfishSingleton]. On top of that, while a
///    report is pending the board caps its own search at [handoffDepth]
///    ([shouldCapBoardDepth]) so it finishes fast and frees the engine instead
///    of deepening to depth 60 / infinity and starving the report.
/// 2. The report waits ([waitForBoardHandoff]) until the board's current
///    position has reached [handoffDepth] or the board went idle, so it never
///    thrashes against the board's climb to the threshold.
/// 3. When the report settles (completed / cancelled / failed / inactive) the
///    board's registered resume callback fires so it re-analyzes the viewed
///    position at the user's full configured depth.
///
/// Only one board page searches at a time (off-screen boards do not run
/// Stockfish) and only the visible game's report auto-runs, so a single shared
/// instance is sufficient.
class EngineReportCoordinator {
  EngineReportCoordinator._();

  static final EngineReportCoordinator instance = EngineReportCoordinator._();

  /// Quality threshold (Stockfish depth) at which the board hands the engine
  /// over to the report generator.
  static const int handoffDepth = 18;

  int _boardDepth = 0;
  bool _boardBusy = false;
  bool _reportPending = false;
  String? _reportOwner;
  final List<Completer<void>> _waiters = <Completer<void>>[];
  final Map<String, VoidCallback> _resumeCallbacks = <String, VoidCallback>{};

  /// True while a whole-game report is running or waiting to run. The board
  /// reads this to cap its own search depth.
  bool get reportPending => _reportPending;

  /// The board should cap its search at [handoffDepth] while this is true.
  bool get shouldCapBoardDepth => _reportPending;

  /// True once the board has either reached the handoff depth on the current
  /// position or gone idle — i.e. the report may safely take the engine.
  bool get _handoffReached => !_boardBusy || _boardDepth >= handoffDepth;

  /// Whether an in-flight board search that started above [handoffDepth] should
  /// stop now so a pending report can borrow the engine.
  ///
  /// Pure helper so unit tests and the board provider share one contract:
  /// yield only when a report is pending, the search was not already capped,
  /// the threshold is reached, and we have not already started yielding.
  static bool shouldYieldBoardSearchForReport({
    required int depth,
    required bool reportPending,
    required int searchMaxDepth,
    required bool alreadyYielding,
    int handoffDepth = EngineReportCoordinator.handoffDepth,
  }) {
    if (alreadyYielding || !reportPending) return false;
    if (depth < handoffDepth) return false;
    if (searchMaxDepth <= handoffDepth) return false;
    return true;
  }

  /// Depth the board should request from Stockfish for a new search while a
  /// report may be pending. Caps at [handoffDepth] so the board finishes fast
  /// and frees the engine; when no report is pending returns [configuredMaxDepth].
  static int boardSearchMaxDepth({
    required int configuredMaxDepth,
    required bool reportPending,
    int handoffDepth = EngineReportCoordinator.handoffDepth,
  }) {
    if (!reportPending) return configuredMaxDepth;
    return configuredMaxDepth > handoffDepth ? handoffDepth : configuredMaxDepth;
  }

  /// Board: a fresh search started for the currently viewed position.
  void boardSearchStarted() {
    _boardDepth = 0;
    _boardBusy = true;
  }

  /// Board: progressive depth update for the current position.
  void boardDepth(int depth) {
    if (depth > _boardDepth) _boardDepth = depth;
    if (_handoffReached) _releaseWaiters();
  }

  /// Board: the current-position search finished (or was cancelled) — the
  /// engine is free for the report.
  void boardSearchIdle() {
    _boardBusy = false;
    _releaseWaiters();
  }

  /// Board: register a callback that re-triggers a full-depth board evaluation
  /// once the report settles. Keyed by the board's Stockfish owner id so
  /// stacked board pages never cross-fire.
  void registerResume(String ownerId, VoidCallback resume) {
    _resumeCallbacks[ownerId] = resume;
  }

  void unregisterResume(String ownerId) {
    _resumeCallbacks.remove(ownerId);
  }

  /// Report: flag that a report is pending. When cleared, the board's resume
  /// callbacks fire so it deepens past the handoff cap again.
  ///
  /// [ownerId] scopes the hold: once a report claims it, only that same owner
  /// (or an unowned caller, e.g. tests) may release it, so a different
  /// controller's invalidate/dispose can't un-cap the board mid-report.
  void setReportPending(bool pending, {String? ownerId}) {
    if (pending) {
      _reportPending = true;
      _reportOwner = ownerId;
      return;
    }
    // Only the current holder (or an unowned hold/caller) may release.
    if (_reportOwner != null && ownerId != null && _reportOwner != ownerId) {
      return;
    }
    if (!_reportPending) return;
    _reportPending = false;
    _reportOwner = null;
    _releaseWaiters();
    for (final resume in List<VoidCallback>.of(_resumeCallbacks.values)) {
      resume();
    }
  }

  /// Report: await until the board has reached the handoff depth or gone idle.
  ///
  /// Bounded by a short timeout so a missed idle signal can never wedge the
  /// report — the board still preempts it at the engine level if it isn't
  /// actually done.
  Future<void> waitForBoardHandoff() {
    if (_handoffReached) return Future<void>.value();
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        _waiters.remove(completer);
      },
    );
  }

  void _releaseWaiters() {
    if (_waiters.isEmpty) return;
    final pending = List<Completer<void>>.of(_waiters);
    _waiters.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Test-only reset so unit tests start from a clean slate.
  @visibleForTesting
  void resetForTest() {
    _boardDepth = 0;
    _boardBusy = false;
    _reportPending = false;
    _reportOwner = null;
    _releaseWaiters();
    _resumeCallbacks.clear();
  }
}
