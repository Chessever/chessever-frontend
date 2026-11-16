import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/screens/tour_detail/bracket/utils/knockout_bracket_builder.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/bracket_graph_layout.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// Speed Chess Championship XI, Round of 16 on 16 Nov 2026: every match of the
// stage lives in one round, only Nakamura-Erdogmus is being played, and the
// other matches are 0-move shells dated to the feed's placeholder day.
void main() {
  group('match-play stage (Speed Chess Championship)', () {
    KnockoutStage roundOf16(List<Games> games) {
      final bracket = buildKnockoutBracket(
        selectedTour: _tour,
        siblingTours: const [],
        roundsByTourId: {
          _tour.id: [_round('r16', 'Round of 16', 'round-of-16')],
        },
        gamesByTourId: {_tour.id: games},
        liveRoundIds: const {'r16'},
        now: DateTime.utc(2026, 11, 16, 17, 30),
      );
      return bracket.stages.firstWhere((stage) => stage.matches.isNotEmpty);
    }

    test('only the match with a game in play is live', () {
      final stage = roundOf16(_scc);
      final live = {
        for (final match in stage.matches)
          match.participant1.name: match.isLive,
      };

      expect(live['Nakamura, Hikaru'], isTrue);
      expect(live['Carlsen, Magnus'], isFalse);
      expect(live['Caruana, Fabiano'], isFalse);
      expect(stage.isLive, isTrue);
    });

    test(
      'game 1 White leads the match even when shells sort first by date',
      () {
        // Carlsen's game 1 is played (re-dated), game 2 is still a shell with
        // the placeholder date; date order would make Movahed participant 1.
        final games = [
          _g(
            'c1',
            2,
            'Carlsen, Magnus',
            'Movahed, Sina',
            '1-0',
            '01.01',
            day: 16,
            moved: true,
          ),
          _g(
            'c2',
            11,
            'Movahed, Sina',
            'Carlsen, Magnus',
            '*',
            '01.02',
            day: 14,
          ),
          ..._scc.where((game) => !game.id.startsWith('c')),
        ];
        final carlsen = roundOf16(games).matches.firstWhere(
          (match) =>
              match.participant1.name.contains('Carlsen') ||
              match.participant2.name.contains('Carlsen'),
        );

        expect(carlsen.participant1.name, 'Carlsen, Magnus');
        expect(carlsen.participant1Score, 1);
      },
    );

    test('a later game on a lower board keeps the same participant 1', () {
      final games = [
        // Game 3 (Erdogmus White) lands mid-file: the feed renumbers it
        // below game 1, which the old board order would have put first.
        _g(
          'n3',
          1,
          'Erdogmus, Yagiz Kaan',
          'Nakamura, Hikaru',
          '*',
          '01.03',
          day: 16,
          moved: true,
        ),
        ..._scc.map(
          (game) => game.id == 'n1' ? game.copyWith(boardNr: 2) : game,
        ),
      ];
      final nakamura = _matchOf(roundOf16(games), 'Nakamura');

      expect(nakamura.participant1.name, 'Nakamura, Hikaru');
    });

    test('a finished game without its PGN still leads its match', () {
      // Rated finished rows arrive without PGN; game 2 is a shell on a lower
      // board, so neither the tag nor the board can order them.
      final games = [
        Games(
          id: 'c1',
          roundId: 'r16',
          roundSlug: 'round-of-16',
          tourId: _tour.id,
          tourSlug: _tour.slug,
          players: [_player('Carlsen, Magnus'), _player('Movahed, Sina')],
          status: '1-0',
          boardNr: 11,
          lastMove: 'h7h8q',
          lastMoveTime: DateTime.utc(2026, 12, 16, 15),
          dateStart: DateTime.utc(2026, 12, 16),
        ),
        _g('c2', 2, 'Movahed, Sina', 'Carlsen, Magnus', '*', '01.02', day: 14),
        ..._scc.where((game) => !game.id.startsWith('c')),
      ];
      final carlsen = _matchOf(roundOf16(games), 'Carlsen');

      expect(carlsen.participant1.name, 'Carlsen, Magnus');
      expect(carlsen.isLive, isFalse);
    });

    test('one duplicated pairing does not change an ordinary stage', () {
      final bracket = buildKnockoutBracket(
        selectedTour: _tour,
        siblingTours: const [],
        roundsByTourId: {
          _tour.id: [_round('r16', 'Round of 16', 'round-of-16')],
        },
        gamesByTourId: {
          _tour.id: [
            _g('a1', 1, 'A, One', 'B, Two', '*', '1.1', day: 16),
            _g('a2', 9, 'B, Two', 'A, One', '*', '1.2', day: 16),
            _g('b', 2, 'C, Three', 'D, Four', '*', '1.1', day: 16),
            _g('c', 3, 'E, Five', 'F, Six', '*', '1.1', day: 16),
          ],
        },
        liveRoundIds: const {'r16'},
        now: DateTime.utc(2026, 11, 16, 17, 30),
      );
      final stage = bracket.stages.firstWhere((s) => s.matches.isNotEmpty);
      final live = {
        for (final match in stage.matches)
          match.participant1.name: match.isLive,
      };

      expect(live['C, Three'], isTrue);
      expect(live['E, Five'], isTrue);
    });
  });

  test('a round with one game per pairing keeps round-level live', () {
    final bracket = buildKnockoutBracket(
      selectedTour: _tour,
      siblingTours: const [],
      roundsByTourId: {
        _tour.id: [_round('r16', 'Round of 16', 'round-of-16')],
      },
      gamesByTourId: {
        _tour.id: [
          _g('a', 1, 'A, One', 'B, Two', '*', '1.1', day: 16),
          _g('b', 2, 'C, Three', 'D, Four', '*', '1.1', day: 16),
        ],
      },
      liveRoundIds: const {'r16'},
      now: DateTime.utc(2026, 11, 16, 17, 30),
    );
    final stage = bracket.stages.firstWhere((s) => s.matches.isNotEmpty);

    expect(stage.matches.every((match) => match.isLive), isTrue);
  });

  test('match-play game index orders by game, not text', () {
    String pgn(String round) => '[Round "$round"]\n\n*';
    expect(compareMatchPlayGameIndex(pgn('01.02'), pgn('01.10')), lessThan(0));
    expect(
      compareMatchPlayGameIndex(pgn('1.2.1'), pgn('1.1.9')),
      greaterThan(0),
    );
    expect(compareMatchPlayGameIndex(null, pgn('01.01')), greaterThan(0));
    expect(compareMatchPlayGameIndex(null, null), 0);
  });

  group('readableStageCameraCenter', () {
    const viewport = Size(402, 700);
    const header = Rect.fromLTWH(24, 18, 220, 28);

    test('a top-of-column target opens with the header at the top', () {
      final center = readableStageCameraCenter(
        focusRect: Rect.fromCenter(
          center: const Offset(134, 80),
          width: 252,
          height: 360,
        ),
        headerRect: header,
        viewport: viewport,
        scale: 1,
      );
      final headerScreenY = viewport.height / 2 - (center.dy - header.top);

      expect(headerScreenY, closeTo(12, 0.001));
      expect(center.dx, 134);
    });

    test('a target deep in the column keeps its center', () {
      const deep = Offset(134, 1400);
      final center = readableStageCameraCenter(
        focusRect: Rect.fromCenter(center: deep, width: 252, height: 360),
        headerRect: header,
        viewport: viewport,
        scale: 1,
      );

      expect(center, deep);
    });
  });
}

