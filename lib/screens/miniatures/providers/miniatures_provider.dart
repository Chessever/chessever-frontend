import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const int kMiniaturesPageSize = 30;

const MiniatureGamesFilter kDefaultMiniaturesFilter = MiniatureGamesFilter(
  sort: MiniatureGamesSort.recent,
  order: MiniatureGamesSortOrder.desc,
);

/// A failure limited to fetching a later page.
///
/// Keeping this in [MiniaturesState] lets the UI offer a retry without losing
/// the rows that were already loaded successfully.
class MiniaturesLoadMoreFailure {
  const MiniaturesLoadMoreFailure({
    required this.error,
    required this.stackTrace,
    required this.offset,
  });

  final Object error;
  final StackTrace stackTrace;
  final int offset;
}

class MiniaturesState {
  MiniaturesState({
    required Iterable<GamebaseMiniature> items,
    required this.filter,
    required this.total,
    required this.nextOffset,
    required this.hasMore,
    this.isLoadingMore = false,
    this.loadMoreFailure,
  }) : items = List<GamebaseMiniature>.unmodifiable(items);

  final List<GamebaseMiniature> items;
  final MiniatureGamesFilter filter;
  final int total;
  final int nextOffset;
  final bool hasMore;
  final bool isLoadingMore;
  final MiniaturesLoadMoreFailure? loadMoreFailure;

  MiniaturesState copyWith({
    Iterable<GamebaseMiniature>? items,
    MiniatureGamesFilter? filter,
    int? total,
    int? nextOffset,
    bool? hasMore,
    bool? isLoadingMore,
    MiniaturesLoadMoreFailure? loadMoreFailure,
    bool clearLoadMoreFailure = false,
  }) {
    return MiniaturesState(
      items: items ?? this.items,
      filter: filter ?? this.filter,
      total: total ?? this.total,
      nextOffset: nextOffset ?? this.nextOffset,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreFailure:
          clearLoadMoreFailure ? null : loadMoreFailure ?? this.loadMoreFailure,
    );
  }
}

final miniaturesProvider =
    AutoDisposeAsyncNotifierProvider<MiniaturesNotifier, MiniaturesState>(
      MiniaturesNotifier.new,
    );

class MiniaturesNotifier extends AutoDisposeAsyncNotifier<MiniaturesState> {
  MiniatureGamesFilter _activeFilter = kDefaultMiniaturesFilter;
  Future<void>? _loadMoreOperation;
  int _generation = 0;
  bool _isDisposed = false;

  @override
  Future<MiniaturesState> build() async {
    _isDisposed = false;
    _generation += 1;

    // Riverpod 2.6 has no public Ref.mounted. This flag and generation protect
    // mutation methods across both auto-disposal and notifier rebuilds.
    ref.onDispose(() {
      _isDisposed = true;
      _generation += 1;
      _loadMoreOperation = null;
    });

    final repository = ref.watch(gamebaseRepositoryProvider);
    final filter = _activeFilter;
    final page = await repository.getMiniatures(
      filter: filter,
      limit: kMiniaturesPageSize,
      offset: 0,
    );

    // Riverpod cancels the build subscription when this provider rebuilds or
    // disposes, so an obsolete return value is never published.
    return _stateFromFirstPage(page, filter);
  }

  /// Pull-to-refresh the active filter from offset zero.
  Future<void> refresh() => _rebuildFirstPage();

  /// Replace the complete server filter and reset pagination to offset zero.
  Future<void> replaceFilter(MiniatureGamesFilter filter) {
    _activeFilter = filter;
    return _rebuildFirstPage();
  }

  /// Convenience alias for callers that model filter replacement as a setter.
  Future<void> setFilter(MiniatureGamesFilter filter) => replaceFilter(filter);

  Future<void> resetFilter() => replaceFilter(kDefaultMiniaturesFilter);

  /// Fetch the next server page, coalescing concurrent calls into one future.
  Future<void> loadMore() {
    final existingOperation = _loadMoreOperation;
    if (existingOperation != null) return existingOperation;

    final current = state.valueOrNull;
    if (current == null || current.isLoadingMore || !current.hasMore) {
      return Future<void>.value();
    }

    final requestGeneration = _generation;
    late final Future<void> operation;
    operation = _performLoadMore(current, requestGeneration).whenComplete(() {
      if (identical(_loadMoreOperation, operation)) {
        _loadMoreOperation = null;
      }
    });
    _loadMoreOperation = operation;
    return operation;
  }

  Future<void> _rebuildFirstPage() {
    // Invalidating the notifier cancels any older build future before build()
    // runs again. The notifier instance is retained, including _activeFilter.
    ref.invalidateSelf();
    return future.then<void>((_) {});
  }

  Future<void> _performLoadMore(
    MiniaturesState current,
    int requestGeneration,
  ) async {
    state = AsyncData(
      current.copyWith(isLoadingMore: true, clearLoadMoreFailure: true),
    );

    try {
      final page = await ref
          .read(gamebaseRepositoryProvider)
          .getMiniatures(
            filter: current.filter,
            limit: kMiniaturesPageSize,
            offset: current.nextOffset,
          );
      if (!_isCurrent(requestGeneration)) return;

      state = AsyncData(
        MiniaturesState(
          items: _mergeByCanonicalId(current.items, page.items),
          filter: current.filter,
          total: page.total,
          nextOffset: page.nextOffset,
          hasMore: page.hasMore,
        ),
      );
    } catch (error, stackTrace) {
      if (!_isCurrent(requestGeneration)) return;

      state = AsyncData(
        current.copyWith(
          isLoadingMore: false,
          loadMoreFailure: MiniaturesLoadMoreFailure(
            error: error,
            stackTrace: stackTrace,
            offset: current.nextOffset,
          ),
        ),
      );
    }
  }

  bool _isCurrent(int requestGeneration) {
    return !_isDisposed && requestGeneration == _generation;
  }
}

MiniaturesState _stateFromFirstPage(
  GamebaseMiniaturesPage page,
  MiniatureGamesFilter filter,
) {
  return MiniaturesState(
    items: _mergeByCanonicalId(const <GamebaseMiniature>[], page.items),
    filter: filter,
    total: page.total,
    nextOffset: page.nextOffset,
    hasMore: page.hasMore,
  );
}

List<GamebaseMiniature> _mergeByCanonicalId(
  Iterable<GamebaseMiniature> existing,
  Iterable<GamebaseMiniature> incoming,
) {
  final merged = <GamebaseMiniature>[];
  final seenIds = <String>{};

  for (final item in existing.followedBy(incoming)) {
    if (seenIds.add(item.canonicalGameId)) merged.add(item);
  }

  return merged;
}
