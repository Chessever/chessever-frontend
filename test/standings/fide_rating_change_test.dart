import 'package:chessever2/screens/standings/utils/fide_rating_change.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fideKFactorForSelectedRating', () {
    test('uses K=10 when the selected rating is 2400 or higher', () {
      expect(fideKFactorForSelectedRating(2400), 10);
      expect(fideKFactorForSelectedRating(2491), 10);
      expect(fideKFactorForSelectedRating(2610), 10);
    });

    test('keeps the simple K=20 fallback below 2400', () {
      expect(fideKFactorForSelectedRating(2399), 20);
      expect(fideKFactorForSelectedRating(1500), 20);
    });
  });

  group('scoreCardFallbackKFactorForSelectedRating', () {
    test('uses K=10 for selected rapid or blitz ratings at 2400+', () {
      expect(
        scoreCardFallbackKFactorForSelectedRating(2491, timeControl: 'rapid'),
        10,
      );
      expect(
        scoreCardFallbackKFactorForSelectedRating(2610, timeControl: 'blitz'),
        10,
      );
    });

    test('preserves titled-player fallback below 2400 for standard games', () {
      expect(
        scoreCardFallbackKFactorForSelectedRating(
          2399,
          title: 'GM',
          timeControl: 'standard',
        ),
        10,
      );
    });
  });

  group('calculateFideRatingChange', () {
    test(
      'draw vs higher-rated opponent uses K=10 for selected 2400+ rating',
      () {
        final change = calculateFideRatingChange(
          playerRating: 2491,
          opponentRating: 2605,
          actualScore: 0.5,
        );

        expect(change, closeTo(1.58, 0.01));
      },
    );

    test('same draw is doubled with K=20 below 2400', () {
      final change = calculateFideRatingChange(
        playerRating: 2399,
        opponentRating: 2513,
        actualScore: 0.5,
      );

      expect(change, closeTo(3.16, 0.01));
    });
  });
}
