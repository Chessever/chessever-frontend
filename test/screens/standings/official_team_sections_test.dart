import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/official_team_standings.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> section(String id, String name, int points) => {
  'id': id,
  'name': name,
  'source': 'chess-results',
  'sourceUrl': 'https://s3.chess-results.com/tnr$id.aspx',
  'round': 2,
  'fetchedAt': '2026-10-13T18:00:00Z',
  'teams': [
    {
      'name': 'Colima',
      'rank': 1,
      'matchPoints': points,
      'gamePoints': points,
      'matchesPlayed': 2,
      'wins': 1,
      'draws': 0,
      'losses': 1,
    },
    {
      'name': 'Toluca',
      'rank': 2,
      'matchPoints': 0,
      'gamePoints': 0,
      'matchesPlayed': 2,
      'wins': 0,
      'draws': 0,
      'losses': 2,
    },
  ],
  'players': [
    {
      'name': 'Player $id',
      'team': 'Colima',
      'rank': 1,
      'score': 0,
      'played': 2,
    },
  ],
};

TourInfo info(List<Map<String, dynamic>> sections) => TourInfo.fromJson({
  'standings': 'https://s3.chess-results.com/tnr1513127.aspx',
  'officialTeamStandings': {...sections.first, 'sections': sections},
  'officialPlayerStandingsSections': {
    'source': 'chess-results',
    'sourceUrl': 'https://s3.chess-results.com/tnr1513127.aspx',
    'fetchedAt': '2026-10-13T18:00:00Z',
    'sections': sections,
  },
});

void main() {
  test(
    'same city names remain independent with ranks local to each section',
    () {
      final source = info([
        section('1513127', 'Men', 2),
        section('1513133', 'Women', 4),
      ]);
      final men = buildOfficialTeamStandings(info: source, players: []);
      final women = buildOfficialTeamStandings(
        info: source,
        players: [],
        selectedSectionId: '1513133',
      );
      expect(men!.first.matchPoints, 2);
      expect(women!.first.matchPoints, 4);
      expect(women.map((t) => t.rank), [1, 2]);
      expect(women[1].matchPoints, 0);
      expect(women.first.players.single.name, 'Player 1513133');
      expect(men.first.players.single.name, 'Player 1513127');
    },
  );
  test(
    'stale selection returns the first section and malformed sibling rejects all',
    () {
      final sections = [
        section('1513127', 'Men', 2),
        section('1513133', 'Women', 4),
      ];
      expect(
        buildOfficialTeamStandings(
          info: info(sections),
          players: [],
          selectedSectionId: 'gone',
        )!.first.matchPoints,
        2,
      );
      (sections[1]['teams'] as List)[0]['matchesPlayed'] = 3;
      expect(
        buildOfficialTeamStandings(info: info(sections), players: []),
        isNull,
      );
    },
  );
  test('a section URL pointing to a different event is rejected', () {
    final sections = [
      section('1513127', 'Men', 2),
      section('1513133', 'Women', 4),
    ];
    sections[1]['sourceUrl'] = 'https://s3.chess-results.com/tnr1513012.aspx';
    expect(
      buildOfficialTeamStandings(info: info(sections), players: []),
      isNull,
    );
  });
}
