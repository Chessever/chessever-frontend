import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Start position. Explorer aggregates/games use this until a move is played.
const _startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// Position after 1.e4. dartchess omits e3 EP (no legal capture), so the
/// sanitizer keeps `e2e4` only when the 4-field key matches this FEN.
const _afterE2e4Fen =
    'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
const _matrixPlayerId = '00000000-0000-4000-8000-000000000001';

const _filterKeys = <String>{
  'timeControl',
  'minRating',
  'maxRating',
  'yearFrom',
  'yearTo',
  'isOnline',
  'result',
  'color',
  'playerId',
};

/// One non-default value on a live Opening Explorer filter axis.
class _AxisValue {
  const _AxisValue({
    required this.axis,
    required this.label,
    this.playerIds,
    this.timeControls,
    this.minRating,
    this.maxRating,
    this.yearFrom,
    this.yearTo,
    this.isOnline,
    this.gameResult,
    this.playerColor,
  });

  final String axis;
  final String label;
  final List<String>? playerIds;
  final List<TimeControl>? timeControls;
  final int? minRating;
  final int? maxRating;
  final int? yearFrom;
  final int? yearTo;
  final bool? isOnline;
  final GamebaseGameResult? gameResult;
  final GamebasePlayerColor? playerColor;
}

class _Case {
  const _Case({
    required this.kind,
    required this.parts,
    required this.filters,
    this.fen = _startFen,
    this.moves = const <String>[],
  });

  final String kind;
  final List<String> parts;
  final GamebaseFilters filters;
  final String fen;
  final List<String> moves;

  String get name {
    final suffix = moves.isEmpty ? '' : ' + moves=${moves.join(',')}';
    return '$kind ${parts.join(' + ')}$suffix';
  }
}

const _timeValues = <_AxisValue>[
  _AxisValue(
    axis: 'timeControls',
    label: 'time=classical',
    timeControls: [TimeControl.classical],
  ),
  _AxisValue(
    axis: 'timeControls',
    label: 'time=rapid',
    timeControls: [TimeControl.rapid],
  ),
  _AxisValue(
    axis: 'timeControls',
    label: 'time=blitz',
    timeControls: [TimeControl.blitz],
  ),
];

const _playerValues = <_AxisValue>[
  _AxisValue(
    axis: 'playerIds',
    label: 'player=scoped',
    playerIds: [_matrixPlayerId],
  ),
];

const _ratingValues = <_AxisValue>[
  _AxisValue(axis: 'rating', label: 'minRating=2400', minRating: 2400),
  _AxisValue(axis: 'rating', label: 'maxRating=2800', maxRating: 2800),
  _AxisValue(
    axis: 'rating',
    label: 'rating=2400-2800',
    minRating: 2400,
    maxRating: 2800,
  ),
];

const _yearValues = <_AxisValue>[
  _AxisValue(axis: 'year', label: 'yearFrom=2018', yearFrom: 2018),
  _AxisValue(axis: 'year', label: 'yearTo=2024', yearTo: 2024),
  _AxisValue(
    axis: 'year',
    label: 'year=2018-2024',
    yearFrom: 2018,
    yearTo: 2024,
  ),
];

const _isOnlineValues = <_AxisValue>[
  _AxisValue(axis: 'isOnline', label: 'isOnline=true', isOnline: true),
  _AxisValue(axis: 'isOnline', label: 'isOnline=false', isOnline: false),
];

const _resultValues = <_AxisValue>[
  _AxisValue(
    axis: 'gameResult',
    label: 'result=W',
    gameResult: GamebaseGameResult.whiteWins,
  ),
  _AxisValue(
    axis: 'gameResult',
    label: 'result=B',
    gameResult: GamebaseGameResult.blackWins,
  ),
  _AxisValue(
    axis: 'gameResult',
    label: 'result=D',
    gameResult: GamebaseGameResult.draw,
  ),
];

const _colorValues = <_AxisValue>[
  _AxisValue(
    axis: 'playerColor',
    label: 'color=white',
    playerIds: [_matrixPlayerId],
    playerColor: GamebasePlayerColor.white,
  ),
  _AxisValue(
    axis: 'playerColor',
    label: 'color=black',
    playerIds: [_matrixPlayerId],
    playerColor: GamebasePlayerColor.black,
  ),
];