KnockoutMatch _matchOf(KnockoutStage stage, String surname) =>
    stage.matches.firstWhere(
      (match) =>
          match.participant1.name.contains(surname) ||
          match.participant2.name.contains(surname),
    );

final _tour = Tour(
  id: 'fqCjSUpE',
  name: 'Speed Chess Championship XI (2026–27)',
  slug: '2026-speed-chess-championship',
  info: TourInfo(
    format: '16-player single-elimination knockout, with a consolation match',
  ),
  createdAt: DateTime.utc(2026, 11, 3),
  url: 'https://chessever.com/broadcast/2026-speed-chess-championship/fqCjSUpE',
  tier: 1,
  dates: [DateTime.utc(2026, 11, 16), DateTime.utc(2027, 2, 7)],
  players: const [],
  groupBroadcastId: 'gb_fqCjSUpE',
);

Round _round(String id, String name, String slug) => Round(
  id: id,
  slug: slug,
  tourId: _tour.id,
  tourSlug: _tour.slug,
  name: name,
  createdAt: DateTime.utc(2026, 11, 3),
  startsAt: DateTime.utc(2026, 11, 16, 17),
  url: 'https://chessever.com',
);

final _scc = [
  _g(
    'n1',
    1,
    'Nakamura, Hikaru',
    'Erdogmus, Yagiz Kaan',
    '1/2-1/2',
    '01.01',
    day: 16,
    moved: true,
  ),
  _g('c1', 2, 'Carlsen, Magnus', 'Movahed, Sina', '*', '01.01', day: 14),
  _g('f1', 6, 'Caruana, Fabiano', 'Sindarov, Javokhir', '*', '01.01', day: 14),
  _g('c2', 11, 'Movahed, Sina', 'Carlsen, Magnus', '*', '01.02', day: 14),
  _g(
    'n2',
    12,
    'Erdogmus, Yagiz Kaan',
    'Nakamura, Hikaru',
    '*',
    '01.02',
    day: 16,
    moved: true,
  ),
  _g('f2', 16, 'Sindarov, Javokhir', 'Caruana, Fabiano', '*', '01.02', day: 14),
];

Games _g(
  String id,
  int board,
  String white,
  String black,
  String status,
  String pgnRound, {
  required int day,
  bool moved = false,
}) => Games(
  id: id,
  roundId: 'r16',
  roundSlug: 'round-of-16',
  tourId: _tour.id,
  tourSlug: _tour.slug,
  players: [_player(white), _player(black)],
  status: status,
  boardNr: board,
  lastMove: moved ? 'e2e4' : null,
  lastMoveTime: moved ? DateTime.utc(2026, 11, day, 17, board) : null,
  fen: moved
      ? 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1'
      : 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  pgn: '[Round "$pgnRound"]\n[White "$white"]\n[Black "$black"]\n\n*',
  dateStart: DateTime.utc(2026, 11, day),
);

Player _player(String name) => Player(
  name: name,
  title: 'GM',
  rating: 2700,
  fideId: 0,
  fed: 'FIDE',
  clock: 0,
  team: '',
);
