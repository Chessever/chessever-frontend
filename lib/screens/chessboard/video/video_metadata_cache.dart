import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'video_repository.dart';

/// Round IDs are globally unique. Never reuse a tour response for a round:
/// round-level visibility and overrides are resolved by the spectator API.
@immutable
class EventVideoKey {
  const EventVideoKey({this.tourId = '', this.roundId = ''});

  final String tourId, roundId;
  bool get isEmpty => tourId.isEmpty && roundId.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is EventVideoKey &&
      roundId == other.roundId &&
      (roundId.isNotEmpty || tourId == other.tourId);

  @override
  int get hashCode => Object.hash(roundId, roundId.isEmpty ? tourId : '');
}

/// App-owned metadata only. Players and user selections stay route-owned.
/// Successful empty responses are cached too; a failed refresh retains URLs.
class EventVideoMetadataCache extends ChangeNotifier
    implements EventVideoRepository {
  EventVideoMetadataCache(
    this.repository, {
    this.refreshInterval = const Duration(seconds: 30),
    this.maxEntries = 256,
    this.maxConcurrentRequests = 4,
    DateTime Function()? now,
  }) : assert(maxEntries > 0),
       assert(maxConcurrentRequests > 0),
       _now = now ?? DateTime.now {
    if (repository != null) {
      _timer = Timer.periodic(refreshInterval, (_) => refreshWatched());
    }
  }

  final EventVideoRepository? repository;
  final Duration refreshInterval;
  final int maxEntries, maxConcurrentRequests;
  final DateTime Function() _now;
  final _values = <EventVideoKey, ResolvedEventVideos>{};
  final _attempts = <EventVideoKey, DateTime>{};
  final _errors = <EventVideoKey, Object>{};
  final _pending = <EventVideoKey, Completer<ResolvedEventVideos>>{};
  final _queue = Queue<EventVideoKey>();
  final _watched = <EventVideoKey, int>{};
  Set<EventVideoKey> _liveRounds = {};
  Timer? _timer;
  int _running = 0;
  bool _disposed = false, _foreground = true;

  bool get enabled => repository != null;

  ResolvedEventVideos? peek(EventVideoKey key) => _values[key];

  /// One lease per mounted round, shared by all of its cards and board pages.
  VoidCallback retain(EventVideoKey key) {
    if (!enabled || key.isEmpty || _disposed) return () {};
    _watched.update(key, (count) => count + 1, ifAbsent: () => 1);
    prefetch([key], priority: true);
    var released = false;
    return () {
      if (released || _disposed) return;
      released = true;
      final count = _watched[key] ?? 0;
      if (count <= 1) {
        _watched.remove(key);
      } else {
        _watched[key] = count - 1;
      }
      _trim();
    };
  }

  void setLiveRounds(Iterable<String> roundIds) {
    _liveRounds = {
      for (final id in roundIds)
        if (id.isNotEmpty) EventVideoKey(roundId: id),
    };
    prefetch(_liveRounds);
    _trim();
  }

  void setForeground(bool foreground) {
    if (_disposed || foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      refreshWatched();
      _pump();
    }
  }

  void refreshWatched() {
    if (!_foreground || _disposed) return;
    prefetch(_watched.keys, priority: true);
    prefetch(_liveRounds);
  }

  void prefetch(Iterable<EventVideoKey> keys, {bool priority = false}) {
    if (!enabled || _disposed) return;
    for (final key in keys.toSet()) {
      if (key.isEmpty) continue;
      unawaited(
        _fetch(
          key,
          priority: priority,
        ).then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }

  @override
  Future<ResolvedEventVideos> fetch({
    required String tourId,
    required String roundId,
  }) => _fetch(EventVideoKey(tourId: tourId, roundId: roundId), priority: true);

  Future<ResolvedEventVideos> _fetch(
    EventVideoKey key, {
    required bool priority,
  }) {
    if (!enabled || key.isEmpty || _disposed) {
      return Future.value(const ResolvedEventVideos([]));
    }
    final pending = _pending[key];
    if (pending != null) {
      if (priority && _queue.remove(key)) _queue.addFirst(key);
      return pending.future;
    }
    final attempted = _attempts[key];
    if (attempted != null && _now().difference(attempted) < refreshInterval) {
      final error = _errors[key];
      if (error != null) return Future.error(error);
      final value = _values.remove(key);
      if (value != null) {
        _values[key] = value;
        return Future.value(value);
      }
    }
    final completer = Completer<ResolvedEventVideos>();
    _pending[key] = completer;
    if (priority) {
      _queue.addFirst(key);
    } else {
      _queue.addLast(key);
    }
    _pump();
    return completer.future;
  }

  void _pump() {
    while (!_disposed &&
        _foreground &&
        _running < maxConcurrentRequests &&
        _queue.isNotEmpty) {
      final key = _queue.removeFirst();
      _running++;
      unawaited(_load(key));
    }
  }

  Future<void> _load(EventVideoKey key) async {
    final completer = _pending[key]!;
    _attempts[key] = _now();
    try {
      var result = await repository!.fetch(
        tourId: key.tourId,
        roundId: key.roundId,
      );
      if (!_disposed) {
        _values.remove(key);
        result = ResolvedEventVideos(
          List.unmodifiable(result.streams),
          sourceScope: result.sourceScope,
          sourceId: result.sourceId,
        );
        _values[key] = result;
        _errors.remove(key);
        notifyListeners();
      }
      if (!completer.isCompleted) completer.complete(result);
    } catch (error, stack) {
      if (!_disposed) {
        _errors[key] = error;
        if (error is VideoMetadataException && error.permanent) {
          _values[key] = const ResolvedEventVideos([]);
        }
        notifyListeners();
      }
      if (!completer.isCompleted) completer.completeError(error, stack);
    } finally {
      _pending.remove(key);
      _running--;
      if (!_disposed) {
        _trim();
        _pump();
      }
    }
  }

  void _trim() {
    // Keep active scopes even if they exceed the idle-cache limit. Failed
    // requests without data count too, so browsing cannot grow error state forever.
    final keys = {..._values.keys, ..._attempts.keys};
    for (final key in keys) {
      if (_attempts.length <= maxEntries) break;
      if (_watched.containsKey(key) ||
          _liveRounds.contains(key) ||
          _pending.containsKey(key)) {
        continue;
      }
      _values.remove(key);
      _attempts.remove(key);
      _errors.remove(key);
    }
  }

  /// Sessions borrow this repository. Only its Riverpod owner disposes it.
  @override
  void close() {}

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete(const ResolvedEventVideos([]));
      }
    }
    _queue.clear();
    repository?.close();
    super.dispose();
  }
}
