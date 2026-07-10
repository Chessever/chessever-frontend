import 'dart:convert';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.body, {this.statusCode = 200});

  final Object body;
  final int statusCode;
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }
}

GamebaseRepository _repository(_ScriptedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return GamebaseRepository(dio, baseUrl: 'http://test', apiKey: 'test-key');
}

Map<String, dynamic> _study({
  String id = 'AbCd1234',
  Object? authorUsername = 'example_author',
  Object? lichessCreatedAt = '2026-01-15T08:00:00.000Z',
}) {
  return <String, dynamic>{
    'id': id,
    'authorUsername': authorUsername,
    'name': 'Annotated Sicilian Model Games',
    'views': 840,
    'lichessCreatedAt': lichessCreatedAt,
    'lichessUpdatedAt': '2026-07-01T09:00:00.000Z',
    'chapterCount': 2,
    'plyTotal': 112,
    'hasAnnotations': true,
    'ecos': ['B90', 'B91'],
    'ecoCategories': ['B'],
    'openings': ['Sicilian Defense'],
    'variants': ['Standard'],
    'chapterModes': ['normal', 'gamebook'],
    'players': ['Example White', 'Example Black'],
    'isGamebook': true,
    'hasCustomPositions': false,
    'credibilityScore': 76.4,
    'passedGate': true,
    'status': 'active',
    'syncedAt': '2026-07-10T02:00:00.000Z',
    // The service currently leaks these ORM timestamps. They are deliberately
    // not promoted to source identity or content-version fields by the client.
    'createdAt': '2026-06-01T00:00:00.000Z',
    'updatedAt': '2026-07-10T02:00:00.000Z',
  };
}

Map<String, dynamic> _chapter({
  required String internalId,
  required String chapterId,
  required int orderIndex,
  String? name = 'Main line',
}) {
  return <String, dynamic>{
    'id': internalId,
    'chapterId': chapterId,
    'name': name,
    'plyCount': 56,
    'orderIndex': orderIndex,
    'eco': 'B90',
    'opening': 'Sicilian Defense',
    'variant': 'Standard',
    'result': '1-0',
    'chapterMode': 'normal',
    'isSetup': false,
    'whiteName': 'Example White',
    'blackName': 'Example Black',
    'whiteElo': 2500,
    'blackElo': 2450,
    'hasAnnotations': true,
  };
}

