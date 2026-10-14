import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/official_team_standings.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> snapshot() => {
  'source': 'chess-results',
  'sourceUrl': 'https://s1.chess-results.com/tnr1469896.aspx?rd=4',
  'round': 4,
  'fetchedAt': '2026-09-20T11:00:00Z',
  'teams': [
    {
      'name': 'Other',
      'rank': 1,
      'matchPoints': 6,
      'gamePoints': 10,
      'matchesPlayed': 4,
      'wins': 3,
      'draws': 0,
      'losses': 1,
    },
    {
      'name': 'Brazil',
      'rank': 2,
      'matchPoints': 6,
      'gamePoints': 12,
      'matchesPlayed': 4,
      'wins': 3,
      'draws': 0,
      'losses': 1,
    },
    {
      'name': 'Awarded',
      'rank': 3,
      'matchPoints': 3,
      'gamePoints': 6,
      'matchesPlayed': 3,
      'wins': 1,
      'draws': 0,
      'losses': 2,
    },
  ],
};
TourInfo info(Map<String, dynamic> value, {String id = '1469896'}) =>
    TourInfo.fromJson({
      'standings': 'https://s2.chess-results.com/tnr$id.aspx',
      'officialTeamStandings': value,
    });

void main() {
  test(
    'keeps published team tiebreaks in source priority without reranking',
    () {
      final data = snapshot();
      (data['teams'] as List)[0]['tiebreaks'] = [
        {'extendedCode': 'TB1', 'description': 'Game points', 'points': 10},
        {'extendedCode': 'TB2', 'description': 'Direct encounter', 'points': 0},
        {
          'extendedCode': 'TB3',
          'description': 'Sonneborn-Berger',
          'points': 42.75,
        },
      ];
      final rows = buildOfficialTeamStandings(info: info(data), players: []);
      expect(rows!.first.tiebreaks.map((t) => t.label), ['TB1', 'TB2', 'TB3']);
      expect(rows.first.tiebreaks.last.formattedPoints, '42.75');
      expect(rows.map((t) => t.rank), [1, 2, 3]);
      expect(rows[1].tiebreaks, isEmpty);
    },
  );

  test(
    'uses official order and points, including awarded points absent from games',
    () {
      final source = info(snapshot());
      final rows = buildOfficialTeamStandings(info: source, players: []);
      expect(rows!.map((t) => t.teamName), ['Other', 'Brazil', 'Awarded']);
      expect(rows[1].matchPoints, 6);
      expect(rows[1].gamePoints, 12);
      expect(rows[1].officialRound, 4);
      expect(rows[2].matchPoints, 3);
      expect(rows[2].averageBoardPoints, isNull);
      expect(
        TourInfo.fromJson(source.toJson()).officialTeamStandings,
        source.officialTeamStandings,
      );
    },
  );
  test('accepts the organizer three-point win scale', () {
    final data = snapshot();
    data['matchScoring'] = {'win': 3, 'draw': 1, 'loss': 0};
    (data['teams'] as List)[0]['matchPoints'] = 9;
    final rows = buildOfficialTeamStandings(info: info(data), players: []);
    expect(rows!.first.matchPoints, 9);
  });
  test('rejects malformed scoring and negative points', () {
    final data = snapshot();
    data['matchScoring'] = {'win': 1, 'draw': 2, 'loss': 0};
    expect(buildOfficialTeamStandings(info: info(data), players: []), isNull);
    data['matchScoring'] = {'win': 3, 'draw': 1, 'loss': 0};
    (data['teams'] as List)[0]['matchPoints'] = -1;
    expect(buildOfficialTeamStandings(info: info(data), players: []), isNull);
  });
  test('preserves organizer awards beyond played-match totals', () {
    final data = snapshot();
    (data['teams'] as List)[0]['matchPoints'] = 9;
    final rows = buildOfficialTeamStandings(info: info(data), players: []);
    expect(rows!.first.matchPoints, 9);
  });
  test('preserves official shared ranks', () {
    final data = snapshot();
    (data['teams'] as List)[1]['rank'] = 1;
    final rows = buildOfficialTeamStandings(info: info(data), players: []);
    expect(rows!.map((t) => t.rank), [1, 1, 3]);
  });
  test('preserves published skipped team ranks', () {
    final data = snapshot();
    (data['teams'] as List)[1]['rank'] = 3;
    final rows = buildOfficialTeamStandings(info: info(data), players: []);
    expect(rows, isNotNull);
    expect(rows!.map((t) => t.rank), [1, 3, 3]);
  });

  test(
    'rejects ranks outside membership, descending ranks and missing first',
    () {
      for (final ranks in [
        [2, 2, 3],
        [1, 4, 4],
        [1, 3, 2],
        [1, 0, 3],
      ]) {
        final data = snapshot();
        final teams = data['teams'] as List;
        for (var i = 0; i < ranks.length; i++) {
          teams[i]['rank'] = ranks[i];
        }
        expect(
          buildOfficialTeamStandings(info: info(data), players: []),
          isNull,
        );
      }
    },
  );

  test('does not use another event snapshot', () {
    expect(
      buildOfficialTeamStandings(
        info: info(snapshot(), id: '123'),
        players: [],
      ),
      isNull,
    );
  });
  test('rejects the entire duplicate or malformed table', () {
    final data = snapshot();
    (data['teams'] as List)[1]['name'] = 'Other';
    expect(buildOfficialTeamStandings(info: info(data), players: []), isNull);
    (data['teams'] as List)[1]['name'] = 'Brazil';
    (data['teams'] as List)[1]['matchPoints'] = -1;
    expect(buildOfficialTeamStandings(info: info(data), players: []), isNull);
  });
  test('legacy tours keep their existing computed standings path', () {
    expect(
      buildOfficialTeamStandings(info: const TourInfo(), players: []),
      isNull,
    );
  });
}
