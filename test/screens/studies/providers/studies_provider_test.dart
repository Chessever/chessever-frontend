import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/studies/providers/studies_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef _StudiesHandler =
    Future<GamebaseStudiesPage> Function(_StudiesRequest request);

class _StudiesRequest {
  const _StudiesRequest({
    required this.filter,
    required this.limit,
    required this.offset,
  });

  final GamebaseStudiesFilter filter;
  final int limit;
  final int offset;
}

class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository(this._studiesHandler, {this.detail})
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  final _StudiesHandler _studiesHandler;
  final GamebaseStudyDetail? detail;
  final List<_StudiesRequest> requests = <_StudiesRequest>[];
  final List<String> detailRequests = <String>[];

  @override
  Future<GamebaseStudiesPage> getStudies({
    GamebaseStudiesFilter filter = GamebaseStudiesFilter.defaultFilter,
    int limit = 50,
    int offset = 0,
  }) {
    final request = _StudiesRequest(
      filter: filter,
      limit: limit,
      offset: offset,
    );
    requests.add(request);
    return _studiesHandler(request);
  }

  @override
  Future<GamebaseStudyDetail> getStudy(String lichessStudyId) {
    detailRequests.add(lichessStudyId);
    final value = detail;
    if (value == null) {
      return Future<GamebaseStudyDetail>.error(StateError('No detail'));
    }
    return Future<GamebaseStudyDetail>.value(value);
  }
}