const _allAxes = <List<_AxisValue>>[
  _playerValues,
  _timeValues,
  _ratingValues,
  _yearValues,
  _isOnlineValues,
  _resultValues,
  _colorValues,
];

_Case _caseFrom(
  String kind,
  List<_AxisValue> values, {
  String fen = _startFen,
  List<String> moves = const <String>[],
}) {
  var playerIds = const <String>[];
  var timeControls = const <TimeControl>[];
  int? minRating;
  int? maxRating;
  int? yearFrom;
  int? yearTo;
  bool? isOnline;
  GamebaseGameResult? gameResult;
  GamebasePlayerColor? playerColor;
  final parts = <String>[];

  for (final value in values) {
    if (value.playerIds != null) playerIds = value.playerIds!;
    if (value.timeControls != null) timeControls = value.timeControls!;
    if (value.minRating != null) minRating = value.minRating;
    if (value.maxRating != null) maxRating = value.maxRating;
    if (value.yearFrom != null) yearFrom = value.yearFrom;
    if (value.yearTo != null) yearTo = value.yearTo;
    if (value.isOnline != null) isOnline = value.isOnline;
    if (value.gameResult != null) gameResult = value.gameResult;
    if (value.playerColor != null) playerColor = value.playerColor;
    parts.add(value.label);
  }

  return _Case(
    kind: kind,
    parts: parts,
    fen: fen,
    moves: moves,
    filters: GamebaseFilters(
      playerIds: playerIds,
      timeControls: timeControls,
      minRating: minRating,
      maxRating: maxRating,
      yearFrom: yearFrom,
      yearTo: yearTo,
      isOnline: isOnline,
      gameResult: gameResult,
      playerColor: playerColor,
    ),
  );
}

List<_Case> _generateExplorerFilterMatrix() {
  final cases = <_Case>[
    const _Case(kind: 'empty', parts: ['none'], filters: GamebaseFilters()),
  ];

  for (final axis in _allAxes) {
    for (final value in axis) {
      cases.add(_caseFrom('single', [value]));
    }
  }

  for (var i = 0; i < _allAxes.length; i++) {
    for (var j = i + 1; j < _allAxes.length; j++) {
      for (final left in _allAxes[i]) {
        for (final right in _allAxes[j]) {
          cases.add(_caseFrom('pair', [left, right]));
        }
      }
    }
  }

  cases.addAll([
    _caseFrom('triple', [_timeValues[0], _ratingValues[2], _yearValues[2]]),
    _caseFrom('triple', [_timeValues[1], _isOnlineValues[0], _resultValues[0]]),
    _caseFrom('triple', [_timeValues[2], _colorValues[0], _resultValues[2]]),
    _caseFrom('triple', [_isOnlineValues[1], _yearValues[2], _colorValues[1]]),
    _caseFrom('triple', [_ratingValues[2], _resultValues[1], _colorValues[0]]),
    _caseFrom('triple', [_yearValues[0], _ratingValues[0], _isOnlineValues[0]]),
  ]);

  cases.addAll([
    _caseFrom(
      'filter+moves',
      [_timeValues[0]],
      fen: _afterE2e4Fen,
      moves: const ['e2e4'],
    ),
    _caseFrom(
      'filter+moves',
      [_resultValues[0], _colorValues[0]],
      fen: _afterE2e4Fen,
      moves: const ['e2e4'],
    ),
    _caseFrom(
      'filter+moves',
      [_ratingValues[2], _isOnlineValues[0]],
      fen: _afterE2e4Fen,
      moves: const ['e2e4'],
    ),
  ]);

  return cases;
}

