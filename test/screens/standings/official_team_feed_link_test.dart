import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/official_team_feed_link.dart';
import 'package:chessever2/screens/standings/official_team_standings.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';

// Trimmed from tour h2GbjYXa (2026 Texas Collegiate Super Finals, 2026-10-20):
// tours.info.officialTeamStandings (tiebreaks dropped), tours.players and
// round-1 boards. Chess-Results names the squads "University of Texas at
// Dallas-A"; the broadcast labels every UTD player and board "UTD".
Map<String, dynamic> _team(
  String name,
  int rank,
  num mp,
  num gp,
  int w,
  int d,
  int l,
) => {
  'name': name,
  'rank': rank,
  'matchPoints': mp,
  'gamePoints': gp,
  'matchesPlayed': 4,
  'wins': w,
  'draws': d,
  'losses': l,
};

Map<String, dynamic> _snapshot() => {
  'round': 4,
  'source': 'chess-results',
  'fetchedAt': '2026-10-19T01:36:27.617227Z',
  'sourceUrl':
      'https://s2.chess-results.com/tnr1515428.aspx?lan=1&art=0&flag=NO&zeilen=99999',
  'matchScoring': {'win': 2, 'draw': 1, 'loss': 0},
  'teams': [
    _team('University of Texas at Dallas-A', 1, 7, 11.5, 3, 1, 0),
    _team('University of Texas Rio Grande Valley-A', 2, 6, 11.5, 2, 2, 0),
    _team('University of Texas at Dallas-B', 3, 5, 9, 2, 1, 1),
    _team('University of Texas Rio Grande Valley-B', 4, 4, 9, 2, 0, 2),
    _team('Texas Tech University-A', 5, 2, 7, 0, 2, 2),
    _team('Texas Tech University-B', 6, 0, 0, 0, 0, 4),
  ],
};

TourInfo _info(Map<String, dynamic> snapshot) => TourInfo.fromJson({
  'standings': 'https://s2.chess-results.com/tnr1515428.aspx?lan=1',
  'officialTeamStandings': snapshot,
});

const _roster = [
  ('UTD Samant Aditya S', 'UTD', 35080580),
  ('UTD Gorshtein Ido', 'UTD', 2815532),
  ('UTD Sankalp Gupta', 'UTD', 5097010),
  ('UTD Harikrishnan.A.Ra', 'UTD', 5081483),
  ('UTD Koustav Chatterjee', 'UTD', 25073060),
  ('UTD Rahul Srivatshav P', 'UTD', 25059653),
  ('UTD Parkhov Yair', 'UTD', 2813408),
  ('UTD Ouellet Maili-Jade', 'UTD', 2620472),
  ('UTRGV Dudin Gleb', 'UTRGV', 34184934),
  ('UTRGV Cardoso Cardoso Jose Gabriel', 'UTRGV', 4430492),
  ('TTU Moor Nathaniel Philip', 'TTU', 30970610),
  ('TTU Senol Mert', 'TTU', 44524498),
  ('TTU Nguyen Minh Trong', 'TTU', 39945138),
];

List<PlayerStandingModel> _players() => [
  for (final (name, team, fideId) in _roster)
    PlayerStandingModel(
      countryCode: 'USA',
      name: name,
      score: 2400,
      scoreChange: 0,
      matchScore: null,
      fideId: fideId,
      team: team,
    ),
];

PlayerCard _card(String name) {
  final (_, team, fideId) = _roster.firstWhere((p) => p.$1 == name);
  return PlayerCard(
    name: name,
    federation: 'USA',
    title: '',
    rating: 2400,
    countryCode: 'USA',
    team: team,
    fideId: fideId,
  );
}

GamesTourModel _game(int board, String white, String black, GameStatus s) =>
    GamesTourModel(
      gameId: 'r1-$board',
      whitePlayer: _card(white),
      blackPlayer: _card(black),
      whiteTimeDisplay: '',
      blackTimeDisplay: '',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: s,
      roundId: 'round-1',
      roundSlug: 'round-1',
      tourId: 'h2GbjYXa',
      boardNr: board,
    );

// Round 1, real pairings and results: UTRGV-A v UTD-B on boards 1-3,
// UTD-A v TTU-B on boards 9-12.
final _games = [
  _game(1, 'UTRGV Dudin Gleb', 'UTD Koustav Chatterjee', GameStatus.whiteWins),
  _game(
    2,
    'UTD Rahul Srivatshav P',
    'UTRGV Cardoso Cardoso Jose Gabriel',
    GameStatus.blackWins,
  ),
  _game(
    9,
    'UTD Samant Aditya S',
    'TTU Moor Nathaniel Philip',
    GameStatus.whiteWins,
  ),
  _game(10, 'TTU Senol Mert', 'UTD Gorshtein Ido', GameStatus.blackWins),
  _game(11, 'UTD Sankalp Gupta', 'TTU Nguyen Minh Trong', GameStatus.whiteWins),
];

