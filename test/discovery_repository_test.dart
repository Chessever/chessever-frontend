import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_game.dart';
import 'package:chessever2/screens/my_space/models/space_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------- doubles

/// Most Liked must never go back to the full list read (`getGamesByIds`
/// selects the PGN): any call here fails the lookup and the test with it.
class _NoGameRepository implements GameRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

class _NoTours implements TourRepository {
  @override
  Future<List<Tour>> getToursByIds(List<String> tourIds) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

class _NoArchive implements GamebaseRepository {
  @override
  Future<GamebaseGame?> getGameById(String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

class _StalledClient extends http.BaseClient {
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    final abort = (request as http.AbortableRequest).abortTrigger;
    if (abort == null) {
      throw StateError('A stalled Reports read must be cancellable');
    }
    await abort;
    throw http.RequestAbortedException(request.url);
  }
}

/// Counts Analyzed games reads; nothing else is expected of it.
class _CountingRepository implements DiscoveryRepository {
  int analyzedReads = 0;
  int failuresRemaining = 0;

  @override
  Future<List<GamesTourModel>> fetchAnalyzedGames({
    int limit = 10,
    DateTime? now,
  }) async {
    analyzedReads++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('Reports temporarily unavailable');
    }
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

// ---------------------------------------------------------------- fixtures

/// A real game replayed with dartchess, so the fen column is written exactly
/// the way the model's PGN replay writes it.
({String pgn, String fen, String previousFen, String lastUci}) _play(
  List<String> sans, {
  required String result,
}) {
  Position position = Chess.initial;
  var previous = position.fen;
  Move? last;
  final text = StringBuffer();
  for (var i = 0; i < sans.length; i++) {
    final move = position.parseSan(sans[i])!;
    previous = position.fen;
    position = position.play(move);
    last = move;
    if (i.isEven) text.write('${i ~/ 2 + 1}. ');
    // Clocks count down from 1:30:00, a minute per move.
    final left = 5400 - 60 * (i ~/ 2 + 1);
    final clock =
        '${left ~/ 3600}:${((left % 3600) ~/ 60).toString().padLeft(2, '0')}:00';
    text.write('${sans[i]} {[%clk $clock]} ');
  }
  final pgn =
      '[Event "Test Masters"]\n'
      '[White "Carlsen, Magnus"]\n'
      '[Black "Caruana, Fabiano"]\n'
      '[Result "$result"]\n'
      '[ECO "C84"]\n'
      '[Opening "Ruy Lopez: Closed"]\n\n'
      '$text$result';
  return (
    pgn: pgn,
    fen: position.fen,
    previousFen: previous,
    lastUci: last!.uci,
  );
}

final _ruy = _play([
  'e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Ba4', 'Nf6', //
  'O-O', 'Be7', 'Re1', 'b5', 'Bb3', 'd6', 'c3', 'O-O', 'h3',
], result: '1/2-1/2');

final _italian = _play([
  'e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5', 'O-O', //
], result: '1-0');

/// A full `games` row as the list read returns it (PGN included).
Map<String, dynamic> _row(
  String id, {
  required ({String pgn, String fen, String previousFen, String lastUci}) game,
  String status = '1/2-1/2',
  String? fen,
  String? lastMove,
  int? whiteClock = 5040,
  int? blackClock = 5040,
  int playerClock = 0,
  String? eco = 'C84',
  String? opening = 'Ruy Lopez: Closed',
  String? tc = '90+30',
}) {
  return {
    'id': id,
    'round_id': 'round-1',
    'round_slug': 'round-1',
    'tour_id': 'tour-1',
    'tour_slug': 'test-masters',
    'name': 'Carlsen - Caruana',
    'fen': fen ?? game.fen,
    'pgn': game.pgn,
    'players': [
      for (final (name, rating) in [
        ('Carlsen, Magnus', 2837),
        ('Caruana, Fabiano', 2795),
      ])
        {
          'name': name,
          'title': 'GM',
          'rating': rating,
          'fideId': rating,
          'fed': 'NOR',
          'clock': playerClock,
          'team': '',
        },
    ],
    'last_move': lastMove ?? game.lastUci,
    'status': status,
    'board_nr': 1,
    'last_move_time': '2026-09-23T14:05:00Z',
    'game_day': '2026-09-23',
    'last_clock_white': whiteClock,
    'last_clock_black': blackClock,
    'eco': eco,
    'opening_name': opening,
    'tours': {
      'avg_elo': 2750,
      'tc': tc,
      'group_broadcasts': {'time_control': 'standard'},
    },
  };
}

Map<String, dynamic> _withoutPgn(Map<String, dynamic> row) =>
    Map<String, dynamic>.of(row)..remove('pgn');

GamesTourModel _model(Map<String, dynamic> row) =>
    GamesTourModel.fromGame(Games.fromJson(row));

/// Everything a Most Liked game shows or hands on: every model field but
/// the PGN text itself, the board-preview test and the My Space snapshot.
Map<String, Object?> _shown(GamesTourModel g) => {
  'id': g.gameId,
  'source': g.source,
  'white': g.whitePlayer,
  'black': g.blackPlayer,
  'whiteTime': g.whiteTimeDisplay,
  'blackTime': g.blackTimeDisplay,
  'whiteCs': g.whiteClockCentiseconds,
  'blackCs': g.blackClockCentiseconds,
  'whiteSec': g.whiteClockSeconds,
  'blackSec': g.blackClockSeconds,
  'status': g.gameStatus,
  'fen': g.fen,
  'lastMove': g.lastMove,
  'board': g.boardNr,
  'round': g.roundId,
  'roundSlug': g.roundSlug,
  'tour': g.tourId,
  'tourSlug': g.tourSlug,
  'lastMoveTime': g.lastMoveTime,
  'dateStart': g.dateStart,
  'gameDay': g.gameDay,
  'eco': g.eco,
  'opening': g.openingName,
  'tc': g.timeControl,
  'tcText': g.timeControlText,
  'avgElo': g.avgElo,
  'online': g.isOnline,
  'deferred': g.isPgnDeferred,
  'realPosition': discoveryHasRealPosition(g),
  'snapshot': spaceGameCardParams(g),
};

/// Every shape a liked broadcast row comes in, and whether its columns
/// alone are enough.
final _cases = <String, ({Map<String, dynamic> row, bool needsPgn})>{
  'finished, every column filled': (
    row: _row('lean', game: _ruy),
    needsPgn: false,
  ),
  'castled last (Lichess e1g1)': (
    row: _row('castled', game: _italian, status: '1-0', lastMove: 'e1g1'),
    needsPgn: false,
  ),
  'clock in the player entry only': (
    row: _row(
      'player_clock',
      game: _ruy,
      whiteClock: null,
      blackClock: null,
      playerClock: 504000,
    ),
    needsPgn: false,
  ),
  'no clock columns': (
    row: _row('no_clock', game: _ruy, whiteClock: null, blackClock: null),
    needsPgn: true,
  ),
  'no ECO': (row: _row('no_eco', game: _ruy, eco: null), needsPgn: true),
  'unknown opening name': (
    row: _row('no_opening', game: _ruy, opening: 'Unknown'),
    needsPgn: true,
  ),
  'fen a move behind': (
    row: _row('lagging', game: _ruy, fen: _ruy.previousFen),
    needsPgn: true,
  ),
  'fen written another way': (
    row: _row(
      'short_fen',
      game: _ruy,
      fen: _ruy.fen.split(' ').take(4).join(' '),
    ),
    needsPgn: true,
  ),
  'still being played': (
    row: _row('live', game: _ruy, status: '*'),
    needsPgn: true,
  ),
  'no last move': (
    row: _row('no_last_move', game: _ruy)..['last_move'] = null,
    needsPgn: true,
  ),
  'second time period': (
    row: _row(
      'second_period',
      game: _ruy,
      tc: '90 min / 40 moves + 30 min + 30 sec / move',
    ),
    needsPgn: true,
  ),
};

http.Response _json(Object body, http.BaseRequest request, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    request: request,
    headers: {'content-type': 'application/json'},
  );
}

List<String> _inIds(String filter) => filter
    .replaceFirst('in.(', '')
    .replaceFirst(RegExp(r'\)$'), '')
    .replaceAll('"', '')
    .split(',');

void main() {
  group('Most Liked without the PGN', () {
    test('a row asks for its PGN exactly when its columns fall short', () {
      for (final MapEntry(key: name, value: c) in _cases.entries) {
        expect(
          discoveryGameNeedsPgn(Games.fromJson(_withoutPgn(c.row))),
          c.needsPgn,
          reason: name,
        );
      }
    });

    test('what the columns build is what the full row built', () {
      for (final MapEntry(key: name, value: c) in _cases.entries) {
        final full = _model(c.row);
        final lean = _model(c.needsPgn ? c.row : _withoutPgn(c.row));
        expect(_shown(lean), _shown(full), reason: name);
      }
    });

    test('each fallback is load-bearing: without the PGN it would differ', () {
      for (final name in [
        'no clock columns',
        'no ECO',
        'unknown opening name',
        'fen a move behind',
        'fen written another way',
      ]) {
        final row = _cases[name]!.row;
        expect(
          _shown(_model(_withoutPgn(row))),
          isNot(_shown(_model(row))),
          reason: name,
        );
      }
    });

    Future<MostLikedResult> fetch({
      required List<Map<String, dynamic>> rows,
      required List<String> listSelects,
      required List<List<String>> pgnReads,
      bool pgnReadFails = false,
    }) async {
      final byId = {for (final r in rows) r['id'] as String: r};
      final client = SupabaseClient(
        'https://example.test',
        'placeholder',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/rpc/most_liked_ranking_preview')) {
            return _json([
              for (var i = 0; i < rows.length; i++)
                {'source_game_id': rows[i]['id'], 'like_count': 100 - i},
            ], request);
          }
          expect(request.url.path, endsWith('/games'));
          final query = request.url.queryParameters;
          final columns = query['select']!.split(',');
          final ids = _inIds(query['id']!);
          if (columns.contains('pgn')) {
            expect(columns, ['id', 'pgn']);
            pgnReads.add(ids);
            if (pgnReadFails) {
              return _json(
                {'message': 'statement timeout'},
                request,
                status: 500,
              );
            }
            return _json([
              for (final id in ids) {'id': id, 'pgn': byId[id]!['pgn']},
            ], request);
          }
          listSelects.add(query['select']!);
          return _json([
            for (final id in ids)
              if (byId[id] case final row?) _withoutPgn(row),
          ], request);
        }),
      );
      addTearDown(client.dispose);
      return DiscoveryRepository(
        client: () => client,
        games: _NoGameRepository(),
        tours: _NoTours(),
        gamebase: _NoArchive(),
      ).fetchMostLiked(MostLikedQuery(MostLikedPeriod.today, DateTime.now()));
    }

