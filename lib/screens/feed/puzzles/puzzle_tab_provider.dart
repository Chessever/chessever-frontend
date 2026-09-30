import 'dart:async';

import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/race/puzzle_rating_range.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Puzzle tab: an endless stream of puzzles, one per page, the way the
/// Feed tab is an endless stream of games.
///
/// Opens on [FeedPuzzleRepository.load] (the cache first, so it is instant
/// on every launch after the first) and grows by [loadMore] as the viewer
/// nears the end. A new difficulty starts it over inside the new range.
final puzzleTabProvider =
    AsyncNotifierProvider<PuzzleTabNotifier, List<FeedPuzzle>>(
      PuzzleTabNotifier.new,
    );

class PuzzleTabNotifier extends AsyncNotifier<List<FeedPuzzle>> {
  bool _loadingMore = false;

  /// True once a page came back empty; cleared by a refresh.
  bool _exhausted = false;
  int _generation = 0;

  @override
  Future<List<FeedPuzzle>> build() async {
    final generation = ++_generation;
    _loadingMore = false;
    _exhausted = false;
    final repository = ref.watch(feedPuzzleRepositoryProvider);
    ref.listen<PuzzleRatingRange>(puzzleRatingRangeProvider, (previous, next) {
      if (previous == next) return;
      unawaited(
        repository
            .retainWithin(next.min, next.max)
            .then((_) => ref.invalidateSelf()),
      );
    });
    final first = await repository.load();
    if (generation != _generation) return first;
    if (first.length < 3) unawaited(loadMore());
    return first;
  }

  /// Appends the next page. Safe to call repeatedly; no-ops while loading.
  Future<void> loadMore() async {
    if (_loadingMore || _exhausted) return;
    final generation = _generation;
    _loadingMore = true;
    try {
      if (!state.hasValue) await future;
      final current = state.valueOrNull ?? const <FeedPuzzle>[];
      final more = await ref.read(feedPuzzleRepositoryProvider).loadMore({
        for (final p in current) p.id,
      });
      if (generation != _generation) return;
      if (more.isEmpty) {
        _exhausted = true;
        return;
      }
      final latest = state.valueOrNull ?? current;
      final ids = {for (final p in latest) p.id};
      state = AsyncData(
        List.unmodifiable([
          ...latest,
          for (final p in more)
            if (ids.add(p.id)) p,
        ]),
      );
    } catch (error) {
      debugPrint('[PuzzleTab] loadMore failed: $error');
    } finally {
      if (generation == _generation) _loadingMore = false;
    }
  }

  /// Pull-to-refresh: a new set of puzzles the viewer has not finished.
  /// The current list stays until the new one is in.
  Future<void> refresh() async {
    final generation = ++_generation;
    _loadingMore = false;
    _exhausted = false;
    final repository = ref.read(feedPuzzleRepositoryProvider);
    final shown = <String>{
      for (final p in state.valueOrNull ?? const <FeedPuzzle>[]) p.id,
    };
    var fresh = await repository.loadMore(shown);
    if (fresh.isEmpty) fresh = await repository.load();
    if (generation != _generation) return;
    if (fresh.isEmpty) throw StateError('No new puzzles');
    state = AsyncData(List.unmodifiable(fresh));
  }
}