void main() {
  test('h2GbjYXa: a published squad roster finds its UTD-labelled players '
      'and only that squad\'s boards', () {
    final data = _snapshot();
    final teams = data['teams'] as List;
    // Chess-Results spelling, no team prefix; one player has no FIDE id.
    teams[0]['members'] = [
      {'fideId': 35080580, 'name': 'Samant, Aditya S'},
      {'fideId': 2815532, 'name': 'Gorshtein, Ido'},
      {'fideId': 5097010, 'name': 'Sankalp Gupta'},
      {'name': 'Harikrishnan.A.Ra'},
    ];
    teams[2]['members'] = [
      {'fideId': 25073060},
      {'fideId': 25059653},
      {'fideId': 2813408},
      {'fideId': 2620472},
    ];
    final rows = buildOfficialTeamStandings(
      info: _info(data),
      players: _players(),
    )!;

    expect(rows[0].players.map((p) => p.name), [
      'UTD Samant Aditya S',
      'UTD Gorshtein Ido',
      'UTD Sankalp Gupta',
      'UTD Harikrishnan.A.Ra',
    ]);
    expect(rows[2].players.map((p) => p.fideId), [
      25073060,
      25059653,
      2813408,
      2620472,
    ]);

    final matches = buildTeamMatches(
      games: _games,
      teamName: rows[0].teamName,
      link: rows[0].feedLink,
      opponentName: officialTeamOpponentNamer(rows),
    );
    expect(matches, hasLength(1));
    expect(matches.single.boardGames.map((b) => b.boardNr), [9, 10, 11]);
    expect(matches.single.ourPoints, 3);
    // TTU-B published no roster, so the board keeps the feed's label.
    expect(matches.single.opponentTeam, 'TTU');

    final squadB = buildTeamMatches(
      games: _games,
      teamName: rows[2].teamName,
      link: rows[2].feedLink,
      opponentName: officialTeamOpponentNamer(rows),
    );
    expect(squadB.single.boardGames.map((b) => b.boardNr), [1, 2]);
    expect(squadB.single.opponentPoints, 2);
  });

  test('h2GbjYXa without rosters: squads sharing one feed label get '
      'nothing rather than each other\'s players', () {
    final rows = buildOfficialTeamStandings(
      info: _info(_snapshot()),
      players: _players(),
    )!;
    for (final row in rows) {
      expect(row.players, isEmpty, reason: row.teamName);
      expect(row.feedLink, isNull, reason: row.teamName);
    }
  });

  test('a single squad maps to its abbreviated feed label', () {
    final data = _snapshot();
    // One squad per university: the A/B split is gone.
    data['teams'] = [
      _team('University of Texas at Dallas', 1, 7, 11.5, 3, 1, 0),
      _team('University of Texas Rio Grande Valley-A', 2, 6, 11.5, 2, 2, 0),
      _team('Texas Tech University-A', 3, 2, 7, 0, 2, 2),
    ];
    final rows = buildOfficialTeamStandings(
      info: _info(data),
      players: _players(),
    )!;
    expect(rows[0].players, hasLength(8));
    expect(rows[1].players.map((p) => p.team).toSet(), {'UTRGV'});
    expect(rows[2].players, hasLength(3));

    final namer = officialTeamOpponentNamer(rows);
    final matches = buildTeamMatches(
      games: _games,
      teamName: rows[0].teamName,
      link: rows[0].feedLink,
      opponentName: namer,
    );
    expect(matches.map((m) => m.opponentTeam).toSet(), {
      'University of Texas Rio Grande Valley-A',
      'Texas Tech University-A',
    });
    expect(matches.expand((m) => m.boardGames), hasLength(5));
  });

  test('labels that already match keep joining by name', () {
    final data = _snapshot();
    data['teams'] = [
      _team('UTD', 1, 7, 11.5, 3, 1, 0),
      _team('utrgv', 2, 6, 11.5, 2, 2, 0),
      _team('TTU', 3, 2, 7, 0, 2, 2),
    ];
    final rows = buildOfficialTeamStandings(
      info: _info(data),
      players: _players(),
    )!;
    expect(rows.map((t) => t.players.length), [8, 2, 3]);
    final matches = buildTeamMatches(
      games: _games,
      teamName: 'UTD',
      link: rows[0].feedLink,
    );
    expect(matches.expand((m) => m.boardGames), hasLength(5));
  });

  test('folding is accent, punctuation and squad aware', () {
    List<String> linked(List<String> official, List<String> labels) {
      final links = linkOfficialTeamsToFeed(
        official: [for (final n in official) (name: n, members: const [])],
        feedPlayers: [
          for (final l in labels) (team: l, fideId: null, name: 'X $l'),
        ],
      );
      return [for (final n in official) links[n]?.label ?? '-'];
    }

    expect(linked(['SK Köln'], ['sk koln']), ['sk koln']);
    expect(linked(['Texas Tech University-A'], ['TTU-A', 'TTU-B']), ['TTU-A']);
    expect(linked(['Chess Club A', 'Chess Club B'], ['Chess Club']), [
      '-',
      '-',
    ]);
    // An exact join takes the label; the folded candidate does not share it.
    expect(linked(['TTU', 'Texas Tech University'], ['TTU']), ['TTU', '-']);
  });
}
