import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Active query for the Miniatures screen (window + sort + search + filters).
final miniaturesFilterProvider = StateProvider.autoDispose<MiniatureGamesFilter>(
  (ref) => MiniatureGamesFilter.defaultFilter,
);

/// Total number of miniatures in the community index (unfiltered).
/// Backs the "N miniatures" subtitle on the Library card.
final miniaturesTotalCountProvider = FutureProvider<int>((ref) async {
  final repo = ref.read(gamebaseRepositoryProvider);
  final page = await repo.getMiniatures(limit: 1);
  return page.total;
});

class MiniaturesPaginationState {
  const MiniaturesPaginationState({
    this.items = const <GamebaseMiniature>[],
    this.totalCount = 0,
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  final List<GamebaseMiniature> items;
  final int totalCount;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  MiniaturesPaginationState copyWith({
    List<GamebaseMiniature>? items,
    int? totalCount,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return MiniaturesPaginationState(
      items: items ?? this.items,
      totalCount: totalCount ?? this.totalCount,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

/// Offset-paginated miniatures for the active filter. The provider is
/// recreated whenever [miniaturesFilterProvider] changes, so each notifier
/// serves exactly one query.
final miniaturesPaginatedProvider = StateNotifierProvider.autoDispose<
  MiniaturesPaginationNotifier,
  MiniaturesPaginationState
>((ref) {
  final filter = ref.watch(miniaturesFilterProvider);
  return MiniaturesPaginationNotifier(ref, filter);
});

class MiniaturesPaginationNotifier
    extends StateNotifier<MiniaturesPaginationState> {
  MiniaturesPaginationNotifier(this._ref, this._filter)
    : super(const MiniaturesPaginationState(isLoading: true)) {
    _fetchPage(reset: true);
  }

  static const int _pageSize = 50;

  final Ref _ref;
  final MiniatureGamesFilter _filter;
  int _requestSeq = 0;

  Future<void> refresh() => _fetchPage(reset: true);

  Future<void> loadNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    await _fetchPage(reset: false);
  }

  Future<void> _fetchPage({required bool reset}) async {
    final seq = ++_requestSeq;
    final offset = reset ? 0 : state.items.length;
    state = state.copyWith(isLoading: true, error: null);

    try {
      final repo = _ref.read(gamebaseRepositoryProvider);
      final page = await repo.getMiniatures(
        filter: _filter,
        limit: _pageSize,
        offset: offset,
      );
      if (!mounted || seq != _requestSeq) return;

      final items =
          reset
              ? page.items
              : <GamebaseMiniature>[...state.items, ...page.items];
      state = state.copyWith(
        items: items,
        totalCount: page.total,
        isLoading: false,
        hasMore: items.length < page.total && page.items.isNotEmpty,
      );
    } catch (e, st) {
      talker.handle(e, st);
      if (!mounted || seq != _requestSeq) return;
      state = state.copyWith(
        isLoading: false,
        // Keep already-loaded rows; surface the error only for the empty case.
        hasMore: false,
        error: e.toString(),
      );
    }
  }
}
