import 'dart:convert';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.responseBody);

  final Object responseBody;
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
      jsonEncode(responseBody),
      200,
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

Map<String, dynamic> _miniature({
  String gameId = '04a5af9b-0a7f-58c6-837f-ed3a49162b54',
  String? whitePlayerId = 'white-id',
  String? blackPlayerId = 'black-id',
}) {
  return <String, dynamic>{
    'gameId': gameId,
    'avgRating': 1629,
    'plyCount': 50,
    'finalMoveNumber': 25,
    'result': 'W',
    'timeControl': 'RAPID',
    'isOnline': false,
    'date': '2026-06-25T00:00:00.000Z',
    'event': 'Fountain Open',
    'eco': 'B03',
    'ecoCategory': 'B',
    'opening': 'Alekhine Defense',
    'variation': 'Four Pawns Attack',
    'whiteName': 'Ashwin Jayaram',
    'blackName': 'Mathilde Sage Housion',
    'whiteElo': null,
    'blackElo': 1629,
    'whitePlayerId': whitePlayerId,
    'blackPlayerId': blackPlayerId,
    'whiteFed': 'USA',
    'blackFed': 'ITA',
  };
}

void main() {
  group('Gamebase Miniatures response decoding', () {
    test('decodes the canonical nested envelope and offset metadata', () async {
      final adapter = _ScriptedAdapter({
        'status': 'success',
        'data': {
          'items': [_miniature(), _miniature(gameId: 'second-game-id')],
          'total': 5,
          'limit': 2,
          'offset': 2,
        },
      });

      final page = await _repository(
        adapter,
      ).getMiniatures(limit: 2, offset: 2);

      expect(adapter.lastRequest?.path, 'http://test/api/miniatures');
      expect(adapter.lastRequest?.headers['X-API-Key'], 'test-key');
      expect(adapter.lastRequest?.queryParameters, {
        'window': 'all',
        'sort': 'rating',
        'order': 'desc',
        'limit': 2,
        'offset': 2,
      });
      expect(page.total, 5);
      expect(page.limit, 2);
      expect(page.offset, 2);
      expect(page.nextOffset, 4);
      expect(page.hasMore, isTrue);
      expect(page.items, hasLength(2));

      final item = page.items.first;
      expect(item.result, MiniatureGameResult.whiteWins);
      expect(item.timeControl, MiniatureGameTimeControl.rapid);
      expect(item.onlineStatus, MiniatureGameOnlineStatus.offline);
      expect(item.isOnline, isFalse);
      expect(item.date, DateTime.utc(2026, 6, 25));
    });

    test('accepts the historical flat page shape', () {
      final page = GamebaseMiniaturesPage.fromJson({
        'items': [_miniature()],
        'total': '1',
        'limit': '50',
        'offset': '0',
      });

      expect(page.items.single.gameId, _miniature()['gameId']);
      expect(page.total, 1);
      expect(page.limit, 50);
      expect(page.offset, 0);
      expect(page.nextOffset, 1);
      expect(page.hasMore, isFalse);
    });

    test('rejects a malformed nested envelope instead of returning empty', () {
      expect(
        () => GamebaseMiniaturesPage.fromJson({
          'status': 'success',
          'data': {'total': 0, 'limit': 50, 'offset': 0},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => GamebaseMiniaturesPage.fromJson({
          'status': 'success',
          'data': <String, dynamic>{},
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('repository preserves malformed-envelope failures', () async {
      final adapter = _ScriptedAdapter({
        'status': 'success',
        'data': {'items': <Object>[], 'limit': 50, 'offset': 0},
      });

      expect(
        _repository(adapter).getMiniatures(),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed required item fields', () {
      expect(
        () => GamebaseMiniaturesPage.fromJson({
          'items': [
            {..._miniature(), 'gameId': '', 'result': 'draw'},
          ],
          'total': 1,
          'limit': 1,
          'offset': 0,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('preserves null and absent optional fields', () {
      final item =
          GamebaseMiniaturesPage.fromJson({
            'status': 'success',
            'data': {
              'items': [
                {
                  'gameId': 'nullable-game-id',
                  'avgRating': null,
                  'plyCount': 9,
                  'finalMoveNumber': 5,
                  'result': 'B',
                  'timeControl': 'CLASSICAL',
                  'isOnline': true,
                  'date': null,
                  'event': null,
                  'eco': '',
                  'opening': null,
                  'whiteElo': null,
                  'blackElo': null,
                  'whitePlayerId': null,
                  'blackPlayerId': null,
                },
              ],
              'total': 1,
              'limit': 1,
              'offset': 0,
            },
          }).items.single;

      expect(item.avgRating, isNull);
      expect(item.date, isNull);
      expect(item.event, isNull);
      expect(item.eco, isNull);
      expect(item.ecoCategory, isNull);
      expect(item.opening, isNull);
      expect(item.variation, isNull);
      expect(item.whiteName, isNull);
      expect(item.blackName, isNull);
      expect(item.whiteElo, isNull);
      expect(item.blackElo, isNull);
      expect(item.result, MiniatureGameResult.blackWins);
      expect(item.timeControl, MiniatureGameTimeControl.classical);
      expect(item.onlineStatus, MiniatureGameOnlineStatus.online);
    });

    test('an empty page is terminal even when total is stale', () {
      final page = GamebaseMiniaturesPage.fromJson({
        'items': <Object>[],
        'total': 100,
        'limit': 20,
        'offset': 40,
      });

      expect(page.nextOffset, 40);
      expect(page.hasMore, isFalse);
    });
  });

  group('MiniatureGamesFilter', () {
    test('serializes the complete endpoint query exactly', () async {
      const filter = MiniatureGamesFilter(
        window: MiniatureGamesWindow.week,
        sort: MiniatureGamesSort.moves,
        order: MiniatureGamesSortOrder.asc,
        search: '  Carlsen  ',
        results: {MiniatureGameResult.whiteWins, MiniatureGameResult.blackWins},
        eco: ' b12, C44, b12 ',
        ecoCategories: {' b ', 'C'},
        opening: '  Sicilian Defense ',
        variation: ' Najdorf  ',
        timeControls: {
          MiniatureGameTimeControl.rapid,
          MiniatureGameTimeControl.blitz,
        },
        onlineStatus: MiniatureGameOnlineStatus.online,
        minRating: 2200,
        maxRating: 2800,
        minMoves: 8,
        maxMoves: 25,
        dateFrom: '2026-01-01',
        dateTo: '2026-12-31',
        player: '  Kasparov ',
        playerId: ' canonical-player-id ',
      );

      final adapter = _ScriptedAdapter({
        'status': 'success',
        'data': {'items': <Object>[], 'total': 0, 'limit': 30, 'offset': 60},
      });
      await _repository(
        adapter,
      ).getMiniatures(filter: filter, limit: 30, offset: 60);

      expect(adapter.lastRequest?.queryParameters, {
        'window': 'week',
        'sort': 'moves',
        'order': 'asc',
        'limit': 30,
        'offset': 60,
        'q': 'Carlsen',
        'result': 'W,B',
        'eco': 'B12,C44',
        'ecoCategory': 'B,C',
        'opening': 'Sicilian Defense',
        'variation': 'Najdorf',
        'timeControl': 'RAPID,BLITZ',
        'isOnline': true,
        'minRating': 2200,
        'maxRating': 2800,
        'minMoves': 8,
        'maxMoves': 25,
        'dateFrom': '2026-01-01',
        'dateTo': '2026-12-31',
        'player': 'Kasparov',
        'playerId': 'canonical-player-id',
      });
    });

    test('omits empty optionals and normalizes an inverted date range', () {
      const filter = MiniatureGamesFilter(
        search: '   ',
        eco: ' , ',
        dateFrom: '2026-12-31',
        dateTo: '2026-01-01',
        player: '',
        playerId: ' ',
      );

      expect(filter.queryParameters(limit: 50, offset: 0), {
        'window': 'all',
        'sort': 'rating',
        'order': 'desc',
        'limit': 50,
        'offset': 0,
        'dateFrom': '2026-01-01',
        'dateTo': '2026-12-31',
      });
    });
  });

  test('preserves canonical game identity and hydration source metadata', () {
    final item = GamebaseMiniature.fromJson(
      _miniature(
        gameId: 'stable-game-id',
        whitePlayerId: 'stable-white-id',
        blackPlayerId: 'stable-black-id',
      ),
    );

    expect(item.gameId, 'stable-game-id');
    expect(item.canonicalGameId, 'stable-game-id');
    expect(item.sourceGameId, 'stable-game-id');

    final source = item.sourceMetadata;
    expect(source.gameId, 'stable-game-id');
    expect(source.source, GamebaseMiniatureSource.gamebase);
    expect(source.requiresFullGameHydration, isTrue);
    expect(source.whitePlayerId, 'stable-white-id');
    expect(source.blackPlayerId, 'stable-black-id');
  });
}