void main() {
  group('Gamebase Studies list contract', () {
    test('decodes the actual nested envelope and quality fields', () async {
      final adapter = _ScriptedAdapter({
        'status': 'success',
        'data': {
          'items': [_study()],
          'total': 3,
          'limit': 1,
          'offset': 1,
        },
      });

      final page = await _repository(adapter).getStudies(limit: 1, offset: 1);

      expect(adapter.lastRequest?.path, 'http://test/api/studies');
      expect(adapter.lastRequest?.headers['X-API-Key'], 'test-key');
      expect(adapter.lastRequest?.queryParameters, {
        'sort': 'score',
        'order': 'desc',
        'limit': 1,
        'offset': 1,
      });

      expect(page.total, 3);
      expect(page.limit, 1);
      expect(page.offset, 1);
      expect(page.nextOffset, 2);
      expect(page.hasMore, isTrue);

      final study = page.items.single;
      expect(study.lichessStudyId, 'AbCd1234');
      expect(study.canonicalStudyId, 'AbCd1234');
      expect(study.authorUsername, 'example_author');
      expect(study.views, 840);
      expect(study.chapterCount, 2);
      expect(study.plyTotal, 112);
      expect(study.hasAnnotations, isTrue);
      expect(study.credibilityScore, 76.4);
      expect(study.passedGate, isTrue);
      expect(study.status, GamebaseStudyStatus.active);
      expect(study.isGamebook, isTrue);
      expect(study.hasCustomPositions, isFalse);
      expect(study.ecos, ['B90', 'B91']);
      expect(study.source, GamebaseStudySource.lichess);
      expect(study.sourceUrl.toString(), 'https://lichess.org/study/AbCd1234');
    });

    test(
      'serializes every existing list filter at the request boundary',
      () async {
        const filter = GamebaseStudiesFilter(
          sort: GamebaseStudySort.created,
          order: GamebaseStudySortOrder.asc,
          search: '  Sicilian plans  ',
          ecos: {' b90 ', 'B91', 'b90'},
          ecoCategories: {' b ', 'C'},
          openings: {' Sicilian Defense ', 'French Defense'},
          variants: {'Standard', 'Chess960'},
          chapterModes: {'gamebook', 'normal'},
          players: {'Example White', ' Example Black '},
          gamebook: false,
          customPositions: true,
          hasAnnotations: false,
          minViews: 100,
          minChapters: 2,
        );
        final adapter = _ScriptedAdapter({
          'status': 'success',
          'data': {'items': <Object>[], 'total': 48, 'limit': 24, 'offset': 48},
        });

        await _repository(
          adapter,
        ).getStudies(filter: filter, limit: 24, offset: 48);

        expect(adapter.lastRequest?.queryParameters, {
          'sort': 'created',
          'order': 'asc',
          'limit': 24,
          'offset': 48,
          'q': 'Sicilian plans',
          'eco': 'B90,B91',
          'ecoCategory': 'B,C',
          'opening': 'Sicilian Defense,French Defense',
          'variant': 'Standard,Chess960',
          'chapterMode': 'gamebook,normal',
          'player': 'Example White,Example Black',
          'gamebook': false,
          'customPositions': true,
          'hasAnnotations': false,
          'minViews': 100,
          'minChapters': 2,
        });
      },
    );

    test('preserves nullable source metadata without fabricating values', () {
      final page = GamebaseStudiesPage.fromJson({
        'status': 'success',
        'data': {
          'items': [_study(authorUsername: null, lichessCreatedAt: null)],
          'total': 1,
          'limit': 50,
          'offset': 0,
        },
      });

      final study = page.items.single;
      expect(study.authorUsername, isNull);
      expect(study.lichessCreatedAt, isNull);
      expect(study.lichessUpdatedAt, DateTime.utc(2026, 7, 1, 9));
      expect(study.syncedAt, DateTime.utc(2026, 7, 10, 2));
    });

    test(
      'rejects flat or malformed payloads with a typed contract failure',
      () {
        expect(
          () => GamebaseStudiesPage.fromJson({
            'items': <Object>[],
            'total': 0,
            'limit': 50,
            'offset': 0,
          }),
          throwsA(isA<GamebaseStudyContractException>()),
        );
        expect(
          () => GamebaseStudiesPage.fromJson({
            'status': 'success',
            'data': {'items': <Object>[], 'limit': 50, 'offset': 0},
          }),
          throwsA(isA<GamebaseStudyContractException>()),
        );
        expect(
          () => GamebaseStudiesPage.fromJson({
            'status': 'success',
            'data': {
              'items': [
                {..._study(), 'passedGate': 'not-a-bool'},
              ],
              'total': 1,
              'limit': 1,
              'offset': 0,
            },
          }),
          throwsA(isA<GamebaseStudyContractException>()),
        );
      },
    );
  });

  group('Gamebase Study detail contract', () {
    test(
      'uses external chapter identity and source order, never row UUIDs',
      () async {
        final adapter = _ScriptedAdapter({
          'status': 'success',
          'data': {
            'study': _study(),
            // Deliberately reversed to prove orderIndex is the source order.
            'chapters': [
              _chapter(
                internalId: '22222222-2222-2222-2222-222222222222',
                chapterId: 'Chapter2',
                orderIndex: 1,
                name: 'Second chapter',
              ),
              _chapter(
                internalId: '11111111-1111-1111-1111-111111111111',
                chapterId: 'Chapter1',
                orderIndex: 0,
                name: 'First chapter',
              ),
            ],
          },
        });

        final detail = await _repository(adapter).getStudy('  AbCd1234  ');

        expect(adapter.lastRequest?.path, 'http://test/api/studies/AbCd1234');
        expect(detail.canonicalStudyId, 'AbCd1234');
        expect(detail.chapters.map((chapter) => chapter.orderIndex), [0, 1]);

        final first = detail.chapters.first;
        expect(first.lichessStudyId, 'AbCd1234');
        expect(first.lichessChapterId, 'Chapter1');
        expect(first.canonicalStudyId, 'AbCd1234');
        expect(first.canonicalChapterId, 'Chapter1');
        expect(
          first.canonicalChapterId,
          isNot('11111111-1111-1111-1111-111111111111'),
        );
        expect(
          first.sourceUrl.toString(),
          'https://lichess.org/study/AbCd1234/Chapter1',
        );
        expect(first.name, 'First chapter');
        expect(first.hasAnnotations, isTrue);
      },
    );

    test('keeps nullable chapter metadata nullable', () {
      final chapter = <String, dynamic>{
        ..._chapter(
          internalId: 'internal-only-id',
          chapterId: 'Nullable1',
          orderIndex: 0,
          name: null,
        ),
        'eco': null,
        'opening': null,
        'variant': null,
        'result': null,
        'chapterMode': null,
        'whiteName': null,
        'blackName': null,
        'whiteElo': null,
        'blackElo': null,
      };
      final detail = GamebaseStudyDetail.fromJson({
        'status': 'success',
        'data': {
          'study': _study(),
          'chapters': [chapter],
        },
      });

      final parsed = detail.chapters.single;
      expect(parsed.name, isNull);
      expect(parsed.eco, isNull);
      expect(parsed.opening, isNull);
      expect(parsed.variant, isNull);
      expect(parsed.result, isNull);
      expect(parsed.chapterMode, isNull);
      expect(parsed.whiteName, isNull);
      expect(parsed.blackName, isNull);
      expect(parsed.whiteElo, isNull);
      expect(parsed.blackElo, isNull);
    });

    test(
      'does not invent content versions, rights, or redistribution access',
      () {
        final detail = GamebaseStudyDetail.fromJson({
          'status': 'success',
          'data': {
            'study': _study(),
            'chapters': [
              _chapter(
                internalId: 'internal-only-id',
                chapterId: 'Chapter1',
                orderIndex: 0,
              ),
            ],
          },
        });

        for (final capabilities in <GamebaseStudyContentCapabilities>[
          detail.contentCapabilities,
          detail.chapters.single.contentCapabilities,
        ]) {
          expect(capabilities.contentVersion, isNull);
          expect(capabilities.rights, isNull);
          expect(
            capabilities.redistribution,
            GamebaseStudyRedistributionCapability.unknown,
          );
          expect(capabilities.canOpenMirroredChapterInApp, isFalse);
        }
        expect(detail.contentVersion, isNull);
        expect(detail.rights, isNull);
        expect(
          detail.redistribution,
          GamebaseStudyRedistributionCapability.unknown,
        );
        expect(detail.canOpenMirroredChapterInApp, isFalse);
        expect(detail.study.canOpenMirroredChapterInApp, isFalse);
        expect(detail.chapters.single.canOpenMirroredChapterInApp, isFalse);
      },
    );

    test('rejects malformed external chapter identity', () {
      final chapter = _chapter(
        internalId: 'internal-row-uuid',
        chapterId: 'External1',
        orderIndex: 0,
      )..remove('chapterId');

      expect(
        () => GamebaseStudyDetail.fromJson({
          'status': 'success',
          'data': {
            'study': _study(),
            'chapters': [chapter],
          },
        }),
        throwsA(isA<GamebaseStudyContractException>()),
      );

      expect(
        () => GamebaseStudyDetail.fromJson({
          'status': 'success',
          'data': {
            'study': _study(),
            'chapters': [
              _chapter(
                internalId: 'internal-row-uuid',
                chapterId: 'AbCd1234-c0',
                orderIndex: 0,
              ),
            ],
          },
        }),
        throwsA(isA<GamebaseStudyContractException>()),
      );
    });

    test('surfaces HTTP failures as typed request failures', () async {
      final adapter = _ScriptedAdapter({
        'status': 'error',
        'error': {'message': 'Study not found'},
      }, statusCode: 404);

      expect(
        _repository(adapter).getStudy('Missing1'),
        throwsA(
          isA<GamebaseStudyRequestException>()
              .having((error) => error.statusCode, 'statusCode', 404)
              .having((error) => error.isNotFound, 'isNotFound', isTrue),
        ),
      );
    });
  });
}
