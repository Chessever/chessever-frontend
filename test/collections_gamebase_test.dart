import 'dart:convert';
import 'dart:typed_data';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shapes of the gamebase Collections API (see the shared contract): the app
/// and gamebase live in separate repos, so these guard the parsing against
/// nulls, wrong scalar types and keys the backend adds later.
const _listResponse = '''
{
  "status": "success",
  "data": {
    "items": [
      {
        "id": "c1", "slug": "us-championship-2025", "kind": "event",
        "status": "published", "title": "US Championship 2025",
        "subtitle": null, "author": null, "annotator": "GM Annotator",
        "coverUrl": "", "location": "Saint Louis",
        "dateStart": "2025-10-02", "dateEnd": "2025-10-14",
        "publisher": null, "publishedYear": null, "sortOrder": 10,
        "publishedAt": "2025-10-20T12:00:00.000Z",
        "gameCount": 3, "sectionCount": 2, "annotatedCount": 3,
        "plyTotal": 210, "players": ["Caruana, Fabiano", "So, Wesley"],
        "ecos": ["C42", "B90"], "contentVersion": "a1b2c3",
        "updatedAt": "2025-10-20T12:00:00.000Z",
        "someFutureField": {"nested": true}
      },
      {
        "id": "c2", "slug": "my-system", "kind": "book", "title": "My System",
        "author": "Aron Nimzowitsch", "publisher": "Quality Chess",
        "publishedYear": "2016", "gameCount": "12",
        "players": null, "ecos": null, "dateStart": "not a date"
      },
      {"title": "no id or slug: dropped"}
    ],
    "total": 2, "limit": 100, "offset": 0
  }
}
''';

const _detailResponse = '''
{
  "status": "success",
  "data": {
    "id": "c2", "slug": "my-system", "kind": "book", "title": "My System",
    "author": "Aron Nimzowitsch", "annotator": null,
    "about": "First paragraph.\\n\\nSecond paragraph.",
    "gameCount": 4, "unsortedCount": 1,
    "sections": [
      {
        "id": "p2", "parentId": null, "kind": "part", "label": "Part II",
        "number": "II", "title": "Positional Play", "intro": null,
        "orderIndex": 2, "gameCount": 0,
        "children": [
          {"id": "ch3", "parentId": "p2", "kind": "chapter",
           "label": "Chapter 3", "number": "3", "title": "The Blockade",
           "intro": "Restrain, blockade, destroy.", "orderIndex": 1,
           "gameCount": 1, "children": null}
        ]
      },
      {
        "id": "p1", "parentId": null, "kind": "part", "label": "Part I",
        "number": "I", "title": "The Elements", "orderIndex": 1,
        "gameCount": 0,
        "children": [
          {"id": "ch2", "parentId": "p1", "kind": "chapter",
           "label": "Chapter 2", "number": "2", "title": "Open Files",
           "orderIndex": 2, "gameCount": 1},
          {"id": "ch1", "parentId": "p1", "kind": "chapter",
           "label": "Chapter 1", "number": "1", "title": "The Centre",
           "intro": "  ", "orderIndex": 1, "gameCount": 1,
           "startsOn": null, "sourceTag": "1. The Centre"}
        ]
      },
      {"id": "x", "kind": "appendix", "label": null, "title": "Extra",
       "orderIndex": 3}
    ]
  }
}
''';

const _pgnA = '''[Event "Casual"]
[White "Nimzowitsch, Aron"]
[Black "Systemsson, Max"]
[WhiteElo "2600"]
[Result "1-0"]

1. e4 {The centre.} e5 2. Nf3 \$1 Nc6 (2... d6) 3. Bb5 1-0''';

const _pgnB = '''[Event "Casual"]
[White "Systemsson, Max"]
[Black "Nimzowitsch, Aron"]
[Result "0-1"]

1. d4 d5 2. c4 0-1''';

Map<String, dynamic> _gameJson(
  String id, {
  String? sectionId,
  int orderIndex = 0,
  String white = 'Nimzowitsch, Aron',
  String black = 'Systemsson, Max',
  String? pgn,
}) {
  String key(String name) => 'name:${name.toLowerCase()}';
  return {
    'id': id,
    'sectionId': sectionId,
    'orderIndex': orderIndex,
    'white': {'name': white, 'key': key(white)},
    'black': {'name': black, 'key': key(black)},
    'result': '1-0',
    'finalFen': 'x',
    'lastMove': null,
    'plyCount': 5,
    'hasAnnotations': true,
    'contentHash': 'h-$id',
    'updatedAt': '2025-10-20T12:00:00.000Z',
    'pgn': ?pgn,
  };
}

