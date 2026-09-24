import 'dart:convert';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
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

/// Counts Analyzed games reads; nothing else is expected of it.
class _CountingRepository implements DiscoveryRepository {
  int analyzedReads = 0;

  @override
  Future<List<GamesTourModel>> fetchAnalyzedGames({
    int limit = 10,
    DateTime? now,
  }) async {
    analyzedReads++;
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
          if (request.url.path.endsWith('/rpc/most_liked_games')) {
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

  group('Analyzed games cache', () {
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
