import 'dart:async';

import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const kReportsFirstPageMaxAge = Duration(minutes: 2);

/// Discovery warms the real first page, including parsed cards, before a tap.
/// Only this page survives leaving Reports; the rest of the list is released.
/// An idle cache expires even when Discovery stays mounted, and failures are
/// released immediately so a later visit can retry.
final reportsFirstPageProvider = FutureProvider.autoDispose<AnalyzedGamesPage>((
  ref,
) async {
  final link = ref.keepAlive();
  final expiry = Timer(kReportsFirstPageMaxAge, link.close);
  ref.onDispose(expiry.cancel);
  try {
    return await ref
        .watch(discoveryRepositoryProvider)
        .fetchAnalyzedGamesPage();
  } catch (_) {
    expiry.cancel();
    link.close();
    rethrow;
  }
});

class ReportsPaginationState {
  const ReportsPaginationState({
    this.items = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.hasMore = true,
    this.error,
  });

  final List<GamesTourModel> items;
  final bool isLoading;
  final bool isRefreshing;
  final bool hasMore;
  final String? error;
}

final reportsGameTypeProvider = StateProvider.autoDispose<ReportGameType?>(
  (ref) => null,
);

final reportsPaginationProvider =
    StateNotifierProvider.autoDispose<
      ReportsPaginationNotifier,
      ReportsPaginationState
    >((ref) {
      final gameType = ref.watch(reportsGameTypeProvider);
      return ReportsPaginationNotifier(
        ref.watch(discoveryRepositoryProvider),
        gameType: gameType,
        firstPage: gameType == null
            ? ref.read(reportsFirstPageProvider.future)
            : null,
        reloadFirstPage: gameType == null
            ? () => ref.refresh(reportsFirstPageProvider.future)
            : null,
      );
    });

/// Like Miniatures, show newest days first and highest average ratings within
/// each day. Sort all loaded cards together so page boundaries do not split a
/// day's ranking; pagination keeps its original server order and cursor.
final reportsGamesProvider = Provider.autoDispose<List<GamesTourModel>>((ref) {
  final games = ref
      .watch(reportsPaginationProvider.select((state) => state.items))
      .toList(growable: false);
  games.sort((left, right) {
    final leftDay = _reportUtcDay(left.lastMoveTime);
    final rightDay = _reportUtcDay(right.lastMoveTime);
    if (leftDay != rightDay) {
      if (leftDay == null) return 1;
      if (rightDay == null) return -1;
      return rightDay.compareTo(leftDay);
    }
    final byRating = (discoveryAverageRating(right) ?? 0).compareTo(
      discoveryAverageRating(left) ?? 0,
    );
    if (byRating != 0) return byRating;
    return left.gameId.compareTo(right.gameId);
  });
  return List.unmodifiable(games);
});

int? _reportUtcDay(DateTime? date) {
  if (date == null) return null;
  final utc = date.toUtc();
  return utc.year * 10000 + utc.month * 100 + utc.day;
}

/// One in-flight page at a time. Refresh supersedes earlier requests without
/// letting a late response replace the fresh list or advance its cursor.
class ReportsPaginationNotifier extends StateNotifier<ReportsPaginationState> {
  ReportsPaginationNotifier(
    this._repository, {
    Future<AnalyzedGamesPage>? firstPage,
    this.reloadFirstPage,
    this.gameType,
  }) : super(const ReportsPaginationState()) {
    unawaited(_fetch(reset: true, firstPage: firstPage));
  }

  final DiscoveryRepository _repository;
  final ReportGameType? gameType;
  final Future<AnalyzedGamesPage> Function()? reloadFirstPage;
  AnalyzedGamesCursor? _cursor;
  final Set<String> _seenIds = {};
  int _request = 0;
  bool _retryRefresh = true;

  Future<void> refresh() => _fetch(reset: true);

  Future<void> loadNextPage() async {
    if (!mounted || state.isLoading || !state.hasMore || state.error != null) {
      return;
    }
    await _fetch(reset: false);
  }

  Future<void> retry() async {
    if (!mounted || state.isLoading || state.error == null) return;
    await _fetch(reset: _retryRefresh);
  }

  Future<void> _fetch({
    required bool reset,
    Future<AnalyzedGamesPage>? firstPage,
  }) async {
    if (!mounted) return;
    final request = ++_request;
    final after = reset ? null : _cursor;
    _retryRefresh = reset;
    state = ReportsPaginationState(
      items: state.items,
      isLoading: true,
      isRefreshing: reset && state.items.isNotEmpty,
      hasMore: state.hasMore,
    );
    try {
      final page =
          await (firstPage ??
              (reset && reloadFirstPage != null
                  ? reloadFirstPage!()
                  : _repository.fetchAnalyzedGamesPage(
                      after: after,
                      gameType: gameType,
                    )));
      if (!mounted || request != _request) return;
      if (page.nextCursor != null && page.nextCursor == after) {
        throw StateError('Report pagination did not advance');
      }
      if (reset) _seenIds.clear();
      final items = <GamesTourModel>[
        if (!reset) ...state.items,
        for (final game in page.items)
          if (_seenIds.add(game.gameId)) game,
      ];
      _cursor = page.nextCursor;
      state = ReportsPaginationState(
        items: List.unmodifiable(items),
        hasMore: page.nextCursor != null,
      );
    } catch (error) {
      if (!mounted || request != _request) return;
      state = ReportsPaginationState(
        items: state.items,
        hasMore: state.hasMore,
        error: error is ReportGameTypesUnavailable
            ? 'Report filters are not available yet. Choose All to browse reports.'
            : state.items.isEmpty
            ? "Couldn't load reports"
            : reset
            ? "Couldn't refresh reports"
            : "Couldn't load more reports",
      );
    }
  }
}
