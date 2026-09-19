import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/initial_tour_round.dart';
import 'package:flutter_test/flutter_test.dart';

Round round(String id, int? day) => Round(
  id: id,
  slug: id,
  tourId: 'open',
  tourSlug: 'open',
  name: id,
  createdAt: DateTime.utc(2026, 9, 1),
  startsAt: day == null ? null : DateTime.utc(2026, 9, day),
  url: '',
);

void main() {
  final now = DateTime.utc(2026, 9, 19, 12);
  final rounds = [round('r1', 17), round('r2', 19), round('r3', 20)];
  test('current started round wins over prepublished future rounds', () {
    expect(initialTourRoundId(rounds: rounds, now: now), 'r2');
  });
  test('explicit round navigation wins over current/live round', () {
    expect(
      initialTourRoundId(
        rounds: rounds,
        now: now,
        requestedRoundId: 'r1',
        liveRoundIds: ['r2'],
      ),
      'r1',
    );
  });
  test(
    'foreign section selection and live ids cannot open Women from Open',
    () {
      expect(
        initialTourRoundId(
          rounds: rounds,
          now: now,
          requestedRoundId: 'women-r2',
          liveRoundIds: ['women-r2'],
        ),
        'r2',
      );
    },
  );
  test('missing start times require activity evidence instead of guessing', () {
    expect(
      initialTourRoundId(rounds: [round('unknown', null)], now: now),
      isNull,
    );
  });
  test('upcoming event opens its first round', () {
    expect(
      initialTourRoundId(rounds: rounds, now: DateTime.utc(2026, 9, 1)),
      'r1',
    );
  });
}