/// Same mapping PositionGamesSheet / explorer aggregates use when calling the repo.
Map<String, dynamic> _aggregatesBody(_Case c) {
  return GamebaseRepository.buildMoveAggregatesQueryBody(
    fen: c.fen,
    moves: c.moves,
    timeControl:
        c.filters.timeControls.isNotEmpty ? c.filters.timeControls.first : null,
    playerId: c.filters.playerIds.isNotEmpty ? c.filters.playerIds.first : null,
    color: c.filters.playerColor?.name,
    result: c.filters.gameResult?.apiValue,
    isOnline: c.filters.isOnline,
    minRating: c.filters.minRating,
    maxRating: c.filters.maxRating,
    yearFrom: c.filters.yearFrom,
    yearTo: c.filters.yearTo,
  );
}

Map<String, dynamic> _gamesBody(
  _Case c, {
  GamebaseSortField? sortBy,
  GamebaseSortDirection? sortDirection,
}) {
  return GamebaseRepository.buildPositionGamesQueryBody(
    fen: c.fen,
    moves: c.moves,
    timeControl:
        c.filters.timeControls.isNotEmpty ? c.filters.timeControls.first : null,
    playerId: c.filters.playerIds.isNotEmpty ? c.filters.playerIds.first : null,
    color: c.filters.playerColor?.name,
    result: c.filters.gameResult?.apiValue,
    isOnline: c.filters.isOnline,
    minRating: c.filters.minRating,
    maxRating: c.filters.maxRating,
    yearFrom: c.filters.yearFrom,
    yearTo: c.filters.yearTo,
    sortBy: sortBy ?? c.filters.sortBy,
    sortDirection: sortDirection ?? c.filters.sortDirection,
  );
}

Map<String, dynamic> _fenGamesQuery(
  _Case c, {
  GamebaseSortField? sortBy,
  GamebaseSortDirection? sortDirection,
}) {
  return GamebaseRepository.buildFenPositionGamesQueryParameters(
    fen: c.fen,
    timeControl:
        c.filters.timeControls.isNotEmpty ? c.filters.timeControls.first : null,
    playerId: c.filters.playerIds.isNotEmpty ? c.filters.playerIds.first : null,
    color: c.filters.playerColor?.name,
    result: c.filters.gameResult?.apiValue,
    isOnline: c.filters.isOnline,
    minRating: c.filters.minRating,
    maxRating: c.filters.maxRating,
    yearFrom: c.filters.yearFrom,
    yearTo: c.filters.yearTo,
    sortBy: sortBy ?? c.filters.sortBy,
    sortDirection: sortDirection ?? c.filters.sortDirection,
  );
}

Map<String, dynamic> _expectedFilterFields(GamebaseFilters filters) {
  return GamebaseRepository.buildExplorerQueryFilterFields(
    timeControl:
        filters.timeControls.isNotEmpty ? filters.timeControls.first : null,
    playerId: filters.playerIds.isNotEmpty ? filters.playerIds.first : null,
    color: filters.playerColor?.name,
    result: filters.gameResult?.apiValue,
    isOnline: filters.isOnline,
    minRating: filters.minRating,
    maxRating: filters.maxRating,
    yearFrom: filters.yearFrom,
    yearTo: filters.yearTo,
  );
}

void _assertFilterFields(_Case c, Map<String, dynamic> body) {
  final reason = c.name;
  final expected = _expectedFilterFields(c.filters);

  expect(expected.keys, everyElement(_filterKeys.contains), reason: reason);

  for (final entry in expected.entries) {
    expect(
      body.containsKey(entry.key),
      isTrue,
      reason: '$reason missing ${entry.key}',
    );
    expect(body[entry.key], entry.value, reason: '$reason ${entry.key}');
  }

  for (final key in _filterKeys.difference(expected.keys.toSet())) {
    expect(body.containsKey(key), isFalse, reason: '$reason extra $key');
  }

  if (c.filters.timeControls.isNotEmpty) {
    expect(
      body['timeControl'],
      c.filters.timeControls.first.name.toUpperCase(),
      reason: reason,
    );
  }
  if (c.filters.minRating != null) {
    expect(body['minRating'], c.filters.minRating, reason: reason);
  }
  if (c.filters.yearFrom != null) {
    expect(body['yearFrom'], c.filters.yearFrom, reason: reason);
  }
  if (c.filters.isOnline != null) {
    expect(body['isOnline'], c.filters.isOnline, reason: reason);
  }
  if (c.filters.gameResult != null) {
    expect(body['result'], c.filters.gameResult!.apiValue, reason: reason);
  }
  if (c.filters.playerColor != null) {
    expect(body['color'], c.filters.playerColor!.name, reason: reason);
  }
}

