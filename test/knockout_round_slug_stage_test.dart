import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('roundSlugStageRoundId', () {
    test('does not turn individual game legs into tournament stages', () {
      // FIDE World Cup 2025 legs all belong to the Finals stage tour. The
      // synthetic model maps them through sourceRoundIds instead.
      expect(roundSlugStageRoundId('DqmmnYSq', 'game-1'), isNull);
      expect(roundSlugStageRoundId('DqmmnYSq', 'game_1'), isNull);
      expect(roundSlugStageRoundId('DqmmnYSq', 'tiebreak-1-rapid-1'), isNull);
      expect(roundSlugStageRoundId('DqmmnYSq', 'rapid_1'), isNull);
      expect(roundSlugStageRoundId('DqmmnYSq', 'blitz_1'), isNull);
      expect(roundSlugStageRoundId('DqmmnYSq', 'sudden-death'), isNull);
      expect(roundSlugStageRoundId('DqmmnYSq', 'sudden_death'), isNull);
    });

    test('uses the segment before "--" as the stage part', () {
      expect(
        roundSlugStageRoundId('t1', 'quarterfinals--game-2'),
        'knockout-stage-t1-quarterfinals',
      );
      expect(
        roundSlugStageRoundId('t1', 'stage-quarterfinals--game-1'),
        'knockout-stage-t1-quarterfinals',
      );
    });

    test('uses the shared logical stage key', () {
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