    test('one lean list read, then one PGN read for the rows that need it, '
        'and the same games come out', () async {
      final rows = [for (final c in _cases.values) c.row];
      final listSelects = <String>[];
      final pgnReads = <List<String>>[];
      final result = await fetch(
        rows: rows,
        listSelects: listSelects,
        pgnReads: pgnReads,
      );

      expect(listSelects, hasLength(1));
      expect(listSelects.single.split(','), isNot(contains('pgn')));
      expect(listSelects.single.split(','), isNot(contains('search')));
      expect(pgnReads, hasLength(1));
      expect(pgnReads.single.toSet(), {
        for (final c in _cases.values)
          if (c.needsPgn) c.row['id'] as String,
      });

      expect(result.status, MostLikedStatus.ranked);
      expect(result.entries.map((e) => e.game.gameId), [
        for (final r in rows) r['id'],
      ]);
      for (final entry in result.entries) {
        final full = rows.firstWhere((r) => r['id'] == entry.game.gameId);
        expect(
          _shown(entry.game),
          _shown(_model(full)),
          reason: '${full['id']}',
        );
        expect(entry.rank, rows.indexOf(full) + 1);
      }
    });

    test('rows that need no PGN cost no second read', () async {
      final pgnReads = <List<String>>[];
      final result = await fetch(
        rows: [
          for (final c in _cases.values)
            if (!c.needsPgn) c.row,
        ],
        listSelects: [],
        pgnReads: pgnReads,
      );
      expect(pgnReads, isEmpty);
      expect(result.entries, hasLength(3));
    });

