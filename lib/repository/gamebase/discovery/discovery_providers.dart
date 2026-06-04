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
  const StudiesQuery({this.sort = StudiesSort.score, this.q = ''});

  final StudiesSort sort;
  final String q;

  StudiesQuery copyWith({StudiesSort? sort, String? q}) =>
      StudiesQuery(sort: sort ?? this.sort, q: q ?? this.q);

  @override
  bool operator ==(Object other) =>
      other is StudiesQuery && other.sort == sort && other.q == q;

  @override
  int get hashCode => Object.hash(sort, q);
}

class StudiesQueryNotifier extends StateNotifier<StudiesQuery> {
  StudiesQueryNotifier() : super(const StudiesQuery());

  void setSort(StudiesSort sort) => state = state.copyWith(sort: sort);
  void setSearch(String q) => state = state.copyWith(q: q);
}

final studiesQueryProvider =
    StateNotifierProvider<StudiesQueryNotifier, StudiesQuery>(
      (ref) => StudiesQueryNotifier(),
    );

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
  });

  final MiniatureWindow window;
  final MiniatureSort sort;

  MiniaturesQuery copyWith({MiniatureWindow? window, MiniatureSort? sort}) =>
      MiniaturesQuery(window: window ?? this.window, sort: sort ?? this.sort);

  @override
  bool operator ==(Object other) =>
      other is MiniaturesQuery && other.window == window && other.sort == sort;

  @override
  int get hashCode => Object.hash(window, sort);
}

class MiniaturesQueryNotifier extends StateNotifier<MiniaturesQuery> {
  MiniaturesQueryNotifier() : super(const MiniaturesQuery());

  void setWindow(MiniatureWindow window) => state = state.copyWith(window: window);
  void setSort(MiniatureSort sort) => state = state.copyWith(sort: sort);
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
      );
    });
