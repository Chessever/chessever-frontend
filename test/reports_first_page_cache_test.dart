import 'dart:async';

import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/for_you/discovery/providers/reports_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Repository implements DiscoveryRepository {
  final requests =
      <
        ({
          AnalyzedGamesCursor? after,
          ReportGameType? gameType,
          Completer<AnalyzedGamesPage> result,
        })
      >[];

  @override
  Future<AnalyzedGamesPage> fetchAnalyzedGamesPage({
    int pageSize = 30,
    AnalyzedGamesCursor? after,
    DateTime? since,
    ReportGameType? gameType,
  }) {
    final result = Completer<AnalyzedGamesPage>();
    requests.add((after: after, gameType: gameType, result: result));
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected call');
}

GamesTourModel _game(String id) => GamesTourModel(
  gameId: id,
  whitePlayer: PlayerCard(
    name: 'White',
    federation: 'IN',
    title: 'GM',
    rating: 2700,
    countryCode: 'IN',
    team: null,
  ),
  blackPlayer: PlayerCard(
    name: 'Black',
    federation: 'IN',
    title: 'GM',
    rating: 2700,
    countryCode: 'IN',
    team: null,
  ),
  whiteTimeDisplay: '--:--',
  blackTimeDisplay: '--:--',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: GameStatus.whiteWins,
  roundId: 'round',
  tourId: 'tour',
);

void main() {
  late _Repository repository;
  late ProviderContainer container;

  void testCache(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      repository = _Repository();
      container = ProviderContainer(
        overrides: [discoveryRepositoryProvider.overrideWithValue(repository)],
      );
      try {
        await body(tester);
      } finally {
        container.dispose();
        await tester.pump(Duration.zero);
      }
    });
  }

  Future<void> flush(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(Duration.zero);
  }

  testCache('Discovery prefetch and opening Reports share one request', (
    tester,
  ) async {
    container.read(reportsFirstPageProvider);
    final visit = container.listen(reportsPaginationProvider, (_, __) {});
    expect(repository.requests, hasLength(1));
    repository.requests.single.result.complete(
      AnalyzedGamesPage(items: [_game('first')]),
    );
    await flush(tester);
    final state = container.read(reportsPaginationProvider);
    expect(state.items.single.gameId, 'first');
    expect(state.isLoading, isFalse);
    expect(repository.requests, hasLength(1));
    visit.close();
  });

  testCache('reopening uses cached cards, releases later pages, and expires', (
    tester,
  ) async {
    container.read(reportsFirstPageProvider);
    const cursor = (lastMoveTime: '2026-09-28T12:00:00Z', gameId: 'first');
    repository.requests.single.result.complete(
      AnalyzedGamesPage(items: [_game('first')], nextCursor: cursor),
    );
    await flush(tester);
    var visit = container.listen(reportsPaginationProvider, (_, __) {});
    await flush(tester);
    expect(repository.requests, hasLength(1));
    expect(container.read(reportsPaginationProvider).isLoading, isFalse);

    final firstNotifier = container.read(reportsPaginationProvider.notifier);
    unawaited(firstNotifier.loadNextPage());
    expect(repository.requests.last.after, cursor);
    repository.requests.last.result.complete(
      AnalyzedGamesPage(items: [_game('second')]),
    );
    await flush(tester);
    expect(container.read(reportsPaginationProvider).items, hasLength(2));
    visit.close();
    await flush(tester);
    expect(firstNotifier.mounted, isFalse);

    visit = container.listen(reportsPaginationProvider, (_, __) {});
    await flush(tester);
    expect(repository.requests, hasLength(2));
    expect(
      container.read(reportsPaginationProvider).items.single.gameId,
      'first',
    );
    expect(container.read(reportsPaginationProvider).hasMore, isTrue);
    visit.close();
    await flush(tester);

    await tester.pump(kReportsFirstPageMaxAge + const Duration(seconds: 1));
    await flush(tester);
    visit = container.listen(reportsPaginationProvider, (_, __) {});
    expect(repository.requests, hasLength(3));
    repository.requests.last.result.complete(
      const AnalyzedGamesPage(items: []),
    );
    await flush(tester);
    visit.close();
  });

  testCache('manual refresh bypasses and replaces the cached first page', (
    tester,
  ) async {
    final visit = container.listen(reportsPaginationProvider, (_, __) {});
    repository.requests.single.result.complete(
      AnalyzedGamesPage(items: [_game('old')]),
    );
    await flush(tester);
    final refresh = container
        .read(reportsPaginationProvider.notifier)
        .refresh();
    expect(repository.requests, hasLength(2));
    expect(
      container.read(reportsPaginationProvider).items.single.gameId,
      'old',
    );
    repository.requests.last.result.complete(
      AnalyzedGamesPage(items: [_game('new')]),
    );
    await refresh;
    await flush(tester);
    expect(
      container.read(reportsFirstPageProvider).requireValue.items.single.gameId,
      'new',
    );
    expect(
      container.read(reportsPaginationProvider).items.single.gameId,
      'new',
    );
    visit.close();
  });

  testCache('a failed background prefetch is not cached on the next visit', (
    tester,
  ) async {
    container.read(reportsFirstPageProvider);
    repository.requests.single.result.completeError(StateError('offline'));
    await flush(tester);
    final visit = container.listen(reportsPaginationProvider, (_, __) {});
    expect(repository.requests, hasLength(2));
    repository.requests.last.result.complete(
      AnalyzedGamesPage(items: [_game('online')]),
    );
    await flush(tester);
    expect(container.read(reportsPaginationProvider).error, isNull);
    expect(
      container.read(reportsPaginationProvider).items.single.gameId,
      'online',
    );
    visit.close();
  });
}