void _assertRequestShapes(_Case c) {
  final aggregates = _aggregatesBody(c);
  final games = _gamesBody(c);
  final fenGames = _fenGamesQuery(c);

  _assertFilterFields(c, aggregates);
  _assertFilterFields(c, games);
  _assertFilterFields(c, fenGames);

  expect(aggregates['fen'], isNotEmpty, reason: c.name);
  expect(games['fen'], isNotEmpty, reason: c.name);
  expect(fenGames['fen'], isNotEmpty, reason: c.name);

  final aggregateFilters = Map<String, dynamic>.from(aggregates)
    ..removeWhere((key, _) => !_filterKeys.contains(key));
  final gameFilters = Map<String, dynamic>.from(games)
    ..removeWhere((key, _) => !_filterKeys.contains(key));
  final fenGameFilters = Map<String, dynamic>.from(fenGames)
    ..removeWhere((key, _) => !_filterKeys.contains(key));
  expect(gameFilters, aggregateFilters, reason: '${c.name} AND-combine');
  expect(
    fenGameFilters,
    aggregateFilters,
    reason: '${c.name} exact-FEN AND-combine',
  );

  if (c.moves.isNotEmpty) {
    expect(aggregates['moves'], c.moves, reason: c.name);
    expect(games['moves'], c.moves, reason: c.name);
  } else {
    expect(aggregates['moves'], isEmpty, reason: c.name);
    expect(games.containsKey('moves'), isFalse, reason: c.name);
  }
}

class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  Map<String, dynamic>? lastBody;
  Map<String, dynamic>? lastQuery;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (options.data is Map<String, dynamic>) {
      lastBody = Map<String, dynamic>.from(options.data as Map);
    }
    lastQuery = Map<String, dynamic>.from(options.queryParameters);
    final responseJson =
        options.path.contains('/games')
            ? '{"status":"success","data":[],"metadata":'
                '{"pageNumber":0,"pageSize":20,"hasMore":false}}'
            : '{"status":"success","data":{"moves":[]}}';
    return ResponseBody.fromString(
      responseJson,
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }
}

