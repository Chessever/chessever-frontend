import 'package:chessever2/repository/gamebase/discovery/discovery_models.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ── Studies ─────────────────────────────────────────────────────────────

/// Sort key for the Studies list. Matches the API enum.
enum StudiesSort { score, recent, name, chapters, created }

extension StudiesSortX on StudiesSort {
  String get api => name; // score|recent|name|chapters|created
  String get label => switch (this) {
    StudiesSort.score => 'Best quality',
    StudiesSort.recent => 'Recently updated',
    StudiesSort.name => 'Name',
    StudiesSort.chapters => 'Chapters',
    StudiesSort.created => 'Newest',
  };
}

class StudiesQuery {
  const StudiesQuery({
    this.sort = StudiesSort.score,
    this.q = '',
    this.ecoCategories = const <String>{},
    this.variants = const <String>{},
    this.chapterModes = const <String>{},
    this.gamebook,
    this.hasAnnotations,
  });

  final StudiesSort sort;
  final String q;
  final Set<String> ecoCategories;
  final Set<String> variants;
  final Set<String> chapterModes;
  final bool? gamebook;
  final bool? hasAnnotations;

  int get activeFilterCount =>
      ecoCategories.length +
      variants.length +
      chapterModes.length +
      (gamebook != null ? 1 : 0) +
      (hasAnnotations != null ? 1 : 0);

  bool get hasFilters => activeFilterCount > 0;

  /// Backend query params for the v1.4.0 study filters (comma-joined multis).
  Map<String, dynamic> filterParams() => {
    if (ecoCategories.isNotEmpty) 'ecoCategory': ecoCategories.join(','),
    if (variants.isNotEmpty) 'variant': variants.join(','),
    if (chapterModes.isNotEmpty) 'chapterMode': chapterModes.join(','),
    if (gamebook != null) 'gamebook': gamebook,
    if (hasAnnotations != null) 'hasAnnotations': hasAnnotations,
  };

  @override
  bool operator ==(Object other) =>
      other is StudiesQuery &&
      other.sort == sort &&
      other.q == q &&
      _setEq(other.ecoCategories, ecoCategories) &&
      _setEq(other.variants, variants) &&
      _setEq(other.chapterModes, chapterModes) &&
      other.gamebook == gamebook &&
      other.hasAnnotations == hasAnnotations;

  @override
  int get hashCode => Object.hash(
    sort,
    q,
    Object.hashAllUnordered(ecoCategories),
    Object.hashAllUnordered(variants),
    Object.hashAllUnordered(chapterModes),
    gamebook,
    hasAnnotations,
  );
}

