import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Games game({
    required String id,
    required String roundId,
    required String roundSlug,
    required String status,
    DateTime? dateStart,
  }) {
    return Games(
      id: id,
      roundId: roundId,
      roundSlug: roundSlug,
      tourId: 'gamebasev2::name=V.%20Rigo%20Janos%20Memorial',
      tourSlug: 'V. Rigo Janos Memorial',
      status: status,
      dateStart: dateStart,
    );
  }

  test(
    'buildVirtualGamebaseRoundModels creates selectable rounds for games',
    () {
      final rounds = buildVirtualGamebaseRoundModels([
        game(
          id: 'g1',
          roundId: 'virtual::round::1',
          roundSlug: 'Round 1',
          status: '1-0',
          dateStart: DateTime.utc(2026, 6, 21),
        ),
        game(
          id: 'g2',
          roundId: 'virtual::round::1',
          roundSlug: 'Round 1',
          status: '0-1',
          dateStart: DateTime.utc(2026, 6, 22),
        ),
        game(
          id: 'g3',
          roundId: 'virtual::round::2',
          roundSlug: 'Round 2',
          status: '*',
          dateStart: DateTime.utc(2026, 6, 23),
        ),
      ]);

      expect(rounds, hasLength(2));
      expect(rounds.map((round) => round.id), [
        'virtual::round::1',
        'virtual::round::2',
      ]);
      expect(rounds.map((round) => round.name), ['Round 1', 'Round 2']);
      expect(rounds[0].startsAt, DateTime.utc(2026, 6, 21));
      expect(rounds[0].roundStatus, RoundStatus.completed);
      expect(rounds[1].roundStatus, RoundStatus.ongoing);
    },
  );
}
