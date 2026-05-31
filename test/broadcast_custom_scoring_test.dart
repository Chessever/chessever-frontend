import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/broadcast_custom_scoring.dart';

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

  group('Norway board and player-card scoring', () {
    test('board view shows classical custom win as 3-0', () {
      final game = _game(
        status: GameStatus.whiteWins,
        whiteCustomPoints: 3.0,
        blackCustomPoints: 0.0,
      );

      expect(boardResultLabelForSide(game, isWhite: true), '3');
      expect(boardResultLabelForSide(game, isWhite: false), '0');
    });

    test('board view shows classical draw custom points as 1-1', () {
      final game = _game(
        status: GameStatus.draw,
        whiteCustomPoints: 1.0,
        blackCustomPoints: 1.0,
      );

      expect(boardResultLabelForSide(game, isWhite: true), '1');
      expect(boardResultLabelForSide(game, isWhite: false), '1');
    });

    test('board view keeps Armageddon simple as 1-0', () {
      final game = _game(
        status: GameStatus.whiteWins,
        roundSlug: 'round-4-armageddon',
        whiteCustomPoints: 0.5,
        blackCustomPoints: 0.0,
      );

      expect(boardResultLabelForSide(game, isWhite: true), '1');
      expect(boardResultLabelForSide(game, isWhite: false), '0');
    });

    test('player card can show Armageddon bonus as 0.5', () {
      expect(
        customAwareResultLabelForSide(
          GameStatus.whiteWins,
          isWhite: true,
          customPoints: 0.5,
        ),
        '0.5',
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

GamesTourModel _game({
  required GameStatus status,
  String roundSlug = 'round-4',
  double? whiteCustomPoints,
  double? blackCustomPoints,
}) {
  return GamesTourModel(
    gameId: 'game-1',
    source: GameSource.supabase,
    whitePlayer: PlayerCard(
      name: 'Carlsen, Magnus',
      federation: 'NOR',
      title: 'GM',
      rating: 2840,
      countryCode: 'NOR',
      team: '',
      customPoints: whiteCustomPoints,
    ),
    blackPlayer: PlayerCard(
      name: 'Gukesh D',
      federation: 'IND',
      title: 'GM',
      rating: 2732,
      countryCode: 'IND',
      team: '',
      customPoints: blackCustomPoints,
    ),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: status,
    roundId: roundSlug,
    roundSlug: roundSlug,
    tourId: 'norway-chess',
    tourSlug: 'norway-chess-2026',
  );
}
