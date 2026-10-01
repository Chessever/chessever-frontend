import 'dart:convert';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/repository/gamebase_repository.dart'
    as legacy;
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _playerId = '00000000-0000-4000-8000-000000000001';
const _line = <String>[
  'e2e4',
  'e7e5',
  'g1f3',
  'b8c6',
  'f1b5',
  'a7a6',
  'b5a4',
  'g8f6',
  'e1h1',
  'f8e7',
  'f1e1',
  'b7b5',
  'a4b3',
  'd7d6',
  'c2c3',
  'e8h8',
  'h2h3',
  'c6b8',
  'd2d4',
  'b8d7',
  'b1d2',
  'c8b7',
];

String _fenAfter(List<String> moves) {
  Position position = Chess.initial;
  for (final move in moves) {
    position = position.play(NormalMove.fromUci(move));
  }
  return position.fen;
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(
        options.path.contains('aggregates')
            ? {
                'status': 'success',
                'data': {'moves': []},
              }
            : {
                'status': 'success',
                'data': [],
                'metadata': {'pageNumber': 0, 'pageSize': 20, 'hasMore': false},
              },
      ),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }
}

void main() {
  late _Adapter adapter;
  late GamebaseRepository repository;
  setUp(() {
    adapter = _Adapter();
    repository = GamebaseRepository(
      Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://example.test',
      apiKey: 'test',
    );
  });

  test(
    'deep games and aggregates send counters of the verified line',
    () async {
      final expectedFen = _fenAfter(_line);
      final key = expectedFen.split(' ').take(4).join(' ');
      for (final inputFen in [key, '$key 99 99', '$key 0 1']) {
        final request = repository.positionGamesRequest(
          fen: inputFen,
          moves: _line,
          sortBy: GamebaseSortField.whiteElo,
          sortDirection: GamebaseSortDirection.desc,
        );
        expect(request.method, 'POST');
        expect(request.payload['fen'], expectedFen);
        expect(request.payload['moves'], hasLength(22));
        expect((request.payload['moves'] as List)[8], 'e1g1');
        expect((request.payload['moves'] as List)[15], 'e8g8');
        expect(request.payload['orderBy'], [
          {'field': 'whiteElo', 'direction': 'desc'},
        ]);
        await repository.getMoveAggregates(fen: inputFen, moves: _line);
        expect((adapter.requests.last.data as Map)['fen'], expectedFen);
        expect(
          (adapter.requests.last.data as Map)['moves'],
          request.payload['moves'],
        );
      }
    },
  );

  test('pseudo en-passant does not discard a valid line', () {
    const fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
    final request = repository.positionGamesRequest(
      fen: fen,
      moves: [' E2E4 '],
    );
    expect(request.method, 'POST');
    expect(request.payload['fen'], _fenAfter(['e2e4']));
    expect(request.payload['moves'], ['e2e4']);
  });

  test(
    'a stale or malformed history cannot replace the requested board',
    () async {
      final fen = _fenAfter(_line);
      for (final moves in [
        ['d2d4', 'd7d5'],
        ['bad-token', ..._line],
        [..._line, 'e2e4'],
      ]) {
        final request = repository.positionGamesRequest(fen: fen, moves: moves);
        expect(request.method, 'GET');
        expect(request.payload['fen'], fen);
        expect(request.payload.containsKey('moves'), isFalse);
        await repository.getMoveAggregates(fen: fen, moves: moves);
        expect((adapter.requests.last.data as Map)['fen'], fen);
        expect((adapter.requests.last.data as Map)['moves'], isEmpty);
      }
    },
  );

  test('selected castling uses standard UCI on line and FEN endpoints', () {
    final moves = _line.take(8).toList();
    final fen = _fenAfter(moves);
    for (final uci in [' E1H1 ', 'e1g1']) {
      final line = repository.positionGamesRequest(
        fen: fen,
        moves: moves,
        uci: uci,
      );
      final exact = repository.fenPositionGamesRequest(fen: fen, uci: uci);
      expect(line.payload['fen'], fen);
      expect(exact.payload['fen'], fen);
      expect(line.payload['uci'], 'e1g1');
      expect(exact.payload['uci'], 'e1g1');
    }
  });

  test('illegal selected moves and malformed FEN fail before HTTP', () async {
    final fen = _fenAfter(_line);
    for (final uci in ['e2e4', 'e1h1', 'bad']) {
      await expectLater(
        repository.getPositionGames(fen: fen, uci: uci),
        throwsException,
      );
      await expectLater(
        repository.getFenPositionGames(fen: fen, uci: uci),
        throwsException,
      );
    }
    for (final badFen in [
      '',
      'not a fen',
      '$fen extra',
      fen.replaceFirst(' 12', ' 0'),
    ]) {
      await expectLater(
        repository.getMoveAggregates(fen: badFen),
        throwsException,
      );
    }
    expect(adapter.requests, isEmpty);
  });

  test(
    'filters, descending Elo, pagination and continuation are identical',
    () async {
      final fen = _fenAfter(_line);
      final request = repository.positionGamesRequest(
        fen: fen,
        moves: _line,
        uci: ' A2A3 ',
        playerId: ' $_playerId ',
        timeControl: TimeControl.classical,
        color: ' WHITE ',
        result: ' d ',
        minRating: 2400,
        maxRating: 2800,
        yearFrom: 2018,
        yearTo: 2024,
        isOnline: false,
        sortBy: GamebaseSortField.whiteElo,
        sortDirection: GamebaseSortDirection.desc,
        pageNumber: 2,
        pageSize: 25,
        notationPlies: 40,
      );
      final exact = repository.fenPositionGamesRequest(
        fen: fen,
        uci: ' A2A3 ',
        playerId: ' $_playerId ',
        timeControl: TimeControl.classical,
        color: ' WHITE ',
        result: ' d ',
        minRating: 2400,
        maxRating: 2800,
        yearFrom: 2018,
        yearTo: 2024,
        isOnline: false,
        sortBy: GamebaseSortField.whiteElo,
        sortDirection: GamebaseSortDirection.desc,
        pageNumber: 2,
        pageSize: 25,
        notationPlies: 40,
      );
      final lineFields = Map<String, dynamic>.from(request.payload)
        ..remove('moves')
        ..remove('orderBy');
      expect(lineFields, exact.payload);
      expect(lineFields, {
        'fen': fen,
        'uci': 'a2a3',
        'playerId': _playerId,
        'timeControl': 'CLASSICAL',
        'color': 'white',
        'result': 'D',
        'minRating': 2400,
        'maxRating': 2800,
        'yearFrom': 2018,
        'yearTo': 2024,
        'isOnline': false,
        'sortBy': 'whiteElo',
        'sortDirection': 'desc',
        'pageNumber': 2,
        'pageSize': 25,
        'notationPlies': 20,
      });
      await repository.getPositionGames(fen: fen, moves: _line, uci: ' D4D5 ');
      expect(adapter.requests.single.method, 'POST');
      expect((adapter.requests.single.data as Map)['uci'], 'd4d5');
    },
  );

  test('invalid filters and pagination fail rather than broaden a query', () {
    final fen = _fenAfter(_line);
    for (final build in <GamebaseWireRequest Function()>[
      () => repository.positionGamesRequest(fen: fen, playerId: 'player-name'),
      () => repository.positionGamesRequest(fen: fen, minRating: 0),
      () => repository.positionGamesRequest(
        fen: fen,
        minRating: 2800,
        maxRating: 2400,
      ),
      () => repository.positionGamesRequest(
        fen: fen,
        yearFrom: 2024,
        yearTo: 2018,
      ),
      () => repository.positionGamesRequest(fen: fen, color: 'all'),
      () => repository.positionGamesRequest(fen: fen, result: '1-0'),
      () => repository.positionGamesRequest(fen: fen, pageNumber: -1),
      () => repository.positionGamesRequest(fen: fen, pageSize: 51),
      () => repository.fenPositionGamesRequest(fen: fen, notationPlies: -1),
    ]) {
      expect(build, throwsArgumentError);
    }
    expect(adapter.requests, isEmpty);
  });

  test('legacy FEN aggregates use the same request validation', () async {
    final sent = <http.Request>[];
    final client = MockClient((request) async {
      sent.add(request);
      return http.Response('{"data":{"moves":[]}}', 200);
    });
    final repo = legacy.GamebaseRepository(
      client: client,
      baseUrl: 'https://example.test',
      apiKey: 'test',
    );
    addTearDown(repo.dispose);
    const fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3';
    await repo.getPositionAggregates(
      fen: fen,
      playerId: ' $_playerId ',
      timeControl: TimeControl.blitz,
      minRating: 2400,
      maxRating: 2800,
    );
    expect(sent.single.url.queryParameters, {
      'fen': _fenAfter(['e2e4']),
      'playerId': _playerId,
      'timeControl': 'BLITZ',
      'minRating': '2400',
      'maxRating': '2800',
    });
    await expectLater(
      repo.getPositionAggregates(fen: fen, playerId: 'player-name'),
      throwsA(isA<legacy.GamebaseApiException>()),
    );
    expect(sent, hasLength(1));
  });
}
