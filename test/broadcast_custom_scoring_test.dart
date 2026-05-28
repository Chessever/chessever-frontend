import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/broadcast_custom_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('custom-aware broadcast game points', () {
    test('shows custom win points when they differ from standard result', () {
      expect(
        customAwareResultLabelForSide(
          GameStatus.whiteWins,
          isWhite: true,
          customPoints: 3.0,
        ),
        '3',
      );
    });

    test('keeps standard win when custom points match standard result', () {
      expect(
        customAwareResultLabelForSide(
          GameStatus.whiteWins,
          isWhite: true,
          customPoints: 1.0,
        ),
        '1',
      );
    });

    test('keeps draw label when custom points are zero', () {
      expect(
        customAwareResultLabelForSide(
          GameStatus.draw,
          isWhite: true,
          customPoints: 0.0,
        ),
        '½',
      );
    });
  });

  group('broadcast standings score resolution', () {
    test('preserves custom source score and updates played count', () {
      final resolved = resolveBroadcastStandingScore(
        sourceScore: 3.0,
        sourcePlayed: 1,
        calculatedScore: 1.0,
        calculatedPlayed: 1,
      );

      expect(resolved.score, 3.0);
      expect(resolved.played, 1);
    });

    test('falls back to calculated score when source score should not win', () {
      final resolved = resolveBroadcastStandingScore(
        sourceScore: 3.0,
        sourcePlayed: 1,
        calculatedScore: 1.0,
        calculatedPlayed: 1,
        preserveSourceScore: false,
      );

      expect(resolved.score, 1.0);
      expect(resolved.played, 1);
    });

    test('falls back to calculated score when no source score exists', () {
      final resolved = resolveBroadcastStandingScore(
        sourceScore: null,
        sourcePlayed: 0,
        calculatedScore: 1.5,
        calculatedPlayed: 2,
      );

      expect(resolved.score, 1.5);
      expect(resolved.played, 2);
    });
  });

  test('parses per-player customPoints from game players JSON', () {
    final player = Player.fromJson(const {
      'name': 'Alireza Firouzja',
      'rating': 2759,
      'customPoints': 3.0,
    });

    final card = PlayerCard.fromPlayer(player);

    expect(player.customPoints, 3.0);
    expect(card.customPoints, 3.0);
  });
}