CollectionGame _game(String id, {String? sectionId, int orderIndex = 0}) {
  final card = CollectionGameCard.fromJson(
    _gameJson(id, sectionId: sectionId, orderIndex: orderIndex, pgn: _pgnA),
  );
  return CollectionGame.fromCard(card)!;
}

/// Answers every request with one canned JSON body and status, so the real
/// Dio flow (a 4xx throws a DioException) runs against the repository.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status, this.body);

  final int status;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

GamebaseRepository _cannedGamebase(int status, String body) =>
    GamebaseRepository(
      Dio()..httpClientAdapter = _CannedAdapter(status, body),
      apiKey: 'test',
    );

class _FakeGamebase extends GamebaseRepository {
  _FakeGamebase(this.games) : super(Dio(), apiKey: 'test');

  final List<Map<String, dynamic>> games;
  final gameCalls = <({int offset, int limit, bool includePgn})>[];

  /// What the server caps a games page at.
  int serverPageCap = 200;

  @override
  Future<CollectionGamesPage> getCollectionGames(
    String slug, {
    String? section,
    String? playerKey,
    bool includePgn = false,
    int limit = 100,
    int offset = 0,
  }) async {
    gameCalls.add((offset: offset, limit: limit, includePgn: includePgn));
    final take = limit < serverPageCap ? limit : serverPageCap;
    return CollectionGamesPage.fromJson({
      'items': games.skip(offset).take(take).toList(),
      'total': games.length,
      'limit': take,
      'offset': offset,
    });
  }
}

