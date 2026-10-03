import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'opening models preserve scope counts and reject malformed ECO rows',
    () {
      final page = CollectionOpeningsPage.fromJson({
        'items': [
          {
            'eco': 'c60',
            'name': 'Ruy Lopez',
            'fen': null,
            'gameCount': 12,
            'bookCount': 3,
          },
          {'eco': 'invalid', 'gameCount': 30},
        ],
        'total': 1,
        'limit': 100,
        'offset': 0,
      });
      expect(page.items.single.eco, 'C60');
      expect(page.items.single.gameCount, 12);
      expect(page.items.single.bookCount, 3);
      expect(
        Collection.fromJson({
          'id': 'book',
          'kind': 'book',
          'matchedGameCount': 7,
        }).matchedGameCount,
        7,
      );
    },
  );

  test(
    'opening routes carry ECO and collection scope, games alone carry the session',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              requests.add(request);
              handler.resolve(
                Response(
                  requestOptions: request,
                  statusCode: 200,
                  data: {
                    'status': 'success',
                    'data': {
                      'items': [],
                      'total': 0,
                      'limit': 100,
                      'offset': 0,
                    },
                  },
                ),
              );
            },
          ),
        );
      final api = GamebaseRepository(dio, apiKey: 'test');
      final repo = CollectionsRepository(
        api,
        accessToken: () => 'test-session',
      );
      await repo.fetchOpenings();
      await repo.fetchOpenings(slug: 'opening-book');
      await repo.fetchBooksForOpening('C60');
      await repo.fetchGamesForOpening('opening-book', 'C60');
      await repo.fetchPublishedGames(offset: 40);
      expect(requests.map((r) => r.uri.path), [
        '/api/collections/openings',
        '/api/collections/opening-book/openings',
        '/api/collections/for-opening',
        '/api/collections/opening-book/games',
        '/api/collections/games',
      ]);
      expect(requests[2].queryParameters['eco'], 'C60');
      expect(requests[3].queryParameters['eco'], 'C60');
      expect(requests[3].queryParameters.containsKey('include'), isFalse);
      expect(requests[3].headers['Authorization'], 'Bearer test-session');
      expect(requests[4].queryParameters['offset'], 40);
      expect(requests[4].headers['Authorization'], 'Bearer test-session');
      expect(
        requests.take(3).every((r) => !r.headers.containsKey('Authorization')),
        isTrue,
      );
      dio.close();
    },
  );

  test(
    'published batches advance past unreadable PGNs without looping',
    () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              handler.resolve(
                Response(
                  requestOptions: request,
                  statusCode: 200,
                  data: {
                    'status': 'success',
                    'data': {
                      'items': [
                        {'id': 'broken', 'pgn': null},
                      ],
                      'total': 42,
                      'offset': 40,
                      'limit': 40,
                    },
                  },
                ),
              );
            },
          ),
        );
      final batch = await CollectionsRepository(
        GamebaseRepository(dio, apiKey: 'test'),
        accessToken: () => null,
      ).fetchPublishedGames(offset: 40);
      expect(batch.games, isEmpty);
      expect(batch.nextOffset, 41);
      expect(batch.hasMore, isTrue);
      dio.close();
    },
  );
}
