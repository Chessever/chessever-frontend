import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/miniatures/providers/miniatures_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef _RequestHandler =
    Future<GamebaseMiniaturesPage> Function(_MiniaturesRequest request);

class _MiniaturesRequest {
  const _MiniaturesRequest({
    required this.filter,
    required this.limit,
    required this.offset,
  });

  final MiniatureGamesFilter filter;
  final int limit;
  final int offset;
}

class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository(this._handler)
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  final _RequestHandler _handler;
  final List<_MiniaturesRequest> requests = <_MiniaturesRequest>[];

  @override
  Future<GamebaseMiniaturesPage> getMiniatures({
    MiniatureGamesFilter filter = MiniatureGamesFilter.defaultFilter,
    int limit = 50,
    int offset = 0,
  }) {
    final request = _MiniaturesRequest(
      filter: filter,
      limit: limit,
      offset: offset,
    );
    requests.add(request);
    return _handler(request);
  }
}

void main() {
  group('miniaturesProvider', () {
    test('uses the recent-descending desktop baseline request', () async {
      final repository = _FakeGamebaseRepository(
        (request) => Future<GamebaseMiniaturesPage>.value(
          _page(ids: const <String>[], total: 0, offset: request.offset),
        ),
      );
      final container = _containerFor(repository);

      final value = await container.read(miniaturesProvider.future);

      expect(repository.requests, hasLength(1));
      final request = repository.requests.single;
      expect(request.offset, 0);
      expect(request.limit, kMiniaturesPageSize);
      expect(request.filter.window, MiniatureGamesWindow.all);
      expect(request.filter.sort, MiniatureGamesSort.recent);
      expect(request.filter.order, MiniatureGamesSortOrder.desc);
      expect(value.filter.sort, MiniatureGamesSort.recent);
      expect(value.filter.order, MiniatureGamesSortOrder.desc);
    });

    test('publishes a successful immutable first page', () async {
      final repository = _FakeGamebaseRepository(
        (_) => Future<GamebaseMiniaturesPage>.value(
          _page(ids: const <String>['a', 'b'], total: 3, offset: 0),
        ),
      );
      final container = _containerFor(repository);

      final value = await container.read(miniaturesProvider.future);

      expect(_ids(value), const <String>['a', 'b']);
      expect(value.total, 3);
      expect(value.nextOffset, 2);
      expect(value.hasMore, isTrue);
      expect(value.isLoadingMore, isFalse);
      expect(value.loadMoreFailure, isNull);
      expect(
        () => value.items.add(_miniature('mutated')),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        container.read(miniaturesProvider),
        isA<AsyncData<MiniaturesState>>(),
      );
    });

    test('paginates 0 to 30 and terminates at the server total', () async {
      final repository = _FakeGamebaseRepository((request) {
        if (request.offset == 0) {
          return Future<GamebaseMiniaturesPage>.value(
            _page(
              ids: List<String>.generate(30, (index) => 'game-$index'),
              total: 45,
              offset: 0,
            ),
          );
        }
        return Future<GamebaseMiniaturesPage>.value(
          _page(
            ids: List<String>.generate(15, (index) => 'game-${index + 30}'),
            total: 45,
            offset: 30,
          ),
        );
      });
      final container = _containerFor(repository);
      await container.read(miniaturesProvider.future);

      await container.read(miniaturesProvider.notifier).loadMore();

      final value = container.read(miniaturesProvider).requireValue;
      expect(repository.requests.map((request) => request.offset), <int>[
        0,
        30,
      ]);
      expect(value.items, hasLength(45));
      expect(value.total, 45);
      expect(value.nextOffset, 45);
      expect(value.hasMore, isFalse);

      await container.read(miniaturesProvider.notifier).loadMore();
      expect(repository.requests, hasLength(2));
    });

    test('merges pages by canonical game ID without reordering', () async {
      final repository = _FakeGamebaseRepository((request) {
        return Future<GamebaseMiniaturesPage>.value(
          request.offset == 0
              ? _page(ids: const <String>['a', 'b'], total: 4, offset: 0)
              : _page(ids: const <String>['b', 'c'], total: 4, offset: 2),
        );
      });
      final container = _containerFor(repository);
      await container.read(miniaturesProvider.future);

      await container.read(miniaturesProvider.notifier).loadMore();

      final value = container.read(miniaturesProvider).requireValue;
      expect(_ids(value), const <String>['a', 'b', 'c']);
      expect(value.nextOffset, 4);
      expect(value.hasMore, isFalse);
    });

    test('coalesces concurrent loadMore calls', () async {
      final nextPage = Completer<GamebaseMiniaturesPage>();
      final repository = _FakeGamebaseRepository((request) {
        if (request.offset == 0) {
          return Future<GamebaseMiniaturesPage>.value(
            _page(
              ids: List<String>.generate(30, (index) => 'game-$index'),
              total: 60,
              offset: 0,
            ),
          );
        }
        return nextPage.future;
      });
      final container = _containerFor(repository);
      await container.read(miniaturesProvider.future);
      final notifier = container.read(miniaturesProvider.notifier);

      final first = notifier.loadMore();
      final second = notifier.loadMore();

      expect(identical(first, second), isTrue);
      expect(repository.requests, hasLength(2));
      expect(
        container.read(miniaturesProvider).requireValue.isLoadingMore,
        isTrue,
      );

      nextPage.complete(
        _page(
          ids: List<String>.generate(30, (index) => 'game-${index + 30}'),
          total: 60,
          offset: 30,
        ),
      );
      await Future.wait<void>(<Future<void>>[first, second]);

      expect(
        container.read(miniaturesProvider).requireValue.items,
        hasLength(60),
      );
      expect(repository.requests, hasLength(2));
    });

    test('filter replacement resets and ignores the stale response', () async {
      final stalePage = Completer<GamebaseMiniaturesPage>();
      final replacementPage = Completer<GamebaseMiniaturesPage>();
      final repository = _FakeGamebaseRepository((request) {
        if (request.filter.sort == MiniatureGamesSort.moves) {
          return replacementPage.future;
        }
        if (request.offset == 30) return stalePage.future;
        return Future<GamebaseMiniaturesPage>.value(
          _page(
            ids: List<String>.generate(30, (index) => 'old-$index'),
            total: 60,
            offset: 0,
          ),
        );
      });
      final container = _containerFor(repository);
      await container.read(miniaturesProvider.future);
      final notifier = container.read(miniaturesProvider.notifier);

      final staleLoad = notifier.loadMore();
      const replacementFilter = MiniatureGamesFilter(
        sort: MiniatureGamesSort.moves,
        order: MiniatureGamesSortOrder.asc,
      );
      final replace = notifier.replaceFilter(replacementFilter);

      expect(repository.requests, hasLength(3));
      expect(repository.requests.last.offset, 0);
      expect(repository.requests.last.limit, kMiniaturesPageSize);
      expect(repository.requests.last.filter, same(replacementFilter));

      replacementPage.complete(
        _page(ids: const <String>['fresh'], total: 1, offset: 0),
      );
      await replace;

      stalePage.complete(
        _page(ids: const <String>['stale'], total: 60, offset: 30),
      );
      await staleLoad;

      final value = container.read(miniaturesProvider).requireValue;
      expect(_ids(value), const <String>['fresh']);
      expect(value.filter, same(replacementFilter));
      expect(value.nextOffset, 1);
      expect(value.hasMore, isFalse);
      expect(value.loadMoreFailure, isNull);
    });

    test('exposes a cold malformed response as typed AsyncError', () async {
      final repository = _FakeGamebaseRepository(
        (_) => Future<GamebaseMiniaturesPage>.error(
          const FormatException('malformed miniatures page'),
        ),
      );
      final container = _containerFor(repository);

      await expectLater(
        container.read(miniaturesProvider.future),
        throwsA(isA<FormatException>()),
      );

      final state = container.read(miniaturesProvider);
      expect(state, isA<AsyncError<MiniaturesState>>());
      expect(state.hasValue, isFalse);
      expect(state.error, isA<FormatException>());
    });

    test(
      'retains data on loadMore error and retries the same offset',
      () async {
        var laterPageAttempts = 0;
        final repository = _FakeGamebaseRepository((request) {
          if (request.offset == 0) {
            return Future<GamebaseMiniaturesPage>.value(
              _page(ids: const <String>['a', 'b'], total: 4, offset: 0),
            );
          }
          laterPageAttempts += 1;
          if (laterPageAttempts == 1) {
            return Future<GamebaseMiniaturesPage>.error(
              StateError('network unavailable'),
            );
          }
          return Future<GamebaseMiniaturesPage>.value(
            _page(ids: const <String>['c', 'd'], total: 4, offset: 2),
          );
        });
        final container = _containerFor(repository);
        await container.read(miniaturesProvider.future);
        final notifier = container.read(miniaturesProvider.notifier);

        await notifier.loadMore();

        var value = container.read(miniaturesProvider).requireValue;
        expect(_ids(value), const <String>['a', 'b']);
        expect(value.hasMore, isTrue);
        expect(value.nextOffset, 2);
        expect(value.isLoadingMore, isFalse);
        expect(value.loadMoreFailure, isNotNull);
        expect(value.loadMoreFailure!.error, isA<StateError>());
        expect(value.loadMoreFailure!.offset, 2);

        await notifier.loadMore();

        value = container.read(miniaturesProvider).requireValue;
        expect(repository.requests.map((request) => request.offset), <int>[
          0,
          2,
          2,
        ]);
        expect(_ids(value), const <String>['a', 'b', 'c', 'd']);
        expect(value.hasMore, isFalse);
        expect(value.loadMoreFailure, isNull);
      },
    );

    test('refresh replaces the previously loaded rows', () async {
      var callCount = 0;
      final repository = _FakeGamebaseRepository((request) {
        callCount += 1;
        return Future<GamebaseMiniaturesPage>.value(
          callCount == 1
              ? _page(ids: const <String>['old'], total: 1, offset: 0)
              : _page(
                ids: const <String>['new-a', 'new-b'],
                total: 2,
                offset: 0,
              ),
        );
      });
      final container = _containerFor(repository);
      await container.read(miniaturesProvider.future);

      await container.read(miniaturesProvider.notifier).refresh();

      final value = container.read(miniaturesProvider).requireValue;
      expect(repository.requests.map((request) => request.offset), <int>[0, 0]);
      expect(_ids(value), const <String>['new-a', 'new-b']);
      expect(value.total, 2);
      expect(value.nextOffset, 2);
      expect(value.hasMore, isFalse);
    });
  });
}

ProviderContainer _containerFor(GamebaseRepository repository) {
  final container = ProviderContainer(
    overrides: <Override>[
      gamebaseRepositoryProvider.overrideWithValue(repository),
    ],
  );
  final subscription = container.listen<AsyncValue<MiniaturesState>>(
    miniaturesProvider,
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(() {
    subscription.close();
    container.dispose();
  });
  return container;
}

GamebaseMiniaturesPage _page({
  required Iterable<String> ids,
  required int total,
  required int offset,
}) {
  return GamebaseMiniaturesPage(
    items: ids.map(_miniature).toList(growable: false),
    total: total,
    limit: kMiniaturesPageSize,
    offset: offset,
  );
}

GamebaseMiniature _miniature(String id) {
  return GamebaseMiniature(
    gameId: id,
    plyCount: 20,
    finalMoveNumber: 10,
    result: MiniatureGameResult.whiteWins,
    timeControl: MiniatureGameTimeControl.rapid,
    onlineStatus: MiniatureGameOnlineStatus.offline,
  );
}

List<String> _ids(MiniaturesState state) {
  return state.items.map((item) => item.canonicalGameId).toList();
}
