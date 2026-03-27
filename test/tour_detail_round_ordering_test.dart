import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_ordering.dart';
import 'package:flutter_test/flutter_test.dart';

GamesAppBarModel _round({
  required String id,
  required String name,
  required DateTime startsAt,
  required RoundStatus status,
}) {
  return GamesAppBarModel(
    id: id,
    name: name,
    startsAt: startsAt,
    roundStatus: status,
  );
}

List<String> _ids(List<GamesAppBarModel> rounds) =>
    rounds.map((round) => round.id).toList(growable: false);

void main() {
  group('sortRoundsForDisplay', () {
    test('keeps all-upcoming preconfigured rounds in ascending order', () {
      final now = DateTime(2026, 3, 29, 10);
      final rounds = [
        _round(
          id: 'r3',
          name: 'Round 3',
          startsAt: now.add(const Duration(days: 2)),
          status: RoundStatus.upcoming,
        ),
        _round(
          id: 'r1',
          name: 'Round 1',
          startsAt: now.add(const Duration(hours: 6)),
          status: RoundStatus.upcoming,
        ),
        _round(
          id: 'r2',
          name: 'Round 2',
          startsAt: now.add(const Duration(days: 1)),
          status: RoundStatus.upcoming,
        ),
      ];

      final sorted = sortRoundsForDisplay(
        rounds,
        resolveDate: (round) => round.startsAt,
        now: now,
      );

      expect(_ids(sorted), ['r1', 'r2', 'r3']);
    });

    test(
      'prioritizes next upcoming round within two hours over earlier started rounds',
      () {
        final now = DateTime(2026, 3, 30, 16);
        final rounds = [
          _round(
            id: 'r1',
            name: 'Round 1',
            startsAt: now.subtract(const Duration(hours: 4)),
            status: RoundStatus.ongoing,
          ),
          _round(
            id: 'r2',
            name: 'Round 2',
            startsAt: now.add(const Duration(hours: 1)),
            status: RoundStatus.upcoming,
          ),
          _round(
            id: 'r3',
            name: 'Round 3',
            startsAt: now.add(const Duration(days: 1)),
            status: RoundStatus.upcoming,
          ),
          _round(
            id: 'r4',
            name: 'Round 4',
            startsAt: now.add(const Duration(days: 2)),
            status: RoundStatus.upcoming,
          ),
        ];

        final sorted = sortRoundsForDisplay(
          rounds,
          resolveDate: (round) => round.startsAt,
          now: now,
        );

        expect(_ids(sorted), ['r2', 'r1', 'r3', 'r4']);
      },
    );

    test('keeps previously started rounds in reverse chronological order', () {
      final now = DateTime(2026, 3, 31, 16);
      final rounds = [
        _round(
          id: 'r1',
          name: 'Round 1',
          startsAt: now.subtract(const Duration(days: 2)),
          status: RoundStatus.completed,
        ),
        _round(
          id: 'r2',
          name: 'Round 2',
          startsAt: now.subtract(const Duration(days: 1)),
          status: RoundStatus.completed,
        ),
        _round(
          id: 'r3',
          name: 'Round 3',
          startsAt: now.add(const Duration(minutes: 90)),
          status: RoundStatus.upcoming,
        ),
        _round(
          id: 'r4',
          name: 'Round 4',
          startsAt: now.add(const Duration(days: 1)),
          status: RoundStatus.upcoming,
        ),
      ];

      final sorted = sortRoundsForDisplay(
        rounds,
        resolveDate: (round) => round.startsAt,
        now: now,
      );

      expect(_ids(sorted), ['r3', 'r2', 'r1', 'r4']);
    });

    test('ends with latest round first and all prior rounds descending', () {
      final now = DateTime(2026, 4, 12, 16);
      final rounds = [
        for (var i = 1; i <= 4; i++)
          _round(
            id: 'r$i',
            name: 'Round $i',
            startsAt: DateTime(2026, 4, 8 + i, 12),
            status: RoundStatus.completed,
          ),
      ];

      final sorted = sortRoundsForDisplay(
        rounds,
        resolveDate: (round) => round.startsAt,
        now: now,
      );

      expect(_ids(sorted), ['r4', 'r3', 'r2', 'r1']);
    });
  });

  group('pickPreferredRoundForSelection', () {
    test('selects the same top round for the preconfigured upcoming-window case', () {
      final now = DateTime(2026, 3, 30, 16);
      final rounds = [
        _round(
          id: 'r1',
          name: 'Round 1',
          startsAt: now.subtract(const Duration(hours: 4)),
          status: RoundStatus.ongoing,
        ),
        _round(
          id: 'r2',
          name: 'Round 2',
          startsAt: now.add(const Duration(hours: 1)),
          status: RoundStatus.upcoming,
        ),
        _round(
          id: 'r3',
          name: 'Round 3',
          startsAt: now.add(const Duration(days: 1)),
          status: RoundStatus.upcoming,
        ),
      ];

      final selected = pickPreferredRoundForSelection(
        rounds,
        resolveDate: (round) => round.startsAt,
        hasGames: (_) => true,
        now: now,
      );

      expect(selected?.id, 'r2');
    });

    test('returns null when hasGames filters out every round', () {
      final now = DateTime(2026, 3, 30, 16);
      final rounds = [
        _round(
          id: 'r1',
          name: 'Round 1',
          startsAt: now.subtract(const Duration(hours: 4)),
          status: RoundStatus.completed,
        ),
        _round(
          id: 'r2',
          name: 'Round 2',
          startsAt: now.add(const Duration(hours: 1)),
          status: RoundStatus.upcoming,
        ),
      ];

      final selected = pickPreferredRoundForSelection(
        rounds,
        resolveDate: (round) => round.startsAt,
        hasGames: (_) => false,
        now: now,
      );

      expect(selected, isNull);
    });

    test('prefers the most recent live round when multiple live rounds exist', () {
      final now = DateTime(2026, 3, 30, 16);
      final rounds = [
        _round(
          id: 'r1',
          name: 'Round 1',
          startsAt: now.subtract(const Duration(hours: 3)),
          status: RoundStatus.live,
        ),
        _round(
          id: 'r2',
          name: 'Round 2',
          startsAt: now.subtract(const Duration(hours: 1)),
          status: RoundStatus.live,
        ),
        _round(
          id: 'r3',
          name: 'Round 3',
          startsAt: now.add(const Duration(hours: 2)),
          status: RoundStatus.upcoming,
        ),
      ];

      final selected = pickPreferredRoundForSelection(
        rounds,
        resolveDate: (round) => round.startsAt,
        hasGames: (_) => true,
        now: now,
      );

      expect(selected?.id, 'r2');
    });
  });
}
