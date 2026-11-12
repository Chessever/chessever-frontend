import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/watch/core/watch_event_layout.dart';
import 'package:chessever2/watch/core/watch_models.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 12, 15);

WatchTour _tour(
  String id,
  String name, {
  int? avgElo,
  DateTime? startsAt,
  bool isMirror = false,
  String slug = '',
}) => WatchTour(
  id: id,
  eventId: 'event',
  name: name,
  slug: slug,
  avgElo: avgElo,
  startsAt: startsAt,
  isMirror: isMirror,
  players: const [],
);

WatchRound _round(String id, String tour, String name, DateTime? at) =>
    WatchRound(id: id, name: name, startsAt: at, tourId: tour);

Games _game(
  String id, {
  required String tour,
  required String round,
  String status = '*',
  int? board,
  String? lastMove,
  String white = 'Player One',
  String black = 'Player Two',
  String? whiteTeam,
  String? blackTeam,
}) => Games.fromJson({
  'id': id,
  'tour_id': tour,
  'tour_slug': tour,
  'round_id': round,
  'round_slug': round,
  'status': status,
  'board_nr': board,
  'last_move': lastMove,
  'players': [
    {'name': white, if (whiteTeam != null) 'team': whiteTeam},
    {'name': black, if (blackTeam != null) 'team': blackTeam},
  ],
});

