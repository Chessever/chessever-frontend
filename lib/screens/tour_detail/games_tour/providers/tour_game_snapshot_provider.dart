import 'dart:async';

import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A full record lives only as long as a card (or its board) listens. The list
/// retains the small index; Riverpod owns snapshot lifetime, not an LRU cache.
final tourGameSnapshotProvider = FutureProvider.autoDispose
    .family<Games?, String>((ref, gameId) {
      final batcher = ref.watch(_snapshotBatcherProvider);
      final request = batcher.request(gameId);
      ref.onDispose(() => batcher.cancel(gameId, request));
      return request.future;
    });

final _snapshotBatcherProvider = Provider.autoDispose<_SnapshotBatcher>((ref) {
  final batcher = _SnapshotBatcher(ref.watch(gameRepositoryProvider));
  ref.listen<bool>(liveGameCardsPausedProvider, (_, paused) {
    batcher.setPaused(paused);
  }, fireImmediately: true);
  ref.onDispose(batcher.dispose);
  return batcher;
});

/// Transport batching only. Disposed cards leave the queue before a fetch;
/// in-flight replies complete their original requests, never a replacement.
class _SnapshotBatcher {
  _SnapshotBatcher(this.repository);

  final GameRepository repository;
  final _pending = <String, Completer<Games?>>{};
  Timer? _timer;
  bool _paused = false;

  void setPaused(bool paused) {
    _paused = paused;
    if (paused) {
      _timer?.cancel();
      _timer = null;
    } else if (_pending.isNotEmpty) {
      _timer ??= Timer(const Duration(milliseconds: 100), _flush);
    }
  }

  Completer<Games?> request(String id) {
    final request = _pending.putIfAbsent(id, Completer<Games?>.new);
    if (!_paused) {
      _timer ??= Timer(const Duration(milliseconds: 100), _flush);
    }
    return request;
  }

  void cancel(String id, Completer<Games?> request) {
    if (identical(_pending[id], request)) {
      _pending.remove(id);
      request.complete(null);
    }
  }

  void _flush() {
    _timer = null;
    final requests = Map<String, Completer<Games?>>.of(_pending);
    _pending.clear();
    final ids = requests.keys.toList();
    for (var start = 0; start < ids.length; start += 16) {
      final end = start + 16 < ids.length ? start + 16 : ids.length;
      unawaited(_fetch(ids.sublist(start, end), requests));
    }
  }

  Future<void> _fetch(
    List<String> ids,
    Map<String, Completer<Games?>> requests,
  ) async {
    try {
      final games = await repository.getGamesByIds(ids);
      final byId = {for (final game in games) game.id: game};
      for (final id in ids) {
        requests[id]!.complete(byId[id]);
      }
    } catch (error, stack) {
      for (final id in ids) {
        requests[id]!.completeError(error, stack);
      }
    }
  }

  void dispose() {
    _timer?.cancel();
    for (final request in _pending.values) {
      request.complete(null);
    }
    _pending.clear();
  }
}