void main() {
  final cases = _generateExplorerFilterMatrix();
  final singles = cases.where((c) => c.kind == 'single').toList();
  final pairs = cases.where((c) => c.kind == 'pair').toList();
  final triples = cases.where((c) => c.kind == 'triple').toList();
  final moveCombos = cases.where((c) => c.kind == 'filter+moves').toList();

  test('explorer filter matrix covers singles, pairs, triples, and e2e4', () {
    expect(singles.length, 17);
    expect(pairs.length, 122);
    expect(triples.length, greaterThanOrEqualTo(5));
    expect(moveCombos.length, greaterThanOrEqualTo(2));
    expect(cases.length, 17 + 122 + triples.length + moveCombos.length + 1);
    expect(triples.every((c) => c.parts.length == 3), isTrue);
    expect(moveCombos.every((c) => c.moves.contains('e2e4')), isTrue);
  });

  test('empty filters omit every filter key', () {
    const empty = _Case(
      kind: 'empty',
      parts: ['none'],
      filters: GamebaseFilters(),
    );
    final aggregates = _aggregatesBody(empty);
    final games = _gamesBody(empty);
    final fenGames = _fenGamesQuery(empty);
    for (final key in _filterKeys) {
      expect(aggregates.containsKey(key), isFalse, reason: 'aggregates $key');
      expect(games.containsKey(key), isFalse, reason: 'games $key');
      expect(fenGames.containsKey(key), isFalse, reason: 'fen games $key');
    }
    expect(aggregates.keys.toSet(), {'fen', 'moves'});
    expect(games.containsKey('timeControl'), isFalse);
  });

  for (final c in cases) {
    test(c.name, () => _assertRequestShapes(c));
  }

  test(
    'opening explorer and position search cross every filter with every sort',
    () {
      for (final c in cases) {
        for (final sortBy in GamebaseSortField.values) {
          for (final direction in GamebaseSortDirection.values) {
            final reason = '${c.name} ${sortBy.name} ${direction.name}';
            final opening = _gamesBody(
              c,
              sortBy: sortBy,
              sortDirection: direction,
            );
            final position = _fenGamesQuery(
              c,
              sortBy: sortBy,
              sortDirection: direction,
            );

            _assertFilterFields(c, opening);
            _assertFilterFields(c, position);
            expect(opening['sortBy'], sortBy.name, reason: reason);
            expect(position['sortBy'], sortBy.name, reason: reason);
            expect(opening['sortDirection'], direction.name, reason: reason);
            expect(position['sortDirection'], direction.name, reason: reason);
          }
        }
      }
    },
  );

  test('getMoveAggregates POSTs the shipped aggregates body', () async {
    final adapter = _CapturingAdapter();
    final repo = GamebaseRepository(
      Dio()..httpClientAdapter = adapter,
      baseUrl: 'http://test',
      apiKey: 'test',
    );
    final c = _caseFrom('pair', [_timeValues[0], _resultValues[0]]);
    final expected = _aggregatesBody(c);

    await repo.getMoveAggregates(
      fen: c.fen,
      moves: c.moves,
      timeControl: TimeControl.classical,
      result: 'W',
    );

    expect(adapter.lastRequest?.method, 'POST');
    expect(adapter.lastRequest?.path, endsWith('/aggregates/query'));
    expect(adapter.lastBody, expected);
    expect(adapter.lastBody!['timeControl'], 'CLASSICAL');
    expect(adapter.lastBody!['result'], 'W');
    expect(adapter.lastBody!.containsKey('color'), isFalse);
  });

  test(
    'getPositionGames POSTs filter+e2e4 with the shipped games body',
    () async {
      final adapter = _CapturingAdapter();
      final repo = GamebaseRepository(
        Dio()..httpClientAdapter = adapter,
        baseUrl: 'http://test',
        apiKey: 'test',
      );
      final c = _caseFrom(
        'filter+moves',
        [_resultValues[0], _colorValues[0]],
        fen: _afterE2e4Fen,
        moves: const ['e2e4'],
      );
      final expected = _gamesBody(c);

      await repo.getPositionGames(
        fen: c.fen,
        moves: c.moves,
        playerId: _matrixPlayerId,
        color: 'white',
        result: 'W',
        sortBy: GamebaseSortField.date,
        sortDirection: GamebaseSortDirection.desc,
      );

      expect(adapter.lastRequest?.method, 'POST');
      expect(adapter.lastRequest?.path, endsWith('/games/query'));
      expect(adapter.lastBody, expected);
      expect(adapter.lastBody!['moves'], ['e2e4']);
      expect(adapter.lastBody!['result'], 'W');
      expect(adapter.lastBody!['color'], 'white');
      expect(adapter.lastBody!.containsKey('timeControl'), isFalse);
    },
  );

  test('getFenPositionGames GETs the same filters and sort', () async {
    final adapter = _CapturingAdapter();
    final repo = GamebaseRepository(
      Dio()..httpClientAdapter = adapter,
      baseUrl: 'http://test',
      apiKey: 'test',
    );
    final c = _caseFrom('triple', [
      _timeValues[2],
      _yearValues[2],
      _isOnlineValues[1],
    ]);
    final expected = _fenGamesQuery(
      c,
      sortBy: GamebaseSortField.avgElo,
      sortDirection: GamebaseSortDirection.asc,
    );

    await repo.getFenPositionGames(
      fen: c.fen,
      timeControl: TimeControl.blitz,
      yearFrom: 2018,
      yearTo: 2024,
      isOnline: false,
      sortBy: GamebaseSortField.avgElo,
      sortDirection: GamebaseSortDirection.asc,
    );

    expect(adapter.lastRequest?.method, 'GET');
    expect(adapter.lastRequest?.path, endsWith('/fen/games'));
    expect(adapter.lastQuery, expected);
  });
}