void main() {
  test('sections rank strongest first and rounds latest first', () {
    final tours = [
      _tour('b', 'Open | Group B', avgElo: 2500),
      _tour('a', 'Open | Group A', avgElo: 2700),
      _tour('u', 'Open | Amateurs'),
    ];
    DateTime day(int d) => DateTime(2026, 11, 10 + d, 14);
    final rounds = [
      _round('a1', 'a', 'Round 1', day(0)),
      _round('a2', 'a', 'Round 2', day(1)),
      _round('a3', 'a', 'Round 3', day(2)),
      _round('a4', 'a', 'Round 4', day(3)),
      _round('b1', 'b', 'Round 1', day(0)),
      _round('b2', 'b', 'Round 2', day(1)),
      _round('b3', 'b', 'Round 3', day(2)),
      _round('u1', 'u', 'Round 1', day(0)),
    ];
    // Each section has its own players, as real sections do.
    Games g(
      String id, {
      required String tour,
      required String round,
      String status = '*',
      int? board,
      String? lastMove,
    }) => _game(
      id,
      tour: tour,
      round: round,
      status: status,
      board: board,
      lastMove: lastMove,
      white: '$tour white $id',
      black: '$tour black $id',
    );
    final games = [
      g('a1g', tour: 'a', round: 'a1', status: '1-0', board: 1),
      g('a2g', tour: 'a', round: 'a2', status: '1/2-1/2', board: 1),
      g('a3g', tour: 'a', round: 'a3', lastMove: 'e2e4', board: 2),
      g('a3h', tour: 'a', round: 'a3', lastMove: 'd2d4', board: 1),
      g('a4g', tour: 'a', round: 'a4', board: 1), // pairings only
      g('b1g', tour: 'b', round: 'b1', status: '0-1', board: 1),
      g('b2g', tour: 'b', round: 'b2', status: '1-0', board: 1),
      g('b3g', tour: 'b', round: 'b3', board: 1), // pairings only
      g('u1g', tour: 'u', round: 'u1', status: '1-0', board: 1),
    ];
    final sections = watchEventSections(
      tours: tours,
      rounds: rounds,
      games: games,
      now: _now,
      eventName: 'Open',
    );
    expect(
      [for (final s in sections) '${s.label} ${s.round.name}'],
      [
        // Group A is being played: latest started first, then the next.
        'Group A Round 3',
        'Group A Round 2',
        'Group A Round 1',
        'Group A Round 4',
        // Nothing is being played in Group B, so its next round leads.
        'Group B Round 3',
        'Group B Round 2',
        'Group B Round 1',
        // Unrated sections come last.
        'Amateurs Round 1',
      ],
    );
    expect(sections.first.games.map((g) => g.boardNr), [1, 2]);
    expect(sections.first.playing, 2);
    expect(sections[3].hasStarted, isFalse);
    expect(sections[6].isFullyPlayed, isTrue);

    final items = watchFeedItems(sections);
    expect(items.first, isA<WatchCategoryItem>());
    expect((items.first as WatchCategoryItem).rounds, 4);
    expect(items[1], isA<WatchRoundItem>());
    expect(items[2], isA<WatchBoardItem>());
    expect(items.whereType<WatchCategoryItem>().length, 3);
    expect(items.whereType<WatchBoardItem>().length, 9);
  });

  test('a lone section gets no category heading and reads boards in order', () {
    final sections = watchEventSections(
      tours: [_tour('t', 'Club Championship')],
      rounds: [_round('r1', 't', 'Round 1', null)],
      games: [
        _game('x', tour: 't', round: 'r1', status: '1-0'),
        _game('y', tour: 't', round: 'r1', status: '1-0', board: 2),
        _game('z', tour: 't', round: 'r1', status: '1-0', board: 1),
      ],
      now: _now,
    );
    expect(sections.single.games.map((g) => g.id), ['z', 'y', 'x']);
    final items = watchFeedItems(sections);
    expect(items.whereType<WatchCategoryItem>(), isEmpty);
    expect(items.first, isA<WatchRoundItem>());
  });

  test('organiser combined sections and board-level mirrors are left out', () {
    final at = DateTime(2026, 11, 12, 14);
    final tours = [
      _tour('mix', 'Total Chess | Group Stage | Combined', avgElo: 2735),
      _tour('b', 'Total Chess | Group Stage | B', avgElo: 2735),
      _tour('a', 'Total Chess | Group Stage | A', avgElo: 2700),
      _tour('copy', 'Total Chess | Group Stage | Both', avgElo: 2600),
      _tour('flag', 'Total Chess | Group Stage | All', isMirror: true),
    ];
    final rounds = [
      for (final t in ['mix', 'a', 'b', 'copy', 'flag'])
        _round('$t-r1', t, 'Round 1', at),
    ];
    Games pair(String id, String tour, int i) => _game(
      id,
      tour: tour,
      round: '$tour-r1',
      board: i,
      status: '1-0',
      white: 'White $i',
      black: 'Black $i',
    );
    final games = [
      for (var i = 1; i <= 4; i++) pair('a$i', 'a', i),
      for (var i = 5; i <= 8; i++) pair('b$i', 'b', i),
      // "Combined" by name: the same eight boards.
      for (var i = 1; i <= 8; i++) pair('m$i', 'mix', i),
      // Neither flagged nor named, but every board is a copy.
      for (var i = 1; i <= 8; i++) pair('c$i', 'copy', i),
      for (var i = 1; i <= 8; i++) pair('f$i', 'flag', i),
    ];
    final sections = watchEventSections(
      tours: tours,
      rounds: rounds,
      games: games,
      now: _now,
      eventName: 'Total Chess',
    );
    expect([for (final s in sections) s.label], ['B', 'A']);
    final boards = {
      for (final s in sections)
        for (final g in s.games) g.id,
    };
    expect(boards.length, 8);
  });

  test('a section named combined with nothing beside it is a real section', () {
    final sections = watchEventSections(
      tours: [_tour('only', 'Combined Open')],
      rounds: [_round('r1', 'only', 'Round 1', null)],
      games: [_game('g', tour: 'only', round: 'r1', status: '1-0')],
      now: _now,
    );
    expect(sections.single.label, 'Combined Open');
  });

  test('team rounds list each match before its boards', () {
    final sections = watchEventSections(
      tours: [_tour('t', 'League')],
      rounds: [_round('r1', 't', 'Round 1', null)],
      games: [
        for (var i = 1; i <= 4; i++)
          _game(
            'g$i',
            tour: 't',
            round: 'r1',
            board: i,
            status: '1-0',
            white: 'W$i',
            black: 'B$i',
            whiteTeam: i.isOdd ? 'Home' : 'Away',
            blackTeam: i.isOdd ? 'Away' : 'Home',
          ),
      ],
      now: _now,
    );
    final items = watchFeedItems(sections);
    expect(items.map((i) => i.runtimeType), [
      WatchRoundItem,
      WatchMatchItem,
      WatchBoardItem,
      WatchBoardItem,
      WatchBoardItem,
      WatchBoardItem,
    ]);
    final match = (items[1] as WatchMatchItem).match;
    expect(match.home, 'Home');
    expect(match.homeScore, 2);
    expect(match.awayScore, 2);
  });

  test('a published pairing is live but not playing', () {
    final pairing = _game('p', tour: 't', round: 'r');
    expect(watchGameIsLive(pairing), isTrue);
    expect(watchGameIsPlaying(pairing), isFalse);
    expect(
      watchGameIsPlaying(_game('q', tour: 't', round: 'r', lastMove: 'e2e4')),
      isTrue,
    );
  });

  test('category labels read like the phone picker', () {
    expect(
      watchCategoryLabel(
        'Total Chess 2026 | Group Stage | B',
        groupName: 'Total Chess 2026',
      ),
      'B',
    );
    // A parent name only strips with a separator after it, as on the phone.
    expect(
      watchCategoryLabel('Tata Steel - Masters', groupName: 'Tata Steel'),
      'Masters',
    );
    expect(
      watchCategoryLabel('Tata Steel Masters', groupName: 'Tata Steel'),
      'Tata Steel Masters',
    );
    expect(watchCategoryLabel('European Open Boards 1-10'), 'Boards 1-10');
    expect(watchCategoryLabel('World Cup: Women'), 'Women');
    expect(watchCategoryLabel('Open Section A'), 'Section A');
    expect(watchCategoryLabel('Club Championship'), 'Club Championship');
    expect(
      watchIsCombinedLabel(name: 'Group Stage | Combined', slug: ''),
      isTrue,
    );
    expect(watchIsCombinedLabel(name: 'Recombined Open'), isFalse);
  });
}