void main() {
  group('studiesProvider', () {
    test('separates cold loading from a successful empty page', () async {
      final firstPage = Completer<GamebaseStudiesPage>();
      final repository = _FakeGamebaseRepository((_) => firstPage.future);
      final container = _containerFor(repository);

      expect(
        container.read(studiesProvider),
        isA<AsyncLoading<StudiesState>>(),
      );
      expect(repository.requests, hasLength(1));
      expect(repository.requests.single.limit, kStudiesPageSize);
      expect(repository.requests.single.offset, 0);
      expect(repository.requests.single.filter.sort, GamebaseStudySort.score);
      expect(
        repository.requests.single.filter.order,
        GamebaseStudySortOrder.desc,
      );

      firstPage.complete(_page(ids: const <String>[], total: 0, offset: 0));
      final value = await container.read(studiesProvider.future);

      expect(value.isEmpty, isTrue);
      expect(value.items, isEmpty);
      expect(value.hasMore, isFalse);
      expect(container.read(studiesProvider), isA<AsyncData<StudiesState>>());
    });

    test('publishes immutable data and deduplicates the first page', () async {
      final repository = _FakeGamebaseRepository(
        (_) => Future<GamebaseStudiesPage>.value(
          _page(
            ids: const <String>['AbCd0001', 'AbCd0001', 'AbCd0002'],
            total: 3,
            offset: 0,
          ),
        ),
      );
      final container = _containerFor(repository);

      final value = await container.read(studiesProvider.future);

      expect(_ids(value), const <String>['AbCd0001', 'AbCd0002']);
      expect(value.nextOffset, 3);
      expect(value.hasMore, isFalse);
      expect(
        () => value.items.add(_study('AbCd9999')),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('paginates and deduplicates by canonical Lichess Study ID', () async {
      final repository = _FakeGamebaseRepository((request) {
        if (request.offset == 0) {
          return Future<GamebaseStudiesPage>.value(
            _page(
              ids: List<String>.generate(
                30,
                (index) => 'Aa${index.toString().padLeft(6, '0')}',
              ),
              total: 32,
              offset: 0,
            ),
          );
        }
        return Future<GamebaseStudiesPage>.value(
          _page(
            ids: const <String>['Aa000029', 'Aa000030'],
            total: 32,
            offset: 30,
          ),
        );
      });
      final container = _containerFor(repository);
      await container.read(studiesProvider.future);

      await container.read(studiesProvider.notifier).loadMore();

      final value = container.read(studiesProvider).requireValue;
      expect(repository.requests.map((request) => request.offset), <int>[
        0,
        30,
      ]);
      expect(value.items, hasLength(31));
      expect(value.items.last.canonicalStudyId, 'Aa000030');
      expect(value.nextOffset, 32);
      expect(value.hasMore, isFalse);
    });

    test('coalesces simultaneous load-more threshold events', () async {
      final laterPage = Completer<GamebaseStudiesPage>();
      final repository = _FakeGamebaseRepository((request) {
        if (request.offset == 0) {
          return Future<GamebaseStudiesPage>.value(
            _page(
              ids: List<String>.generate(
                30,
                (index) => 'Bb${index.toString().padLeft(6, '0')}',
              ),
              total: 31,
              offset: 0,
            ),
          );
        }
        return laterPage.future;
      });
      final container = _containerFor(repository);
      await container.read(studiesProvider.future);
      final notifier = container.read(studiesProvider.notifier);

      final first = notifier.loadMore();
      final second = notifier.loadMore();

      expect(identical(first, second), isTrue);
      expect(repository.requests, hasLength(2));
      expect(
        container.read(studiesProvider).requireValue.isLoadingMore,
        isTrue,
      );

      laterPage.complete(
        _page(ids: const <String>['Bb000030'], total: 31, offset: 30),
      );
      await Future.wait<void>(<Future<void>>[first, second]);

      expect(container.read(studiesProvider).requireValue.items, hasLength(31));
    });

    test(
      'retains data on pagination failure and retries the same offset',
      () async {
        var laterPageAttempts = 0;
        final repository = _FakeGamebaseRepository((request) {
          if (request.offset == 0) {
            return Future<GamebaseStudiesPage>.value(
              _page(
                ids: const <String>['AbCd0001', 'AbCd0002'],
                total: 4,
                offset: 0,
              ),
            );
          }
          laterPageAttempts += 1;
          if (laterPageAttempts == 1) {
            return Future<GamebaseStudiesPage>.error(
              StateError('network unavailable'),
            );
          }
          return Future<GamebaseStudiesPage>.value(
            _page(
              ids: const <String>['AbCd0003', 'AbCd0004'],
              total: 4,
              offset: 2,
            ),
          );
        });
        final container = _containerFor(repository);
        await container.read(studiesProvider.future);
        final notifier = container.read(studiesProvider.notifier);

        await notifier.loadMore();

        var value = container.read(studiesProvider).requireValue;
        expect(_ids(value), const <String>['AbCd0001', 'AbCd0002']);
        expect(value.nextOffset, 2);
        expect(value.hasMore, isTrue);
        expect(value.isLoadingMore, isFalse);
        expect(value.loadMoreFailure?.offset, 2);
        expect(value.loadMoreFailure?.error, isA<StateError>());

        await notifier.loadMore();

        value = container.read(studiesProvider).requireValue;
        expect(repository.requests.map((request) => request.offset), <int>[
          0,
          2,
          2,
        ]);
        expect(_ids(value), const <String>[
          'AbCd0001',
          'AbCd0002',
          'AbCd0003',
          'AbCd0004',
        ]);
        expect(value.loadMoreFailure, isNull);
        expect(value.hasMore, isFalse);
      },
    );

    test('filter replacement ignores a stale pagination response', () async {
      final stalePage = Completer<GamebaseStudiesPage>();
      final replacementPage = Completer<GamebaseStudiesPage>();
      final repository = _FakeGamebaseRepository((request) {
        if (request.filter.sort == GamebaseStudySort.recent) {
          return replacementPage.future;
        }
        if (request.offset == 30) return stalePage.future;
        return Future<GamebaseStudiesPage>.value(
          _page(
            ids: List<String>.generate(
              30,
              (index) => 'Cc${index.toString().padLeft(6, '0')}',
            ),
            total: 60,
            offset: 0,
          ),
        );
      });
      final container = _containerFor(repository);
      await container.read(studiesProvider.future);
      final notifier = container.read(studiesProvider.notifier);

      final staleLoad = notifier.loadMore();
      const replacementFilter = GamebaseStudiesFilter(
        sort: GamebaseStudySort.recent,
        order: GamebaseStudySortOrder.desc,
      );
      final replace = notifier.replaceFilter(replacementFilter);

      replacementPage.complete(
        _page(ids: const <String>['Fresh001'], total: 1, offset: 0),
      );
      await replace;
      stalePage.complete(
        _page(ids: const <String>['Stale001'], total: 60, offset: 30),
      );
      await staleLoad;

      final value = container.read(studiesProvider).requireValue;
      expect(_ids(value), const <String>['Fresh001']);
      expect(value.filter, same(replacementFilter));
      expect(value.loadMoreFailure, isNull);
    });

    test(
      'surfaces a cold request failure as AsyncError without data',
      () async {
        final repository = _FakeGamebaseRepository(
          (_) => Future<GamebaseStudiesPage>.error(
            const GamebaseStudyRequestException(
              operation: 'list Studies',
              message: 'offline',
            ),
          ),
        );
        final container = _containerFor(repository);

        await expectLater(
          container.read(studiesProvider.future),
          throwsA(isA<GamebaseStudyRequestException>()),
        );

        final state = container.read(studiesProvider);
        expect(state, isA<AsyncError<StudiesState>>());
        expect(state.hasValue, isFalse);
      },
    );

    test('refresh replaces the previous successful page', () async {
      var calls = 0;
      final repository = _FakeGamebaseRepository((_) {
        calls += 1;
        return Future<GamebaseStudiesPage>.value(
          calls == 1
              ? _page(ids: const <String>['Old00001'], total: 1, offset: 0)
              : _page(ids: const <String>['New00001'], total: 1, offset: 0),
        );
      });
      final container = _containerFor(repository);
      await container.read(studiesProvider.future);

      await container.read(studiesProvider.notifier).refresh();

      expect(_ids(container.read(studiesProvider).requireValue), const <String>[
        'New00001',
      ]);
      expect(repository.requests.map((request) => request.offset), <int>[0, 0]);
    });
  });

  test('studyDetailProvider requests canonical metadata only', () async {
    final detail = GamebaseStudyDetail(
      study: _study('AbCd1234'),
      chapters: <GamebaseStudyChapterMetadata>[
        _chapter(studyId: 'AbCd1234', chapterId: 'Chapter1', orderIndex: 0),
      ],
    );
    final repository = _FakeGamebaseRepository(
      (_) => Future<GamebaseStudiesPage>.value(
        _page(ids: const <String>[], total: 0, offset: 0),
      ),
      detail: detail,
    );
    final container = ProviderContainer(
      overrides: <Override>[
        gamebaseRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final value = await container.read(
      studyDetailProvider(' AbCd1234 ').future,
    );

    expect(repository.detailRequests, const <String>['AbCd1234']);
    expect(value.study.canonicalStudyId, 'AbCd1234');
    expect(value.canOpenMirroredChapterInApp, isFalse);
    expect(value.chapters.single.canOpenMirroredChapterInApp, isFalse);
  });
}

ProviderContainer _containerFor(GamebaseRepository repository) {
  final container = ProviderContainer(
    overrides: <Override>[
      gamebaseRepositoryProvider.overrideWithValue(repository),
    ],
  );
  final subscription = container.listen<AsyncValue<StudiesState>>(
    studiesProvider,
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(() {
    subscription.close();
    container.dispose();
  });
  return container;
}

GamebaseStudiesPage _page({
  required List<String> ids,
  required int total,
  required int offset,
}) {
  return GamebaseStudiesPage(
    items: ids.map(_study).toList(growable: false),
    total: total,
    limit: kStudiesPageSize,
    offset: offset,
  );
}

List<String> _ids(StudiesState state) {
  return state.items
      .map((study) => study.canonicalStudyId)
      .toList(growable: false);
}

GamebaseStudySummary _study(String id) {
  return GamebaseStudySummary(
    lichessStudyId: id,
    authorUsername: 'coach',
    name: 'Study $id',
    views: 840,
    lichessCreatedAt: DateTime.utc(2026, 1, 15),
    lichessUpdatedAt: DateTime.utc(2026, 7, 1),
    chapterCount: 2,
    plyTotal: 112,
    hasAnnotations: true,
    ecos: const <String>['B90'],
    ecoCategories: const <String>['B'],
    openings: const <String>['Sicilian Defense'],
    variants: const <String>['Standard'],
    chapterModes: const <String>['normal'],
    players: const <String>['White Player', 'Black Player'],
    isGamebook: false,
    hasCustomPositions: false,
    credibilityScore: 76.4,
    passedGate: true,
    status: GamebaseStudyStatus.active,
    syncedAt: DateTime.utc(2026, 7, 10),
  );
}

GamebaseStudyChapterMetadata _chapter({
  required String studyId,
  required String chapterId,
  required int orderIndex,
}) {
  return GamebaseStudyChapterMetadata(
    lichessStudyId: studyId,
    lichessChapterId: chapterId,
    name: 'Main line',
    plyCount: 56,
    orderIndex: orderIndex,
    eco: 'B90',
    opening: 'Sicilian Defense',
    variant: 'Standard',
    result: '1-0',
    chapterMode: 'normal',
    isSetup: false,
    whiteName: 'White Player',
    blackName: 'Black Player',
    whiteElo: 2500,
    blackElo: 2450,
    hasAnnotations: true,
  );
}
