import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/studies/data/study_bookmark.dart';
import 'package:chessever2/screens/studies/data/study_bookmark_repository.dart';
import 'package:chessever2/screens/studies/providers/study_bookmarks_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('disabled rollout performs zero bookmark and Gamebase calls', () async {
    final store = _FakeStore(<StudyBookmarkReference>[_bookmark('AbCd0001')]);
    final gamebase = _FakeGamebaseRepository();
    final container = _container(store: store, gamebase: gamebase);

    final saved = await container.read(savedStudiesProvider.future);

    expect(saved.isEnabled, isFalse);
    expect(saved.items, isEmpty);
    expect(store.fetchCalls, 0);
    expect(gamebase.requestedIds, isEmpty);
    container.dispose();
  });

  test(
    'orders resolved Studies and turns 404 into removable tombstone',
    () async {
      final store = _FakeStore(<StudyBookmarkReference>[
        _bookmark('AbCd0002', progressHour: 12),
        _bookmark('AbCd0001', bookmarkedHour: 11),
      ]);
      final gamebase = _FakeGamebaseRepository(
        handlers: <String, Future<GamebaseStudyDetail> Function()>{
          'AbCd0002': () async => _detail('AbCd0002'),
          'AbCd0001':
              () async =>
                  throw const GamebaseStudyRequestException(
                    operation: 'get Study',
                    message: 'Gone',
                    statusCode: 404,
                  ),
        },
      );
      final container = _container(
        enabled: true,
        store: store,
        gamebase: gamebase,
      );

      final saved = await container.read(savedStudiesProvider.future);

      expect(saved.items, hasLength(2));
      expect(saved.items.first, isA<AvailableSavedStudy>());
      expect(saved.items.last, isA<UnavailableSavedStudy>());
      expect(saved.resolutionFailures, isEmpty);
      expect(saved.items.last.bookmark.displaySnapshot.title, 'Saved AbCd0001');
      container.dispose();
    },
  );

  test('non-404 failures preserve usable items as partial data', () async {
    final store = _FakeStore(<StudyBookmarkReference>[
      _bookmark('AbCd0001'),
      _bookmark('AbCd0002'),
    ]);
    final gamebase = _FakeGamebaseRepository(
      handlers: <String, Future<GamebaseStudyDetail> Function()>{
        'AbCd0001': () async => _detail('AbCd0001'),
        'AbCd0002':
            () async =>
                throw const GamebaseStudyRequestException(
                  operation: 'get Study',
                  message: 'Offline',
                ),
      },
    );
    final container = _container(
      enabled: true,
      store: store,
      gamebase: gamebase,
    );

    final saved = await container.read(savedStudiesProvider.future);

    expect(saved.items, hasLength(1));
    expect(saved.resolutionFailures, hasLength(1));
    container.dispose();
  });

  test('resolution caps concurrency and rail size', () async {
    final store = _FakeStore(
      List<StudyBookmarkReference>.generate(
        16,
        (index) => _bookmark('Aa${index.toString().padLeft(6, '0')}'),
      ),
    );
    final gamebase = _FakeGamebaseRepository(delayResolution: true);
    final container = _container(
      enabled: true,
      store: store,
      gamebase: gamebase,
    );

    final result = await container.read(savedStudiesProvider.future);

    expect(result.items, hasLength(kMaximumSavedStudiesRailItems));
    expect(gamebase.requestedIds, hasLength(kMaximumSavedStudiesRailItems));
    expect(
      gamebase.maximumConcurrentRequests,
      lessThanOrEqualTo(kSavedStudyResolutionConcurrency),
    );
    container.dispose();
  });

  test(
    'notifier exposes bookmark, progress and unbookmark mutations',
    () async {
      final store = _FakeStore(const <StudyBookmarkReference>[]);
      final container = _container(
        enabled: true,
        store: store,
        gamebase: _FakeGamebaseRepository(),
      );
      await container.read(studyBookmarksProvider.future);
      final notifier = container.read(studyBookmarksProvider.notifier);

      await notifier.bookmark(lichessStudyId: 'AbCd0001');
      await notifier.upsertProgress(
        lichessStudyId: 'AbCd0001',
        lichessChapterId: 'Chapter1',
        lastPly: 12,
      );
      await notifier.unbookmark('AbCd0001');

      expect(store.bookmarkCalls, 1);
      expect(store.progressCalls, 1);
      expect(store.unbookmarkCalls, 1);
      expect(
        container.read(studyBookmarksProvider).requireValue.references,
        isEmpty,
      );
      container.dispose();
    },
  );
}

