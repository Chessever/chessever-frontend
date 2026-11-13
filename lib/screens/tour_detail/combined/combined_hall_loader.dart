import 'dart:async';

/// Bounded, event-owned loading. A third lane stays available for demand while
/// background work uses at most two lanes. Epochs discard responses after pause.
class CombinedHallLoader<R, G> {
  CombinedHallLoader({
    required this.sourceIds,
    required this.readSource,
    required this.readPage,
    required this.roundId,
    required this.sourceId,
    required this.validGame,
    required this.finished,
    required this.orderRounds,
    required this.onChange,
    this.backgroundDelay = const Duration(milliseconds: 120),
    this.publishDelay = const Duration(milliseconds: 200),
    this.refreshInterval = const Duration(seconds: 20),
  }) {
    if (sourceIds.isNotEmpty) _enqueueSource(sourceIds.first, urgent: true);
    scheduleMicrotask(_pump);
  }
  final List<String> sourceIds;
  final Future<List<R>> Function(String) readSource;
  final Future<List<G>> Function(R, int, int) readPage;
  final String Function(R) roundId, sourceId;
  final bool Function(R, G) validGame;
  final bool Function(G) finished;
  final List<R> Function(List<R>) orderRounds;
  final void Function() onChange;
  final Duration backgroundDelay, publishDelay, refreshInterval;
  final Map<String, List<R>> catalogs = {};
  final Map<String, List<G>> games = {};
  final Set<String> loaded = {}, failures = {};
  final List<_HallJob> _queue = [];
  final Set<String> _runningKeys = {};
  Set<String> _demand = {}, _watched = {};
  int _running = 0, _backgroundRunning = 0, _epoch = 0;
  bool _active = true, _disposed = false, _backgroundReady = false;
  bool _seeded = false;
  Timer? _backgroundTimer, _publishTimer, _refreshTimer;
  bool get isLoading => !_seeded && catalogs.isEmpty && failures.isEmpty;

  void demand(Iterable<String> ids) {
    _demand = ids.toSet();
    _pump();
  }

  void watch(Iterable<String> ids) => _watched = ids.toSet();
  void setActive(bool active) {
    if (_active == active || _disposed) return;
    _active = active;
    if (!active) {
      _epoch++;
      _backgroundTimer?.cancel();
      _publishTimer?.cancel();
      _refreshTimer?.cancel();
      _backgroundTimer = null;
      _publishTimer = null;
      _refreshTimer = null;
    } else {
      // Notify once so state accepted before a pause is not left unpublished.
      onChange();
      _startBackground();
      _pump();
    }
  }

  void refresh({bool retry = false}) {
    if (!_active || _disposed) return;
    if (retry) failures.clear();
    for (final id in sourceIds) {
      _enqueueSource(id, urgent: false);
    }
    for (final rounds in catalogs.values) {
      for (final round in rounds) {
        final id = roundId(round);
        final rows = games[id];
        if (_watched.contains(id) &&
            (rows == null || rows.isEmpty || !rows.every(finished))) {
          _enqueueRound(round, refresh: true);
        } else if (retry && !loaded.contains(id)) {
          _enqueueRound(round);
        }
      }
    }
    _pump();
  }

  void _enqueueSource(String id, {required bool urgent}) {
    _add(
      _HallJob('source:$id', urgent, () async {
        final epoch = _epoch;
        final rounds = await readSource(id);
        if (!_accept(epoch)) return false;
        if (rounds.any((r) => sourceId(r) != id)) {
          throw StateError('Combined source mismatch');
        }
        final removed = (catalogs[id] ?? <R>[]).map(roundId).toSet()
          ..removeAll(rounds.map(roundId));
        for (final stale in removed) {
          games.remove(stale);
          loaded.remove(stale);
          failures.remove('round:$stale');
        }
        _queue.removeWhere((job) => removed.contains(job.round));
        catalogs[id] = List.unmodifiable(rounds);
        final ordered = orderRounds(rounds);
        if (!_seeded) {
          _seeded = true;
          if (ordered.isNotEmpty) _enqueueRound(ordered.first, preview: true);
          _startBackground();
        }
        for (final round in ordered) {
          _enqueueRound(round);
        }
        return true;
      }),
    );
  }

