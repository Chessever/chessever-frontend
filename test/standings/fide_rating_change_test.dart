import 'package:chessever2/screens/standings/utils/fide_rating_change.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

void main() {
  test('performance uses the same FIDE dp table as Direct', () {
    expect(
      calculateFidePerformanceRating(
        opponentRatings: [2344, 2665, 2453, 2469, 2743, 2644, 2642, 2391, 2676],
        score: 6.5,
      ),
      2725,
    );
    expect(
      calculateFidePerformanceRating(opponentRatings: [2728], score: 1),
      3528,
    );
    expect(
      calculateFidePerformanceRating(opponentRatings: [2792], score: 0),
      1992,
    );
    expect(
      calculateFidePerformanceRating(opponentRatings: [0], score: 1),
      isNull,
    );
  });

  test(
    'a PGN tiebreak time control overrides the enclosing classical event',
    () {
      final game = GamesTourModel(
        gameId: 'g',
        roundId: 'r',
        tourId: 't',
        whitePlayer: PlayerCard(
          name: 'A',
          federation: '',
          title: '',
          rating: 2400,
          countryCode: '',
          team: null,
        ),
        blackPlayer: PlayerCard(
          name: 'B',
          federation: '',
          title: '',
          rating: 2400,
          countryCode: '',
          team: null,
        ),
        whiteTimeDisplay: '',
        blackTimeDisplay: '',
        whiteClockCentiseconds: 0,
        blackClockCentiseconds: 0,
        gameStatus: GameStatus.draw,
        timeControl: 'standard',
      );
      expect(
        ratingPoolForGame(game.copyWith(pgn: '[TimeControl "900+10"]')),
        'rapid',
      );
      expect(
        ratingPoolForGame(game.copyWith(pgn: '[TimeControl "300+3"]')),
        'blitz',
      );
      expect(
        ratingPoolForGame(game.copyWith(pgn: '[TimeControl "5400+30"]')),
        'standard',
      );
      expect(
        ratingPoolForGame(game.copyWith(pgn: '[TimeControl "600"]')),
        'blitz',
      );
      expect(
        ratingPoolForGame(game.copyWith(pgn: '[TimeControl "600+1"]')),
        'rapid',
      );
      expect(
        ratingPoolForGame(game.copyWith(timeControl: 'classical')),
        'standard',
      );
    },
  );

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