    test('a failed PGN read keeps every game in the ranking', () async {
      final rows = [for (final c in _cases.values) c.row];
      final result = await fetch(
        rows: rows,
        listSelects: [],
        pgnReads: [],
        pgnReadFails: true,
      );
      expect(result.entries, hasLength(rows.length));
    });
  });

  group('Saved Reports eligibility', () {
    const reportPgn =
        r'1. e4 $247 {[%eval 0.20]} e5 $247 {[%eval 0.10]} 1/2-1/2';

    Map<String, dynamic> reportRow(
      String id, {
      String status = '1/2-1/2',
      String? pgn = reportPgn,
    }) => {..._row(id, game: _ruy, status: status), 'pgn': pgn};

    Future<List<GamesTourModel>> fetch(
      List<Map<String, dynamic>> rows, {
      int limit = 10,
      void Function(Uri)? inspect,
    }) async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.test',
        'placeholder',
        httpClient: MockClient((request) async {
          requests.add(request);
          return _json(rows, request);
        }),
      );
      addTearDown(client.dispose);
      final result = await DiscoveryRepository(
        client: () => client,
        games: _NoGameRepository(),
        tours: _NoTours(),
        gamebase: _NoArchive(),
      ).fetchAnalyzedGames(limit: limit, now: DateTime.utc(2026, 9, 24));
      for (final request in requests) {
        expect(request.method, 'GET');
        expect(request.url.path, endsWith('/games'));
        inspect?.call(request.url);
      }
      return result;
    }

    test('reads existing PGN columns with a bounded report filter', () async {
      var reads = 0;
      final result = await fetch(
        [reportRow('saved-report')],
        inspect: (uri) {
          reads++;
          final query = uri.queryParameters;
          expect(uri.toString(), isNot(contains('cloudflare_report')));
          expect(query['last_move_time'], 'gte.2026-09-21T00:00:00.000Z');
          expect(
            _inIds(query['status']!),
            containsAll(['1-0', '0-1', '1/2-1/2']),
          );
          expect(query['pgn'], r'like.%[\%eval %');
          expect(
            query['or'],
            r'(pgn.like.%$24%,pgn.ilike.%chessever_annotation%)',
          );
          expect(
            query['select']!.split(',').map((s) => s.trim()),
            contains('pgn'),
          );
          expect(
            query['order'],
            'last_move_time.desc.nullslast,id.asc.nullslast',
          );
          expect(query['limit'], '30');
        },
      );
      expect(reads, 1);
      expect(result.map((game) => game.gameId), ['saved-report']);
      expect(result.single.pgn, reportPgn);
    });

    test(
      'accepts every current report classification with an evaluation',
      () async {
        final result = await fetch([
          for (var nag = 240; nag <= 247; nag++)
            reportRow(
              'report-$nag',
              pgn: '1. e4 \$$nag {[%eval 0.2]} e5 1/2-1/2',
            ),
        ]);
        expect(result.map((game) => game.gameId), [
          for (var nag = 240; nag <= 247; nag++) 'report-$nag',
        ]);
      },
    );

    test('accepts the Cloudflare writeback fixture unchanged', () async {
      // Same annotated PGN as apps/analysis/test/report-writeback.test.ts.
      const workerPgn = r'''[Event "Test"]
[Result "1-0"]

1. e4 $1 $242 { [%eval 0.32] } e5 $6 $244 { [%eval 0.55] }
2. Nf3 $3 $240 { [%eval 0.28] } Nc6 $247 { [%eval 0.41] } 1-0''';
      final result = await fetch([
        reportRow('cloudflare-report', pgn: workerPgn, status: '1-0'),
      ]);
      expect(result.single.gameId, 'cloudflare-report');
      expect(result.single.pgn, workerPgn);
    });

    test('retains legacy reports and mate or depth-bearing scores', () async {
      final result = await fetch([
        reportRow(
          'legacy',
          pgn:
              '1. e4 {[%chessever_annotation book_move] [%eval 0.2]} e5 1/2-1/2',
        ),
        reportRow(
          'legacy-case',
          pgn:
              '1. e4 {[% CHESSEVER_ANNOTATION best-move] [%eval -0.5]} e5 1/2-1/2',
        ),
        reportRow('depth', pgn: r'1. e4 $242 {[%eval 0.2,18]} e5 1/2-1/2'),
        reportRow('mate', pgn: r'1. e4 $246 {[%eval #-3]} e5 1/2-1/2'),
      ]);
      expect(result.map((game) => game.gameId), [
        'depth',
        'legacy',
        'legacy-case',
        'mate',
      ]);
    });

    test(
      'excludes ordinary evaluations, glyphs and unevaluated annotations',
      () async {
        final result = await fetch([
          reportRow('eval-only', pgn: '1. e4 {[%eval 0.2]} e5 1/2-1/2'),
          reportRow('glyphs', pgn: r'1. e4 $1 {[%eval 0.2]} e5 $6 1/2-1/2'),
          reportRow('annotation-only', pgn: r'1. e4 $247 e5 1/2-1/2'),
          reportRow(
            'invalid-score',
            pgn: r'1. e4 $247 {[%eval unknown]} e5 1/2-1/2',
          ),
          reportRow(
            'different-moves',
            pgn: r'1. e4 $247 e5 {[%eval 0.2]} 1/2-1/2',
          ),
          for (final nag in [239, 248, 249, 2400])
            reportRow(
              'other-$nag',
              pgn: '1. e4 \$$nag {[%eval 0.2]} e5 1/2-1/2',
            ),
          reportRow(
            'unknown-legacy',
            pgn:
                '1. e4 {[%chessever_annotation unknown] [%eval 0.2]} e5 1/2-1/2',
          ),
          reportRow('saved-report'),
        ]);
        expect(result.map((game) => game.gameId), ['saved-report']);
      },
    );

    test('ignores report-like text outside the played mainline', () async {
      final result = await fetch([
        reportRow(
          'comment',
          pgn: r'1. e4 {The report uses $240 [%eval 0.2]} e5 1/2-1/2',
        ),
        reportRow(
          'header',
          pgn: '[Event "\$240 [%eval 0.2]"]\n\n1. e4 e5 1/2-1/2',
        ),
        reportRow(
          'variation',
          pgn: r'1. e4 {[%eval 0.2]} (1. d4 $247 {[%eval 0.3]} d5) e5 1/2-1/2',
        ),
        reportRow(
          'starting-comment',
          pgn:
              '{[%chessever_annotation book_move] [%eval 0.2]} 1. e4 e5 1/2-1/2',
        ),
        reportRow(
          'second-game',
          pgn: '1. e4 e5 1/2-1/2\n\n[Event "Report"]\n\n$reportPgn',
        ),
        reportRow('saved-report'),
      ]);
      expect(result.map((game) => game.gameId), ['saved-report']);
    });

    test(
      'skips live games and unreadable rows without hiding valid reports',
      () async {
        final result = await fetch([
          reportRow('live', status: '*'),
          reportRow('missing-pgn', pgn: null),
          reportRow('empty-pgn', pgn: ''),
          reportRow('invalid-pgn', pgn: '[Event "unfinished'),
          {...reportRow('invalid-players'), 'players': []},
          reportRow('white-wins', status: '1-0'),
          reportRow('black-wins', status: '0-1'),
          reportRow('draw'),
        ]);
        expect(result.map((game) => game.gameId), [
          'black-wins',
          'draw',
          'white-wins',
        ]);
      },
    );

    test('ranks and limits after excluding non-reports', () async {
      final result = await fetch([
        reportRow('no-report', pgn: '1. e4 {[%eval 0.2]} e5 1/2-1/2'),
        reportRow('report-b'),
        reportRow('report-a'),
      ], limit: 1);
      expect(result.map((game) => game.gameId), ['report-a']);
    });

    test('does not query for an empty requested list', () async {
      expect(
        await fetch([], limit: 0, inspect: (_) => fail('Unexpected read')),
        isEmpty,
      );
    });
  });

  group('Reports cursor pages', () {
    late List<Map<String, dynamic>> rows;
    late List<http.Request> requests;
    late DiscoveryRepository repository;

    Map<String, dynamic> report(
      String id, {
      String? time = '2026-09-24T12:00:00.123456+00:00',
      bool valid = true,
    }) => {
      ..._row(id, game: _ruy),
      'last_move_time': time,
      'pgn': valid
          ? r'1. e4 $247 {[%eval 0.2]} e5 1/2-1/2'
          : '1. e4 {[%eval 0.2]} e5 1/2-1/2',
    };

    setUp(() {
      rows = [];
      requests = [];
      final client = SupabaseClient(
        'https://example.test',
        'placeholder',
        httpClient: MockClient((request) async {
          requests.add(request);
          return _json(rows, request);
        }),
      );
      addTearDown(client.dispose);
      repository = DiscoveryRepository(
        client: () => client,
        games: _NoGameRepository(),
        tours: _NoTours(),
        gamebase: _NoArchive(),
      );
    });

    test(
      'full Reports has no date cutoff and retains database page order',
      () async {
        rows = [
          report('z', time: '2020-01-01T12:00:00Z'),
          report('a', time: '2019-01-01T12:00:00Z'),
        ];
        final page = await repository.fetchAnalyzedGamesPage();
        expect(page.items.map((game) => game.gameId), ['z', 'a']);
        expect(page.nextCursor, isNull);
        expect(requests.single.method, 'GET');
        final query = requests.single.url.queryParameters;
        expect(query, isNot(contains('last_move_time')));
        expect(query, isNot(contains('offset')));
        expect(
          query['order'],
          'last_move_time.desc.nullslast,id.asc.nullslast',
        );
        expect(query['limit'], '30');
      },
    );

    test(
      'cursor follows the last candidate, including a rejected report',
      () async {
        rows = [report('a'), report('b', valid: false)];
        final page = await repository.fetchAnalyzedGamesPage(pageSize: 2);
        expect(page.items.single.gameId, 'a');
        expect(page.nextCursor, (
          lastMoveTime: rows.last['last_move_time'],
          gameId: 'b',
        ));
        expect(requests.single.url.queryParameters['limit'], '2');
      },
    );

    test(
      'cursor condition preserves the report filter and quotes literal values',
      () async {
        const cursor = (
          lastMoveTime: '2026-09-24T12:00:00.123456+00:00',
          gameId: 'a,"b\\c',
        );
        await repository.fetchAnalyzedGamesPage(after: cursor);
        final filters = requests.single.url.queryParametersAll['or']!;
        expect(filters, hasLength(2));
        expect(
          filters.first,
          r'(pgn.like.%$24%,pgn.ilike.%chessever_annotation%)',
        );
        expect(
          filters.last,
          '(last_move_time.lt.${jsonEncode(cursor.lastMoveTime)},'
          'and(last_move_time.eq.${jsonEncode(cursor.lastMoveTime)},id.gt.${jsonEncode(cursor.gameId)}),'
          'last_move_time.is.null)',
        );
      },
    );

    test(
      'type filters use the full archive RPC with the same cursor and embeds',
      () async {
        rows = [report('match')];
        await repository.fetchAnalyzedGamesPage(
          gameType: ReportGameType.comeback,
          after: (lastMoveTime: null, gameId: 'previous'),
        );
        final req = requests.single;
        expect(req.method, 'GET');
        expect(req.url.path, '/rest/v1/rpc/report_games_by_type');
        expect(req.url.queryParameters['p_type'], 'comeback');
        expect(req.url.queryParameters['id'], 'gt.previous');
        expect(
          req.url.queryParameters['select'],
          contains('tours!games_tour_id_fkey'),
        );
        expect(req.url.queryParameters['pgn'], r'like.%[\%eval %');
      },
    );

    test('undated games continue by id after all dated games', () async {
      rows = [report('b', time: null), report('c', time: null)];
      final page = await repository.fetchAnalyzedGamesPage(
        pageSize: 2,
        after: (lastMoveTime: null, gameId: 'a'),
      );
      expect(page.nextCursor, (lastMoveTime: null, gameId: 'c'));
      final query = requests.single.url.queryParameters;
      expect(query['last_move_time'], 'is.null');
      expect(query['id'], 'gt.a');
      expect(requests.single.url.queryParametersAll['or'], hasLength(1));
    });

    test(
      'all-filtered pages still advance; only an exhausted page ends pagination',
      () async {
        rows = [report('a', valid: false), report('b', valid: false)];
        final page = await repository.fetchAnalyzedGamesPage(pageSize: 2);
        expect(page.items, isEmpty);
        expect(page.nextCursor, isNotNull);
        rows = [];
        final last = await repository.fetchAnalyzedGamesPage(
          pageSize: 2,
          after: page.nextCursor,
        );
        expect(last.items, isEmpty);
        expect(last.nextCursor, isNull);
      },
    );
  });

  for (final status in [500, 503]) {
    test(
      'Reports exposes HTTP $status after one request and can retry',
      () async {
        var requests = 0;
        var failQuery = true;
        final client = SupabaseClient(
          'https://example.test',
          'placeholder',
          httpClient: MockClient((request) async {
            requests++;
            if (failQuery) {
              return http.Response(
                jsonEncode({
                  'code': '57014',
                  'message': 'canceling statement due to statement timeout',
                }),
                status,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            return _json([], request);
          }),
        );
        addTearDown(client.dispose);
        final repository = DiscoveryRepository(
          client: () => client,
          games: _NoGameRepository(),
          tours: _NoTours(),
          gamebase: _NoArchive(),
        );

        await expectLater(
          repository.fetchAnalyzedGamesPage(),
          throwsA(
            isA<PostgrestException>().having((e) => e.code, 'code', '57014'),
          ),
        );
        expect(
          requests,
          1,
          reason: 'Do not repeat a failed archive query automatically',
        );
        failQuery = false;
        final page = await repository.fetchAnalyzedGamesPage();
        expect(requests, 2);
        expect(page.items, isEmpty);
        expect(page.nextCursor, isNull);
      },
    );
  }

  test(
    'an old backend keeps All working and exposes unavailable type filters',
    () async {
      final client = SupabaseClient(
        'https://example.test',
        'placeholder',
        httpClient: MockClient((request) async {
          if (request.url.path.contains('/rpc/')) {
            return http.Response(
              jsonEncode({'code': 'PGRST202', 'message': 'missing function'}),
              404,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return _json([], request);
        }),
      );
      addTearDown(client.dispose);
      final repository = DiscoveryRepository(
        client: () => client,
        games: _NoGameRepository(),
        tours: _NoTours(),
        gamebase: _NoArchive(),
      );
      expect((await repository.fetchAnalyzedGamesPage()).items, isEmpty);
      await expectLater(
        repository.fetchAnalyzedGamesPage(gameType: ReportGameType.marathon),
        throwsA(isA<ReportGameTypesUnavailable>()),
      );
      expect((await repository.fetchAnalyzedGamesPage()).items, isEmpty);
    },
  );

  test('a stalled Reports connection is aborted within ten seconds', () async {
    final httpClient = _StalledClient();
    final client = SupabaseClient(
      'https://example.test',
      'placeholder',
      httpClient: httpClient,
    );
    final repository = DiscoveryRepository(
      client: () => client,
      games: _NoGameRepository(),
      tours: _NoTours(),
      gamebase: _NoArchive(),
    );
    await expectLater(
      repository.fetchAnalyzedGamesPage(),
      throwsA(isA<TimeoutException>()),
    ).timeout(const Duration(seconds: 12));
    expect(httpClient.requests, 1);
    await client.dispose();
  });

  group('Analyzed games cache', () {
    testWidgets('a failed read is released so the next visit retries', (
      tester,
    ) async {
      final repository = _CountingRepository()..failuresRemaining = 1;
      final container = ProviderContainer(
        overrides: [
          discoveryRepositoryProvider.overrideWith((ref) => repository),
        ],
      );
      final firstVisit = container.listen(
        discoveryAnalyzedGamesProvider,
        (_, __) {},
      );
      await tester.pump();
      expect(container.read(discoveryAnalyzedGamesProvider).hasError, isTrue);
      firstVisit.close();
      await tester.pump();
      // Flush the deferred autoDispose pass before mounting another visit.
      await tester.pump(Duration.zero);

      final secondVisit = container.listen(
        discoveryAnalyzedGamesProvider,
        (_, __) {},
      );
      await tester.pump();
      expect(repository.analyzedReads, 2);
      expect(container.read(discoveryAnalyzedGamesProvider).hasValue, isTrue);
      secondVisit.close();
      container.dispose();
      await tester.pump();
    });

    testWidgets('read at most once per 15 minutes; refresh reads at once', (
      tester,
    ) async {
      final repository = _CountingRepository();
      final container = ProviderContainer(
        overrides: [
          discoveryRepositoryProvider.overrideWith((ref) => repository),
        ],
      );

      // One visit: the section mounts, reads, and is left again.
      Future<void> visit() async {
        final sub = container.listen(
          discoveryAnalyzedGamesProvider,
          (_, __) {},
        );
        await tester.pump();
        expect(container.read(discoveryAnalyzedGamesProvider).hasValue, isTrue);
        sub.close();
        await tester.pump();
      }

      await visit();
      expect(repository.analyzedReads, 1);

      // Well past the five minutes other Discovery reads are kept for.
      await tester.pump(const Duration(minutes: 14));
      await visit();
      expect(repository.analyzedReads, 1);

      // Fifteen minutes after the read it is let go: the next visit reads.
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      await visit();
      expect(repository.analyzedReads, 2);

      // Pull-to-refresh (refreshDiscovery) reads again without waiting.
      container.invalidate(discoveryAnalyzedGamesProvider);
      await visit();
      expect(repository.analyzedReads, 3);

      container.dispose();
      // Let the scheduler's last (zero-delay) dispose pass run.
      await tester.pump(Duration.zero);
    });
  });

  group('Discovery dates', () {
    final now = DateTime(2026, 9, 24);

    test('month first, the year only outside the current one', () {
      expect(discoveryDay(DateTime(2026, 9, 23), now: now), 'Sep 23');
      expect(discoveryDay(DateTime(2025, 12, 31), now: now), 'Dec 31, 2025');
      expect(discoveryWeekday(DateTime(2026, 9, 23), now: now), 'Wed, Sep 23');
      expect(
        discoveryWeekday(DateTime(2025, 9, 23), now: now),
        'Tue, Sep 23, 2025',
      );
    });
  });
}
