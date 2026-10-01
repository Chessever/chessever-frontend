import 'dart:async';

import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/for_you/discovery/providers/reports_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(since, isNull);
    final result = Completer<AnalyzedGamesPage>();
    requests.add((after: after, gameType: gameType, result: result));
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected call');
}

AnalyzedGamesCursor _cursor(int n) =>
    (lastMoveTime: '2026-09-28T12:00:00Z', gameId: 'g$n');

GamesTourModel _game(int n) => GamesTourModel(
  gameId: 'g$n',
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

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _Repository repository;
  late ReportsPaginationNotifier notifier;

  setUp(() {
    repository = _Repository();
    notifier = ReportsPaginationNotifier(repository);
    addTearDown(() {
      if (notifier.mounted) notifier.dispose();
    });
  });

  Future<void> complete(int request, List<int> ids, {int? next}) async {
    repository.requests[request].result.complete(
      AnalyzedGamesPage(
        items: ids.map(_game).toList(),
        nextCursor: next == null ? null : _cursor(next),
      ),
    );
    await _flush();
  }

  test(
    'keeps appending past the old caps, requests once, stops only at the end',
    () async {
      for (var page = 0; page < 4; page++) {
        if (page > 0) unawaited(notifier.loadNextPage());
        await notifier
            .loadNextPage(); // A second near-bottom event is coalesced.
        expect(repository.requests, hasLength(page + 1));
        expect(
          repository.requests[page].after,
          page == 0 ? null : _cursor(page * 30),
        );
        await complete(
          page,
          List.generate(30, (index) => page * 30 + index),
          next: page == 3 ? null : (page + 1) * 30,
        );
      }
      expect(notifier.state.items, hasLength(120));
      expect(notifier.state.items.last.gameId, 'g119');
      expect(notifier.state.hasMore, isFalse);
      await notifier.loadNextPage();
      expect(repository.requests, hasLength(4));
    },
  );

  test(
    'an entirely filtered page advances its cursor instead of ending the list',
    () async {
      await complete(0, [], next: 30);
      expect(notifier.state.hasMore, isTrue);
      unawaited(notifier.loadNextPage());
      expect(repository.requests[1].after, _cursor(30));
      await complete(1, [31]);
      expect(notifier.state.items.single.gameId, 'g31');
    },
  );

  test('deduplicates a game that moved between pages', () async {
    await complete(0, [1, 2], next: 2);
    unawaited(notifier.loadNextPage());
    await complete(1, [2, 3]);
    expect(notifier.state.items.map((g) => g.gameId), ['g1', 'g2', 'g3']);
  });

  test(
    'page failure retains cards and retries the same cursor on demand',
    () async {
      await complete(0, [1, 2], next: 2);
      unawaited(notifier.loadNextPage());
      repository.requests[1].result.completeError(StateError('offline'));
      await _flush();
      expect(notifier.state.items, hasLength(2));
      expect(notifier.state.error, "Couldn't load more reports");
      await notifier.loadNextPage();
      expect(repository.requests, hasLength(2));
      unawaited(notifier.retry());
      expect(repository.requests[2].after, _cursor(2));
      await complete(2, [3]);
      expect(notifier.state.error, isNull);
      expect(notifier.state.items, hasLength(3));
    },
  );

  test('refresh replaces pages and ignores a late previous page', () async {
    await complete(0, [1, 2], next: 2);
    unawaited(notifier.loadNextPage());
    unawaited(notifier.refresh());
    expect(repository.requests[2].after, isNull);
    expect(notifier.state.items, hasLength(2));
    await complete(2, [9], next: 9);
    await complete(1, [3, 4], next: 4);
    expect(notifier.state.items.single.gameId, 'g9');
    unawaited(notifier.loadNextPage());
    expect(repository.requests[3].after, _cursor(9));
    await complete(3, [10]);
  });

  test(
    'failed refresh keeps old cards and retries from the beginning',
    () async {
      await complete(0, [1], next: 1);
      unawaited(notifier.refresh());
      repository.requests[1].result.completeError(StateError('offline'));
      await _flush();
      expect(notifier.state.items.single.gameId, 'g1');
      unawaited(notifier.retry());
      expect(repository.requests[2].after, isNull);
      await complete(2, [2]);
      expect(notifier.state.items.single.gameId, 'g2');
    },
  );

  test(
    'a non-advancing cursor becomes a retry state instead of a request loop',
    () async {
      await complete(0, [1], next: 1);
      unawaited(notifier.loadNextPage());
      await complete(1, [], next: 1);
      expect(notifier.state.error, isNotNull);
      await notifier.loadNextPage();
      expect(repository.requests, hasLength(2));
    },
  );

  test('late completion after leaving the screen is ignored', () async {
    notifier.dispose();
    await complete(0, [1]);
  });

  test(
    'a selected type is retained through pagination, refresh and retry',
    () async {
      notifier.dispose();
      repository = _Repository();
      notifier = ReportsPaginationNotifier(
        repository,
        gameType: ReportGameType.squeeze,
      );
      expect(repository.requests.single.gameType, ReportGameType.squeeze);
      await complete(0, [1], next: 1);
      unawaited(notifier.loadNextPage());
      expect(repository.requests[1].gameType, ReportGameType.squeeze);
      repository.requests[1].result.completeError(StateError('offline'));
      await _flush();
      unawaited(notifier.retry());
      expect(repository.requests[2].gameType, ReportGameType.squeeze);
      expect(repository.requests[2].after, _cursor(1));
      await complete(2, [2]);
      unawaited(notifier.refresh());
      expect(repository.requests[3].gameType, ReportGameType.squeeze);
      expect(repository.requests[3].after, isNull);
      await complete(3, [3]);
    },
  );

  test(
    'missing metadata support offers All without hiding older reports',
    () async {
      repository.requests.single.result.completeError(
        const ReportGameTypesUnavailable(),
      );
      await _flush();
      expect(notifier.state.error, contains('Choose All'));
      expect(notifier.state.isLoading, isFalse);
    },
  );
}
