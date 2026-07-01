import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('roundSlugStageRoundId', () {
    test('maps plain knockout game slugs to app-bar stage ids', () {
      // FIDE World Cup 2025 (tour DqmmnYSq) round slugs.
      expect(
        roundSlugStageRoundId('DqmmnYSq', 'game-1'),
        'knockout-stage-DqmmnYSq-game-1',
      );
      expect(
        roundSlugStageRoundId('DqmmnYSq', 'tiebreak-1-rapid-1'),
        'knockout-stage-DqmmnYSq-tiebreak-1-rapid-1',
      );
      expect(
        roundSlugStageRoundId('DqmmnYSq', 'sudden-death'),
        'knockout-stage-DqmmnYSq-sudden-death',
      );
    });

    test('uses the segment before "--" as the stage part', () {
      expect(
        roundSlugStageRoundId('t1', 'quarterfinals--game-2'),
        'knockout-stage-t1-quarterfinals',
      );
      expect(
        roundSlugStageRoundId('t1', 'stage-quarterfinals--game-1'),
        'knockout-stage-t1-stage-quarterfinals',
      );
    });

    test('normalizes separators like the app-bar stage names', () {
      expect(
        roundSlugStageRoundId('t1', 'sudden_death'),
        'knockout-stage-t1-sudden-death',
      );
      expect(
        roundSlugStageRoundId('t1', ' Round-1 '),
        'knockout-stage-t1-round-1',
      );
    });

    test('returns null for empty slugs', () {
      expect(roundSlugStageRoundId('t1', null), isNull);
      expect(roundSlugStageRoundId('t1', ''), isNull);
      expect(roundSlugStageRoundId('t1', '  '), isNull);
    });
  });
}
