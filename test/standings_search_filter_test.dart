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
  test('keeps published shared ranks when assigning display ranks', () {
    final ranked = assignOverallRanks([
      PlayerStandingModel(
        countryCode: '',
        name: 'First',
        score: 0,
        scoreChange: 0,
        matchScore: '0 / 0',
        overallRank: 1,
      ),
      PlayerStandingModel(
        countryCode: '',
        name: 'Also first',
        score: 0,
        scoreChange: 0,
        matchScore: '0 / 0',
        overallRank: 1,
      ),
      PlayerStandingModel(
        countryCode: '',
        name: 'Third',
        score: 0,
        scoreChange: 0,
        matchScore: '0 / 0',
        overallRank: 3,
      ),
    ]);
    expect(ranked.map((p) => p.overallRank), [1, 1, 3]);
  });

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

  group('standings search in every script', () {
    final standings = assignOverallRanks([
      _player(name: 'Carlsen, Magnus', rating: 2830, countryCode: 'NOR'),
      _player(name: '王浩', rating: 2700, countryCode: 'CHN'),
      _player(name: 'Иванов, Сергей', rating: 2600, countryCode: 'RUS'),
      _player(name: 'Müller, Jörg', rating: 2400, countryCode: 'GER'),
      _player(name: 'Mueller, Hans', rating: 2300, countryCode: 'GER'),
      _player(name: 'Đukić, Nikola', rating: 2200, countryCode: 'SRB'),
    ]);

    List<String> names(String query) =>
        filterStandingsByQuery(standings, query).map((p) => p.name).toList();

    test('a CJK query finds only its player', () {
      expect(names('王'), ['王浩']);
      expect(filterStandingsByQuery(standings, '王浩').single.overallRank, 2);
    });

    test('a Cyrillic query finds only its player', () {
      expect(names('иванов'), ['Иванов, Сергей']);
      expect(names('Сергей Иванов'), ['Иванов, Сергей']);
    });

    test('Latin diacritics fold both ways', () {
      expect(names('dukic'), ['Đukić, Nikola']);
      expect(names('joerg'), ['Müller, Jörg']);
      expect(names('jorg muller'), ['Müller, Jörg']);
    });

    test('umlauts match their transliteration in either direction', () {
      expect(names('mueller'), ['Müller, Jörg', 'Mueller, Hans']);
      expect(names('müller'), ['Müller, Jörg', 'Mueller, Hans']);
    });

    test('a punctuation-only query leaves the table unfiltered', () {
      expect(names(' , ').length, standings.length);
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
