import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/bracket/utils/knockout_bracket_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses official GCT totals when game rows omit adapted points', () {
    final tour = Tour(
      id: 'gct-final-source-only',
      name: 'GCT Finals | Finals',
      slug: 'gct-final-source-only',
      info: TourInfo(format: 'Knockout'),
      createdAt: DateTime.utc(2026, 1, 1),
      url: 'https://lichess.org/broadcast/gct-final-source-only',
      tier: 1,
      dates: [DateTime.utc(2026, 1, 1), DateTime.utc(2026, 1, 3)],
      players: [
        TournamentPlayer(name: 'Caruana', played: 2, score: 9),
        TournamentPlayer(name: 'Praggnanandhaa', played: 2, score: 3),
        TournamentPlayer(name: 'Keymer', played: 3, score: 8),
        TournamentPlayer(name: 'So', played: 3, score: 6),
      ],
      groupBroadcastId: 'broadcast',
    );
    final bracket = buildKnockoutBracket(
      selectedTour: tour,
      siblingTours: const [],
      roundsByTourId: {
        tour.id: [
          _round('final-1', tour.id, day: 1),
          _round('final-2', tour.id, day: 2),
          _round('final-3', tour.id, day: 3),
        ],
      },
      gamesByTourId: {
        tour.id: [
          _game(
            'caruana-1',
            'final-1',
            tour.id,
            'Caruana',
            'Praggnanandhaa',
            '1-0',
          ),
          _game(
            'caruana-2',
            'final-2',
            tour.id,
            'Praggnanandhaa',
            'Caruana',
            '1/2-1/2',
          ),
          _game('keymer-1', 'final-1', tour.id, 'Keymer', 'So', '1-0'),
          _game('keymer-2', 'final-2', tour.id, 'So', 'Keymer', '1/2-1/2'),
          _game('keymer-3', 'final-3', tour.id, 'Keymer', 'So', '1/2-1/2'),
        ],
      },
    );

    final matchesByLeader = {
      for (final match in bracket.stages.single.matches)
        match.participant1.name: match,
    };
    final caruana = matchesByLeader['Caruana']!;
    final keymer = matchesByLeader['Keymer']!;

    expect(caruana.participant1Score, 9);
    expect(caruana.participant2Score, 3);
    expect(keymer.participant1Score, 8);
    expect(keymer.participant2Score, 6);
  });
}

Round _round(String id, String tourId, {required int day}) => Round(
  id: id,
  slug: id,
  tourId: tourId,
  tourSlug: tourId,
  name: 'Finals | Game $day',
  createdAt: DateTime.utc(2026, 1, day),
  startsAt: DateTime.utc(2026, 1, day),
  url: 'https://lichess.org/broadcast/$tourId/$id/$id',
);

Games _game(
  String id,
  String roundId,
  String tourId,
  String white,
  String black,
  String status,
) => Games(
  id: id,
  roundId: roundId,
  roundSlug: roundId,
  tourId: tourId,
  tourSlug: tourId,
  players: [_player(white), _player(black)],
  status: status,
  boardNr: null,
  lastMove: 'e2e4',
);

Player _player(String name) => Player(
  name: name,
  title: '',
  rating: 2500,
  fideId: 0,
  fed: 'FIDE',
  clock: 0,
  team: '',
);
