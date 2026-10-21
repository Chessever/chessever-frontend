import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/standings_builder.dart';
import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/screens/standings/official_team_standings.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/team_scoring_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

PlayerCard _card(String name, String team) => PlayerCard(
  name: name,
  team: team,
  federation: '',
  title: '',
  rating: 2000,
  countryCode: '',
);
GamesTourModel _draw() => GamesTourModel(
  gameId: 'draw',
  roundId: 'r1',
  tourId: 'tour',
  whitePlayer: _card('White', 'Alpha'),
  blackPlayer: _card('Black', 'Beta'),
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: GameStatus.draw,
);

void main() {
  late SupabaseClient client;
  setUp(
    () => client = SupabaseClient(
      'https://example.test',
      'placeholder',
      httpClient: MockClient(
        (request) async => throw StateError(
          'Published standings must not wait for optional enrichment',
        ),
      ),
    ),
  );
  tearDown(() => client.dispose());

  test(
    'official table excludes unranked feed rows and bypasses optional enrichment',
    () async {
      final rows = await buildStandingsFromData(
        supabase: client,
        tournamentPlayers: [
          TournamentPlayer(
            name: 'Published',
            fideId: 1,
            rank: 1,
            score: 3,
            played: 3,
          ),
          TournamentPlayer(name: 'Withdrawn feed row', score: 0, played: 1),
        ],
        gamesTourModels: [_draw()],
        useExternalOrder: true,
      );
      expect(rows.length, 1);
      expect(rows.single.name, 'Published');
      expect(rows.single.overallRank, 1);
      expect(rows.single.matchScore, '3 / 3');
    },
  );

  test('Lichess tied ranks preserve order and custom source scores', () async {
    final rows = await buildStandingsFromData(
      supabase: client,
      tournamentPlayers: [
        TournamentPlayer(
          name: 'First',
          rank: 1,
          score: 3,
          played: 1,
          rating: 1500,
        ),
        TournamentPlayer(
          name: 'Second',
          rank: 1,
          score: 3,
          played: 1,
          rating: 2500,
        ),
        TournamentPlayer(name: 'Third', rank: 3, score: 0, played: 1),
      ],
      gamesTourModels: [],
    );
    expect(rows.map((r) => r.name), ['First', 'Second', 'Third']);
    expect(rows.map((r) => r.overallRank), [1, 1, 3]);
    expect(rows.first.matchScore, '3 / 1');
  });

  test(
    'half-point match draws survive rules, team standings and scorecards',
    () {
      const info = TourInfo(
        teamScoring: {
          'gamePoints': {'whiteWin': 1, 'blackWin': 1, 'draw': 0.5, 'loss': 0},
          'matchPoints': {'win': 1, 'draw': 0.5, 'loss': 0},
        },
      );
      final scoring = TeamScoringRules.fromTourInfo(info);
      expect(scoring.matchDraw, 0.5);
      final teams = buildTeamStandings(
        games: [_draw()],
        playerStandings: [],
        scoring: scoring,
      );
      expect(teams.map((t) => t.matchPoints), [0.5, 0.5]);
      expect(teams.first.matchPointsLabel, '0.5');
      expect(
        buildTeamMatches(
          games: [_draw()],
          teamName: 'Alpha',
          scoring: scoring,
        ).single.matchPoints,
        0.5,
      );
      final official = buildOfficialTeamStandings(
        info: const TourInfo(
          standings: 'https://chess-results.com/tnr123.aspx',
          officialTeamStandings: {
            'source': 'chess-results',
            'sourceUrl': 'https://chess-results.com/tnr123.aspx',
            'fetchedAt': '2026-10-13T13:00:00Z',
            'round': 1,
            'matchScoring': {'win': 1, 'draw': 0.5, 'loss': 0},
            'teams': [
              {
                'name': 'Alpha',
                'rank': 1,
                'matchPoints': 0.5,
                'gamePoints': 0.5,
                'matchesPlayed': 1,
                'wins': 0,
                'draws': 1,
                'losses': 0,
              },
              {
                'name': 'Beta',
                'rank': 1,
                'matchPoints': 0.5,
                'gamePoints': 0.5,
                'matchesPlayed': 1,
                'wins': 0,
                'draws': 1,
                'losses': 0,
              },
            ],
          },
        ),
        players: [],
      );
      expect(official!.map((t) => t.matchPoints), [0.5, 0.5]);
    },
  );
}