bool _setEq(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

class StudiesQueryNotifier extends StateNotifier<StudiesQuery> {
  StudiesQueryNotifier() : super(const StudiesQuery());

  void setSort(StudiesSort sort) => state = StudiesQuery(
    sort: sort,
    q: state.q,
    ecoCategories: state.ecoCategories,
    variants: state.variants,
    chapterModes: state.chapterModes,
    gamebook: state.gamebook,
    hasAnnotations: state.hasAnnotations,
  );

  void setSearch(String q) => state = StudiesQuery(
    sort: state.sort,
    q: q,
    ecoCategories: state.ecoCategories,
    variants: state.variants,
    chapterModes: state.chapterModes,
    gamebook: state.gamebook,
    hasAnnotations: state.hasAnnotations,
  );

  /// Replaces the whole filter set (used by the filter sheet's Apply).
  void applyFilters({
    required Set<String> ecoCategories,
    required Set<String> variants,
    required Set<String> chapterModes,
    required bool? gamebook,
    required bool? hasAnnotations,
  }) {
    state = StudiesQuery(
      sort: state.sort,
      q: state.q,
      ecoCategories: ecoCategories,
      variants: variants,
      chapterModes: chapterModes,
      gamebook: gamebook,
      hasAnnotations: hasAnnotations,
    );
  }

  void clearFilters() => state = StudiesQuery(sort: state.sort, q: state.q);
}

final studiesQueryProvider =
    StateNotifierProvider<StudiesQueryNotifier, StudiesQuery>(
      (ref) => StudiesQueryNotifier(),
    );

final studyFacetsProvider = FutureProvider.autoDispose<StudyFacets>((ref) async {
  final repo = ref.watch(gamebaseRepositoryProvider);
  return repo.getStudyFacets();
});

/// The studies list for the active query. `score`/`recent` default to desc
/// (best/newest first); `name` reads better ascending.
final studiesListProvider =
    FutureProvider.autoDispose<PagedResult<LichessStudy>>((ref) async {
      final query = ref.watch(studiesQueryProvider);
      final repo = ref.watch(gamebaseRepositoryProvider);
      final order = query.sort == StudiesSort.name ? 'asc' : 'desc';
      return repo.listStudies(
        sort: query.sort.api,
        order: order,
        q: query.q,
        limit: 50,
        filters: query.filterParams(),
      );
    });

final studyDetailProvider = FutureProvider.autoDispose
    .family<LichessStudyDetail?, String>((ref, studyId) async {
      final repo = ref.watch(gamebaseRepositoryProvider);
      return repo.getStudy(studyId);
    });

// ── Miniatures ──────────────────────────────────────────────────────────

enum MiniatureWindow { today, week, all }

extension MiniatureWindowX on MiniatureWindow {
  String get api => name; // today|week|all
  String get label => switch (this) {
    MiniatureWindow.today => 'Today',
    MiniatureWindow.week => 'Week',
    MiniatureWindow.all => 'All time',
  };
}

enum MiniatureSort { rating, moves, recent }

extension MiniatureSortX on MiniatureSort {
  String get api => name; // rating|moves|recent
  String get label => switch (this) {
    MiniatureSort.rating => 'Strongest',
    MiniatureSort.moves => 'Fewest moves',
    MiniatureSort.recent => 'Most recent',
  };
}

class MiniaturesQuery {
  const MiniaturesQuery({
    this.window = MiniatureWindow.all,
    this.sort = MiniatureSort.rating,
    this.results = const <String>{},
    this.timeControls = const <String>{},
    this.ecoCategories = const <String>{},
  });

  final MiniatureWindow window;
  final MiniatureSort sort;
  final Set<String> results; // W / B
  final Set<String> timeControls; // CLASSICAL / RAPID / BLITZ
  final Set<String> ecoCategories; // A-E

  int get activeFilterCount =>
      results.length + timeControls.length + ecoCategories.length;

  bool get hasFilters => activeFilterCount > 0;

  Map<String, dynamic> filterParams() => {
    if (results.isNotEmpty) 'result': results.join(','),
    if (timeControls.isNotEmpty) 'timeControl': timeControls.join(','),
    if (ecoCategories.isNotEmpty) 'ecoCategory': ecoCategories.join(','),
  };

  @override
  bool operator ==(Object other) =>
      other is MiniaturesQuery &&
      other.window == window &&
      other.sort == sort &&
      _setEq(other.results, results) &&
      _setEq(other.timeControls, timeControls) &&
      _setEq(other.ecoCategories, ecoCategories);

  @override
  int get hashCode => Object.hash(
    window,
    sort,
    Object.hashAllUnordered(results),
    Object.hashAllUnordered(timeControls),
    Object.hashAllUnordered(ecoCategories),
  );
}

class MiniaturesQueryNotifier extends StateNotifier<MiniaturesQuery> {
  MiniaturesQueryNotifier() : super(const MiniaturesQuery());

  void setWindow(MiniatureWindow window) => state = MiniaturesQuery(
    window: window,
    sort: state.sort,
    results: state.results,
    timeControls: state.timeControls,
    ecoCategories: state.ecoCategories,
  );

  void setSort(MiniatureSort sort) => state = MiniaturesQuery(
    window: state.window,
    sort: sort,
    results: state.results,
    timeControls: state.timeControls,
    ecoCategories: state.ecoCategories,
  );

  void applyFilters({
    required Set<String> results,
    required Set<String> timeControls,
    required Set<String> ecoCategories,
  }) {
    state = MiniaturesQuery(
      window: state.window,
      sort: state.sort,
      results: results,
      timeControls: timeControls,
      ecoCategories: ecoCategories,
    );
  }

  void clearFilters() =>
      state = MiniaturesQuery(window: state.window, sort: state.sort);
}

final miniaturesQueryProvider =
    StateNotifierProvider<MiniaturesQueryNotifier, MiniaturesQuery>(
      (ref) => MiniaturesQueryNotifier(),
    );

/// `moves` sorts ascending (fewest first) by default; others descending.
final miniaturesListProvider =
    FutureProvider.autoDispose<PagedResult<Miniature>>((ref) async {
      final query = ref.watch(miniaturesQueryProvider);
      final repo = ref.watch(gamebaseRepositoryProvider);
      final order = query.sort == MiniatureSort.moves ? 'asc' : 'desc';
      return repo.listMiniatures(
        window: query.window.api,
        sort: query.sort.api,
        order: order,
        limit: 50,
        filters: query.filterParams(),
      );
    });
