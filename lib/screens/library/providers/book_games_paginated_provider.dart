import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const kBookPageSize = 30;

class PaginatedBookState {
  final List<SavedAnalysis> games;
  final int totalCount;
  final bool hasMore;
  final bool isLoadingMore;

  const PaginatedBookState({
    this.games = const [],
    this.totalCount = 0,
    this.hasMore = true,
    this.isLoadingMore = false,
  });

  PaginatedBookState copyWith({
    List<SavedAnalysis>? games,
    int? totalCount,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return PaginatedBookState(
      games: games ?? this.games,
      totalCount: totalCount ?? this.totalCount,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// Key for the paginated book provider.
///
/// [folderId] identifies the folder; [isSubscribed] controls the query path.
/// [filter] + [search] are part of the identity so that changing the filter,
/// sort, or search term spawns a fresh provider instance that reloads from
/// page 0 server-side (and the old one auto-disposes). This is what makes
/// filter/sort/search correct across the WHOLE folder instead of just the
/// pages already loaded.
class BookPaginationKey {
  final String folderId;
  final bool isSubscribed;
  final GameFilter filter;
  final String search;

  const BookPaginationKey({
    required this.folderId,
    this.isSubscribed = false,
    required this.filter,
    this.search = '',
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookPaginationKey &&
          folderId == other.folderId &&
          isSubscribed == other.isSubscribed &&
          filter == other.filter &&
          search == other.search;

  @override
  int get hashCode => Object.hash(folderId, isSubscribed, filter, search);
}

/// Paginated book games provider.
///
/// Loads [kBookPageSize] games at a time. Supports infinite scroll via
/// [BookGamesNotifier.loadMore] and pull-to-refresh via [BookGamesNotifier.refresh].
final bookGamesPaginatedProvider = AutoDisposeAsyncNotifierProvider.family<
  BookGamesNotifier,
  PaginatedBookState,
  BookPaginationKey
>(BookGamesNotifier.new);

class BookGamesNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<PaginatedBookState, BookPaginationKey> {
  @override
  Future<PaginatedBookState> build(BookPaginationKey arg) async {
    final repo = ref.watch(libraryRepositoryProvider);
    return _loadPage(repo, arg, offset: 0);
  }

  Future<PaginatedBookState> _loadPage(
    LibraryRepository repo,
    BookPaginationKey key, {
    required int offset,
    PaginatedBookState? existing,
  }) async {
    final List<SavedAnalysis> page;
    final int count;

    if (key.isSubscribed) {
      final results = await Future.wait([
        repo.getSharedFolderAnalysesPaginated(
          folderId: key.folderId,
          filter: key.filter,
          search: key.search,
          limit: kBookPageSize,
          offset: offset,
        ),
        if (offset == 0)
          repo.getFilteredSharedFolderAnalysisCount(
            folderId: key.folderId,
            filter: key.filter,
            search: key.search,
          ),
      ]);
      page = results[0] as List<SavedAnalysis>;
      count = offset == 0 ? results[1] as int : (existing?.totalCount ?? 0);
    } else {
      final results = await Future.wait([
        repo.getSavedAnalysesPaginated(
          folderId: key.folderId,
          filter: key.filter,
          search: key.search,
          limit: kBookPageSize,
          offset: offset,
        ),
        if (offset == 0)
          repo.getFilteredAnalysisCountInFolder(
            folderId: key.folderId,
            filter: key.filter,
            search: key.search,
          ),
      ]);
      page = results[0] as List<SavedAnalysis>;
      count = offset == 0 ? results[1] as int : (existing?.totalCount ?? 0);
    }

    final List<SavedAnalysis> allGames =
        offset == 0 ? page : [...existing?.games ?? <SavedAnalysis>[], ...page];

    return PaginatedBookState(
      games: allGames,
      totalCount: count,
      hasMore: page.length >= kBookPageSize,
      isLoadingMore: false,
    );
  }

  /// Load the next page. No-op if already loading or no more pages.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    try {
      final repo = ref.read(libraryRepositoryProvider);
      final result = await _loadPage(
        repo,
        arg,
        offset: current.games.length,
        existing: current,
      );
      state = AsyncData(result);
    } catch (e, st) {
      // Restore previous state but stop loading indicator.
      state = AsyncData(current.copyWith(isLoadingMore: false, hasMore: false));
      // Re-throw for error handling upstream if needed.
      state = AsyncError(e, st);
    }
  }

  /// Full refresh — reloads from page 0.
  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(libraryRepositoryProvider);
      final result = await _loadPage(repo, arg, offset: 0);
      state = AsyncData(result);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
