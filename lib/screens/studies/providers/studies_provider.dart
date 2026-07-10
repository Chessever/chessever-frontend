import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const int kStudiesPageSize = 30;

/// The public Studies feed starts with Gamebase's credibility score ranking.
const GamebaseStudiesFilter kDefaultStudiesFilter = GamebaseStudiesFilter(
  sort: GamebaseStudySort.score,
  order: GamebaseStudySortOrder.desc,
);

/// A failure limited to a later page request.
///
/// The successfully loaded Studies remain usable while the failed offset can
/// be retried independently.
@immutable
class StudiesLoadMoreFailure {
  const StudiesLoadMoreFailure({
    required this.error,
    required this.stackTrace,
    required this.offset,
  });

  final Object error;
  final StackTrace stackTrace;
  final int offset;
}

/// Successful Studies feed state.
///
/// Cold loading and cold failure are represented by the provider's outer
/// [AsyncValue]. An empty first page is a successful state with no [items].
@immutable
class StudiesState {
  StudiesState({
    required Iterable<GamebaseStudySummary> items,
    required this.filter,
    required this.total,
    required this.nextOffset,
    required this.hasMore,
    this.isLoadingMore = false,
    this.loadMoreFailure,
  }) : items = List<GamebaseStudySummary>.unmodifiable(items);

  final List<GamebaseStudySummary> items;
  final GamebaseStudiesFilter filter;
  final int total;
  final int nextOffset;
  final bool hasMore;
  final bool isLoadingMore;
  final StudiesLoadMoreFailure? loadMoreFailure;

  bool get isEmpty => items.isEmpty;

  StudiesState copyWith({
    Iterable<GamebaseStudySummary>? items,
    GamebaseStudiesFilter? filter,
    int? total,
    int? nextOffset,
    bool? hasMore,
    bool? isLoadingMore,
    StudiesLoadMoreFailure? loadMoreFailure,
    bool clearLoadMoreFailure = false,
  }) {
    return StudiesState(
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

final studiesProvider =
    AutoDisposeAsyncNotifierProvider<StudiesNotifier, StudiesState>(
      StudiesNotifier.new,
    );

/// Metadata-only Study detail.
///
/// The repository contract deliberately exposes no mirrored chapter PGN, so
/// consumers cannot use this provider to open a chapter in-app.
final studyDetailProvider = FutureProvider.autoDispose
    .family<GamebaseStudyDetail, String>((ref, lichessStudyId) {
      final normalizedId = lichessStudyId.trim();
      if (normalizedId.isEmpty) {
        throw ArgumentError.value(
          lichessStudyId,
          'lichessStudyId',
          'Must not be empty.',
        );
      }
      return ref.watch(gamebaseRepositoryProvider).getStudy(normalizedId);
    });

class StudiesNotifier extends AutoDisposeAsyncNotifier<StudiesState> {
  GamebaseStudiesFilter _activeFilter = kDefaultStudiesFilter;
  Future<void>? _loadMoreOperation;
  int _generation = 0;
  bool _isDisposed = false;

  @override
  Future<StudiesState> build() async {
    _isDisposed = false;
    _generation += 1;

    // Riverpod 2.6 does not expose Ref.mounted. Disposal plus a monotonic
    // generation prevents an obsolete pagination response from publishing.
    ref.onDispose(() {
      _isDisposed = true;
      _generation += 1;
      _loadMoreOperation = null;
    });

    final repository = ref.watch(gamebaseRepositoryProvider);
    final filter = _activeFilter;
    final page = await repository.getStudies(
      filter: filter,
      limit: kStudiesPageSize,
      offset: 0,
    );

    return _stateFromFirstPage(page, filter);
  }

  /// Refresh the active credibility-ranked query from offset zero.
  Future<void> refresh() => _rebuildFirstPage();

  /// Replace the complete server filter and reset pagination.
  Future<void> replaceFilter(GamebaseStudiesFilter filter) {
    _activeFilter = filter;
    return _rebuildFirstPage();
  }

  Future<void> setFilter(GamebaseStudiesFilter filter) => replaceFilter(filter);

  Future<void> resetFilter() => replaceFilter(kDefaultStudiesFilter);

  /// Fetch the next server page, coalescing simultaneous threshold events.
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
    // Make every in-flight pagination request stale immediately, before the
    // invalidated provider's next build begins.
    _generation += 1;
    _loadMoreOperation = null;
    ref.invalidateSelf();
    return future.then<void>((_) {});
  }

  Future<void> _performLoadMore(
    StudiesState current,
    int requestGeneration,
  ) async {
    state = AsyncData(
      current.copyWith(isLoadingMore: true, clearLoadMoreFailure: true),
    );

    try {
      final page = await ref
          .read(gamebaseRepositoryProvider)
          .getStudies(
            filter: current.filter,
            limit: kStudiesPageSize,
            offset: current.nextOffset,
          );
      if (!_isCurrent(requestGeneration)) return;

      state = AsyncData(
        StudiesState(
          items: _mergeStudiesByCanonicalId(current.items, page.items),
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
          loadMoreFailure: StudiesLoadMoreFailure(
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

StudiesState _stateFromFirstPage(
  GamebaseStudiesPage page,
  GamebaseStudiesFilter filter,
) {
  return StudiesState(
    items: _mergeStudiesByCanonicalId(
      const <GamebaseStudySummary>[],
      page.items,
    ),
    filter: filter,
    total: page.total,
    nextOffset: page.nextOffset,
    hasMore: page.hasMore,
  );
}

List<GamebaseStudySummary> _mergeStudiesByCanonicalId(
  Iterable<GamebaseStudySummary> existing,
  Iterable<GamebaseStudySummary> incoming,
) {
  final merged = <GamebaseStudySummary>[];
  final seenIds = <String>{};

  for (final study in existing.followedBy(incoming)) {
    if (seenIds.add(study.canonicalStudyId)) merged.add(study);
  }

  return merged;
}