ProviderContainer _container({
  bool enabled = false,
  required _FakeStore store,
  required _FakeGamebaseRepository gamebase,
}) {
  return ProviderContainer(
    overrides: <Override>[
      studyBookmarksEnabledProvider.overrideWithValue(enabled),
      studyBookmarkRepositoryProvider.overrideWithValue(store),
      gamebaseRepositoryProvider.overrideWithValue(gamebase),
    ],
  );
}

final class _FakeStore implements StudyBookmarkStore {
  _FakeStore(this.references);

  final List<StudyBookmarkReference> references;
  int fetchCalls = 0;
  int bookmarkCalls = 0;
  int progressCalls = 0;
  int unbookmarkCalls = 0;

  @override
  Future<List<StudyBookmarkReference>> fetch({int limit = 48}) async {
    fetchCalls += 1;
    return references.take(limit).toList(growable: false);
  }

  @override
  Future<StudyBookmarkReference> bookmark({
    required String lichessStudyId,
    StudyBookmarkDisplaySnapshot snapshot =
        const StudyBookmarkDisplaySnapshot(),
  }) async {
    bookmarkCalls += 1;
    return _bookmark(lichessStudyId);
  }

  @override
  Future<void> unbookmark(String lichessStudyId) async {
    unbookmarkCalls += 1;
  }

  @override
  Future<StudyBookmarkReference> upsertProgress({
    required String lichessStudyId,
    required String lichessChapterId,
    required int lastPly,
    String? contentVersion,
    StudyBookmarkDisplaySnapshot snapshot =
        const StudyBookmarkDisplaySnapshot(),
  }) async {
    progressCalls += 1;
    return _bookmark(lichessStudyId, progressHour: 12);
  }
}

final class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository({
    this.handlers = const <String, Future<GamebaseStudyDetail> Function()>{},
    this.delayResolution = false,
  }) : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  final Map<String, Future<GamebaseStudyDetail> Function()> handlers;
  final bool delayResolution;
  final List<String> requestedIds = <String>[];
  int concurrentRequests = 0;
  int maximumConcurrentRequests = 0;

  @override
  Future<GamebaseStudyDetail> getStudy(String lichessStudyId) async {
    requestedIds.add(lichessStudyId);
    concurrentRequests += 1;
    if (concurrentRequests > maximumConcurrentRequests) {
      maximumConcurrentRequests = concurrentRequests;
    }
    try {
      if (delayResolution) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      final handler = handlers[lichessStudyId];
      return handler == null ? _detail(lichessStudyId) : await handler();
    } finally {
      concurrentRequests -= 1;
    }
  }
}

StudyBookmarkReference _bookmark(
  String id, {
  int bookmarkedHour = 10,
  int? progressHour,
}) {
  return StudyBookmarkReference(
    userId: 'user-1',
    lichessStudyId: id,
    lichessChapterId: progressHour == null ? null : 'Chapter1',
    lastPly: progressHour == null ? null : 12,
    displaySnapshot: StudyBookmarkDisplaySnapshot.validated(
      title: 'Saved $id',
      attribution: 'Study on Lichess',
    ),
    bookmarkedAt: DateTime.utc(2026, 7, 10, bookmarkedHour),
    progressUpdatedAt:
        progressHour == null ? null : DateTime.utc(2026, 7, 10, progressHour),
    updatedAt: DateTime.utc(2026, 7, 10, 13),
  );
}

GamebaseStudyDetail _detail(String id) {
  final now = DateTime.utc(2026, 7, 10);
  return GamebaseStudyDetail(
    study: GamebaseStudySummary(
      lichessStudyId: id,
      authorUsername: 'author',
      name: 'Quality Study $id',
      views: 100,
      lichessCreatedAt: now,
      lichessUpdatedAt: now,
      chapterCount: 1,
      plyTotal: 20,
      hasAnnotations: true,
      ecos: const <String>['C65'],
      ecoCategories: const <String>['C'],
      openings: const <String>['Ruy Lopez'],
      variants: const <String>['standard'],
      chapterModes: const <String>['normal'],
      players: const <String>[],
      isGamebook: false,
      hasCustomPositions: false,
      credibilityScore: 0.9,
      passedGate: true,
      status: GamebaseStudyStatus.active,
      syncedAt: now,
    ),
    chapters: const <GamebaseStudyChapterMetadata>[],
  );
}