void main() {
  group('collections API models', () {
    test('list page parses summaries and tolerates nulls / unknown keys', () {
      final page = CollectionsPage.fromJson(
        unwrapCollectionsEnvelope(jsonDecode(_listResponse)),
      );
      expect(page.total, 2);
      expect(page.items, hasLength(2));

      final event = page.items[0];
      expect(event.slug, 'us-championship-2025');
      expect(event.kind, CollectionKind.event);
      expect(event.annotator, 'GM Annotator');
      expect(event.coverUrl, isNull, reason: 'blank strings read as null');
      expect(event.location, 'Saint Louis');
      expect(event.dateStart, DateTime(2025, 10, 2));
      expect(event.dateEnd, DateTime(2025, 10, 14));
      expect(event.gameCount, 3);
      expect(event.players, ['Caruana, Fabiano', 'So, Wesley']);
      expect(event.ecos, ['C42', 'B90']);
      expect(event.contentVersion, 'a1b2c3');
      expect(event.sections, isEmpty, reason: 'summaries carry no tree');
      expect(event.about, isNull);

      final book = page.items[1];
      expect(book.kind, CollectionKind.book);
      expect(book.author, 'Aron Nimzowitsch');
      expect(book.publisher, 'Quality Chess');
      expect(book.publishedYear, 2016, reason: 'numeric strings parse');
      expect(book.gameCount, 12);
      expect(book.players, isEmpty);
      expect(book.ecos, isEmpty);
      expect(book.dateStart, isNull);
      expect(book.subtitle, isNull);
    });

    test('detail parses about and the section tree in order', () {
      final detail = Collection.fromJson(
        unwrapCollectionsEnvelope(jsonDecode(_detailResponse))
            as Map<String, dynamic>,
      );
      expect(detail.about, 'First paragraph.\n\nSecond paragraph.');
      expect(detail.unsortedCount, 1);
      expect(detail.sections.map((s) => s.id), ['p1', 'p2', 'x']);

      final part1 = detail.sections[0];
      expect(part1.kind, CollectionSectionKind.part);
      expect(part1.label, 'Part I');
      expect(part1.title, 'The Elements');
      expect(part1.children.map((s) => s.id), ['ch1', 'ch2']);

      final ch1 = part1.children[0];
      expect(ch1.kind, CollectionSectionKind.chapter);
      expect(ch1.parentId, 'p1');
      expect(ch1.number, '1');
      expect(ch1.title, 'The Centre');
      expect(ch1.intro, isNull, reason: 'whitespace-only intro is none');
      expect(ch1.sourceTag, '1. The Centre');
      expect(ch1.gameCount, 1);

      final ch3 = detail.sections[1].children.single;
      expect(ch3.intro, 'Restrain, blockade, destroy.');
      expect(ch3.children, isEmpty, reason: 'null children read as none');

      final unknown = detail.sections[2];
      expect(unknown.kind, CollectionSectionKind.other);
      expect(unknown.label, 'Extra', reason: 'missing label falls back');
    });

    test('games page parses cards, sides and the optional PGN', () {
      final page = CollectionGamesPage.fromJson({
        'items': [
          {
            ..._gameJson('g1', sectionId: 'r1', pgn: _pgnA),
            'white': {
              'name': 'Nimzowitsch, Aron',
              'elo': 2600,
              'title': 'GM',
              'fed': 'LAT',
              'fideId': 123456,
              'playerId': null,
              'key': 'fide:123456',
            },
            'board': '3',
            'playedOn': '1925-05-01',
            'eco': 'C60',
          },
          {
            'id': 'g2',
            'white': null,
            'black': {'name': '', 'elo': 0},
            'result': null,
            'plyCount': null,
          },
          {'white': {'name': 'no id'}},
        ],
        'total': '2',
        'limit': 100,
        'offset': 0,
      });
      expect(page.total, 2);
      expect(page.items, hasLength(2));

      final g1 = page.items[0];
      expect(g1.sectionId, 'r1');
      expect(g1.white.title, 'GM');
      expect(g1.white.elo, 2600);
      expect(g1.white.fideId, '123456', reason: 'numeric ids read as text');
      expect(g1.white.key, 'fide:123456');
      expect(g1.black.key, 'name:systemsson, max');
      expect(g1.board, 3);
      expect(g1.playedOn, DateTime(1925, 5, 1));
      expect(g1.eco, 'C60');
      expect(g1.hasAnnotations, isTrue);
      expect(g1.pgn, _pgnA);
      expect(g1.involves('fide:123456'), isTrue);
      expect(g1.involves('name:someone'), isFalse);

      final g2 = page.items[1];
      expect(g2.sectionId, isNull);
      expect(g2.white.name, 'White');
      expect(g2.black.name, 'Black');
      expect(g2.black.elo, isNull, reason: '0 is unrated');
      expect(g2.result, '*');
      expect(g2.plyCount, 0);
      expect(g2.pgn, isNull);
    });

    test('players parse from the {items} payload', () {
      final players = CollectionPlayer.listFromJson({
        'items': [
          {
            'key': 'fide:1',
            'name': 'Caruana, Fabiano',
            'title': 'GM',
            'fed': 'USA',
            'fideId': '2020009',
            'playerId': 'p-1',
            'bestElo': 2805,
            'games': 11,
            'wins': 5,
            'draws': 5,
            'losses': 1,
          },
          {
            'name': 'So, Wesley',
            'title': null,
            'bestElo': null,
            'games': '9',
            'extra': [1, 2],
          },
          {'name': null, 'games': 3},
        ],
      });
      expect(players, hasLength(2));
      expect(players[0].key, 'fide:1');
      expect(players[0].bestElo, 2805);
      expect(players[0].wins, 5);
      expect(players[0].draws, 5);
      expect(players[0].losses, 1);
      expect(players[1].key, 'name:so, wesley');
      expect(players[1].title, isNull);
      expect(players[1].bestElo, isNull);
      expect(players[1].games, 9);
      expect(CollectionPlayer.listFromJson(null), isEmpty);
    });

    test('an error envelope throws its message', () {
      expect(
        () => unwrapCollectionsEnvelope({
          'status': 'error',
          'error': {'message': 'Collection not found'},
        }),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Collection not found'),
          ),
        ),
      );
      expect(
        () => unwrapCollectionsEnvelope('<html>'),
        throwsA(isA<FormatException>()),
      );
    });

    test('a 4xx error envelope surfaces its message and status', () async {
      final api = _cannedGamebase(
        404,
        '{"status":"error","error":{"message":"Collection not found"}}',
      );
      await expectLater(
        api.getCollection('draft-slug'),
        throwsA(
          isA<CollectionsRequestException>()
              .having((e) => e.message, 'message', 'Collection not found')
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.toString(), 'toString', contains(' 404')),
        ),
      );

      final invalid = _cannedGamebase(
        400,
        '{"status":"error","error":{"message":"Failed to validate request",'
        '"details":[{"path":["limit"],"message":"Too big"}]}}',
      );
      await expectLater(
        invalid.getCollectionGames('slug'),
        throwsA(
          isA<CollectionsRequestException>().having(
            (e) => e.message,
            'message',
            'Failed to validate request',
          ),
        ),
      );
    });

    test('a failure without an envelope keeps the generic message', () async {
      final api = _cannedGamebase(502, '{"hello":1}');
      await expectLater(
        api.getCollections(),
        throwsA(
          isA<Exception>()
              .having(
                (e) => e,
                'type',
                isNot(isA<CollectionsRequestException>()),
              )
              .having(
                (e) => e.toString(),
                'message',
                contains('Failed to load collections: 502'),
              ),
        ),
      );
    });
  });

  group('collection games', () {
    test('a card with PGN becomes a board model at its final position', () {
      final game = _game('g1');
      expect(game.id, 'g1');
      expect(game.game.gameId, 'g1');
      expect(game.game.whitePlayer.name, 'Nimzowitsch, Aron');
      expect(game.game.whitePlayer.rating, 2600);
      expect(game.game.lastMove, 'f1b5');
      expect(game.game.pgn, contains('{The centre.}'));
      expect(game.game.fen, startsWith('r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/'));
    });

    test('a card without PGN is skipped', () {
      final card = CollectionGameCard.fromJson(_gameJson('g1'));
      expect(CollectionGame.fromCard(card), isNull);
    });
  });

  group('groupCollectionGames', () {
    const rounds = [
      CollectionSection(
        id: 'r2',
        kind: CollectionSectionKind.round,
        label: 'Round 2',
        orderIndex: 2,
      ),
      CollectionSection(
        id: 'r1',
        kind: CollectionSectionKind.round,
        label: 'Round 1',
        orderIndex: 1,
      ),
    ];

    test('event: rounds in the order given, games by orderIndex, unsorted '
        'last, offsets into the whole list', () {
      final groups = groupCollectionGames(rounds, [
        _game('b', sectionId: 'r1', orderIndex: 2),
        _game('u1'),
        _game('c', sectionId: 'r2', orderIndex: 1),
        _game('a', sectionId: 'r1', orderIndex: 1),
        _game('u2', sectionId: 'gone'),
      ]);
      expect(groups.map((g) => g.section?.id), ['r2', 'r1', null]);
      expect(groups.map((g) => g.games.map((x) => x.id).toList()), [
        ['c'],
        ['a', 'b'],
        ['u1', 'u2'],
      ]);
      expect(groups.map((g) => g.offset), [0, 1, 3]);
    });

    test('book: part headers lead their chapters; empty sections drop', () {
      final detail = Collection.fromJson(
        unwrapCollectionsEnvelope(jsonDecode(_detailResponse))
            as Map<String, dynamic>,
      );
      final groups = groupCollectionGames(detail.sections, [
        _game('g3', sectionId: 'ch3'),
        _game('g1', sectionId: 'ch1'),
        _game('u'),
      ]);
      expect(groups.map((g) => g.section?.id), [
        'p1',
        'ch1',
        'p2',
        'ch3',
        null,
      ]);
      expect(groups.map((g) => g.depth), [0, 1, 0, 1, 0]);
      expect(groups[0].games, isEmpty, reason: 'a part only leads');
      expect(groups.map((g) => g.offset), [0, 0, 1, 1, 2]);
      expect(
        groups.expand((g) => g.games).map((g) => g.id),
        ['g1', 'g3', 'u'],
      );
    });

    test('no sections: one headerless group', () {
      final groups = groupCollectionGames(const [], [_game('a'), _game('b')]);
      expect(groups, hasLength(1));
      expect(groups.single.section, isNull);
      expect(groups.single.games.map((g) => g.id), ['a', 'b']);
    });
  });

  group('CollectionsRepository', () {
    test('reads every page of games with PGN until the total', () async {
      final api = _FakeGamebase([
        for (var i = 0; i < 450; i++)
          _gameJson('g$i', orderIndex: i, pgn: i.isEven ? _pgnA : _pgnB),
      ]);
      final games = await CollectionsRepository(api).fetchGames('slug');
      expect(games, hasLength(450));
      expect(games.first.id, 'g0');
      expect(games.last.id, 'g449');
      expect(api.gameCalls.map((c) => c.offset), [0, 200, 400]);
      expect(api.gameCalls.every((c) => c.includePgn), isTrue);
    });

    test('steps by the page the server actually returned', () async {
      final api = _FakeGamebase([
        for (var i = 0; i < 120; i++) _gameJson('g$i', pgn: _pgnB),
      ])..serverPageCap = 50;
      final games = await CollectionsRepository(api).fetchGames('slug');
      expect(games.map((g) => g.id).toSet(), hasLength(120));
      expect(api.gameCalls.map((c) => c.offset), [0, 50, 100]);
    });

    test('drops games without PGN and duplicate ids', () async {
      final api = _FakeGamebase([
        _gameJson('a', pgn: _pgnA),
        _gameJson('b'),
        _gameJson('a', pgn: _pgnA),
      ]);
      final games = await CollectionsRepository(api).fetchGames('slug');
      expect(games.map((g) => g.id), ['a']);
    });
  });
}
