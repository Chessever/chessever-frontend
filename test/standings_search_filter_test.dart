import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerStandingModel _player({
  required String name,
  required int rating,
  String countryCode = 'USA',
  String? title,
  int? fideId,
}) {
  return PlayerStandingModel(
    countryCode: countryCode,
    title: title,
    name: name,
    score: rating,
    scoreChange: 0,
    matchScore: '0.0 / 0',
    fideId: fideId,
  );
}

void main() {
  group('standings search filtering', () {
    test('preserves the unfiltered overall rank for a one-player result', () {
      final standings = assignOverallRanks([
        for (var i = 1; i <= 36; i++)
          _player(name: 'Player $i', rating: 2800 - i, fideId: i),
        _player(
          name: 'Mamedyarov, Shakhriyar',
          rating: 2704,
          countryCode: 'AZE',
          title: 'GM',
          fideId: 13401319,
        ),
        _player(name: 'Player 38', rating: 2600, fideId: 38),
      ]);

      final result = filterStandingsByQuery(standings, 'mamedyarov');

      expect(result, hasLength(1));
      expect(result.single.name, 'Mamedyarov, Shakhriyar');
      expect(result.single.overallRank, 37);
    });

    test('matches title and federation without renumbering results', () {
      final standings = assignOverallRanks([
        _player(name: 'Carlsen, Magnus', rating: 2830, countryCode: 'NOR'),
        _player(
          name: 'Mamedyarov, Shakhriyar',
          rating: 2704,
          countryCode: 'AZE',
          title: 'GM',
        ),
      ]);

      expect(filterStandingsByQuery(standings, 'aze').single.overallRank, 2);
      expect(filterStandingsByQuery(standings, 'gm').single.overallRank, 2);
      expect(filterStandingsByQuery(standings, 'gm aze').single.overallRank, 2);
    });

    test('matches comma-separated names in natural typed order', () {
      final standings = assignOverallRanks([
        _player(name: 'Carlsen, Magnus', rating: 2830, countryCode: 'NOR'),
        _player(
          name: 'Mamedyarov, Shakhriyar',
          rating: 2704,
          countryCode: 'AZE',
          title: 'GM',
        ),
      ]);

      final result = filterStandingsByQuery(standings, 'shakhriyar mamedyarov');

      expect(result, hasLength(1));
      expect(result.single.name, 'Mamedyarov, Shakhriyar');
      expect(result.single.overallRank, 2);
    });
  });

  group('PlayerStandingModel overallRank', () {
    test('participates in json and equality', () {
      final player = _player(
        name: 'Mamedyarov, Shakhriyar',
        rating: 2704,
      ).copyWith(overallRank: 37);

      expect(PlayerStandingModel.fromJson(player.toJson()).overallRank, 37);
      expect(player, isNot(player.copyWith(overallRank: 1)));
    });
  });
}