  void _enqueueRound(R round, {bool preview = false, bool refresh = false}) {
    final id = roundId(round);
    if (!(catalogs[sourceId(round)] ?? <R>[]).any((r) => roundId(r) == id)) {
      return;
    }
    if (!refresh && (loaded.contains(id) || failures.contains('round:$id'))) {
      return;
    }
    _add(
      _HallJob(
        'round:$id',
        preview,
        () async {
          final epoch = _epoch;
          final offset = refresh ? 0 : (games[id]?.length ?? 0);
          final limit = preview ? 16 : 1000;
          final page = await readPage(round, offset, limit);
          if (!_accept(epoch)) return false;
          if (!(catalogs[sourceId(round)] ?? <R>[]).any(
            (r) => roundId(r) == id,
          )) {
            return true;
          }
          if (page.any((g) => !validGame(round, g))) {
            throw StateError('Combined round mismatch');
          }
          final previous = refresh ? <G>[] : (games[id] ?? <G>[]);
          games[id] = List.unmodifiable([...previous, ...page]);
          if (page.length < limit) {
            loaded.add(id);
          } else {
            loaded.remove(id);
          }
          return true;
        },
        round: id,
        after: () {
          if (!loaded.contains(id)) _enqueueRound(round);
        },
      ),
    );
  }

  void _add(_HallJob job) {
    if (_disposed ||
        _runningKeys.contains(job.key) ||
        _queue.any((j) => j.key == job.key)) {
      return;
    }
    _queue.add(job);
  }

  bool _accept(int epoch) => !_disposed && _active && epoch == _epoch;
  void _startBackground() {
    if (!_active || _disposed) return;
    _backgroundTimer ??= Timer(backgroundDelay, () {
      _backgroundTimer = null;
      _backgroundReady = true;
      for (final id in sourceIds) {
        if (!catalogs.containsKey(id) && !failures.contains('source:$id')) {
          _enqueueSource(id, urgent: false);
        }
      }
      _pump();
    });
    _refreshTimer ??= Timer.periodic(refreshInterval, (_) => refresh());
  }

  void _pump() {
    if (!_active || _disposed) return;
    while (_running < 3) {
      var index = _queue.indexWhere(
        (j) => j.urgent || _demand.contains(j.round),
      );
      if (index < 0) {
        if (!_backgroundReady || _backgroundRunning >= 2) return;
        index = _queue.indexWhere((j) => j.key.startsWith('source:'));
        if (index < 0) index = _queue.isEmpty ? -1 : 0;
      }
      if (index < 0) return;
      final job = _queue.removeAt(index);
      final urgent = job.urgent || _demand.contains(job.round);
      _running++;
      if (!urgent) _backgroundRunning++;
      _runningKeys.add(job.key);
      final epoch = _epoch;
      () async {
        var accepted = false;
        try {
          accepted = await job.run();
          if (accepted) failures.remove(job.key);
        } catch (_) {
          if (_accept(epoch)) {
            failures.add(job.key);
            if (job.key.startsWith('source:')) _startBackground();
            accepted = true;
          }
        } finally {
          _running--;
          if (!urgent) _backgroundRunning--;
          _runningKeys.remove(job.key);
          if (_accept(epoch) && accepted) {
            if (!failures.contains(job.key)) job.after?.call();
            if (urgent || _demand.contains(job.round)) {
              _publishTimer?.cancel();
              _publishTimer = null;
              onChange();
            } else {
              _publishTimer ??= Timer(publishDelay, () {
                _publishTimer = null;
                if (_active && !_disposed) onChange();
              });
            }
          } else if (!_disposed) {
            _queue.add(job);
          }
          _pump();
        }
      }();
    }
  }

  void dispose() {
    _disposed = true;
    _epoch++;
    _queue.clear();
    _backgroundTimer?.cancel();
    _publishTimer?.cancel();
    _refreshTimer?.cancel();
  }
}

class _HallJob {
  _HallJob(this.key, this.urgent, this.run, {this.round, this.after});
  final String key;
  final bool urgent;
  final String? round;
  final Future<bool> Function() run;
  final void Function()? after;
}
