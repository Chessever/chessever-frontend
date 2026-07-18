import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:flutter_test/flutter_test.dart';

TournamentPlayer _player(String name, {String? team}) =>
    TournamentPlayer(name: name, played: 0, team: team);

PlayerCard _card(String name, String team) => PlayerCard(
  name: name,
  federation: 'GRE',
  title: '',
  rating: 2000,
  countryCode: 'GRE',
  team: team,
);

GamesTourModel _game({
  required String round,
  required String whiteTeam,
  required String blackTeam,
  int board = 1,
}) => GamesTourModel(
  gameId: '$round-$whiteTeam-$blackTeam-$board',
  whitePlayer: _card('W $board', whiteTeam),
  blackPlayer: _card('B $board', blackTeam),
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: GameStatus.whiteWins,
  roundId: round,
  tourId: 't',
  boardNr: board,
);

/// A completed team match: two boards in one round between the same two
/// teams (colors alternating across boards, as lichess broadcasts do).
List<GamesTourModel> _teamMatchGames() => [
  _game(round: 'r1', whiteTeam: 'Alpha', blackTeam: 'Beta', board: 1),
  _game(round: 'r1', whiteTeam: 'Beta', blackTeam: 'Alpha', board: 2),
];

void main() {
  group('resolveIsTeamEvent — explicit teamTable signal', () {
    test('teamTable true is authoritative even against a player format', () {
      expect(
        resolveIsTeamEvent(
          teamTable: true,
          formatString: '206-player Single-elimination Knockout',
          players: [_player('A'), _player('B')],
          games: const [],
        ),
        isTrue,
      );
    });

    test('teamTable true short-circuits the team-battle exclusion', () {
      expect(
        resolveIsTeamEvent(
          teamTable: true,
          formatString: 'Team Battle',
          players: const [],
          games: const [],
        ),
        isTrue,
      );
    });

    test('teamTable false still honors an explicit team format token', () {
      expect(
        resolveIsTeamEvent(
          teamTable: false,
          formatString: '7-round Swiss (team)',
          players: const [],
          games: const [],
        ),
        isTrue,
      );
    });

    test('teamTable false suppresses roster and game heuristics', () {
      expect(
        resolveIsTeamEvent(
          teamTable: false,
          formatString: '9-round Swiss',
          players: [_player('A', team: 'Alpha'), _player('B', team: 'Beta')],
          games: _teamMatchGames(),
        ),
        isFalse,
      );
    });
  });

  group('resolveIsTeamEvent — absent key falls back to heuristics', () {
    test('structural signal: two boards in one round between one pair', () {
      expect(
        resolveIsTeamEvent(
          teamTable: null,
          formatString: '9-round Swiss',
          players: const [],
          games: _teamMatchGames(),
        ),
        isTrue,
      );
    });

    test('one board per (round, pair) is not a team match', () {
      expect(
        resolveIsTeamEvent(
          teamTable: null,
          formatString: '9-round Swiss',
          players: const [],
          games: [
            _game(round: 'r1', whiteTeam: 'Alpha', blackTeam: 'Beta'),
            _game(round: 'r2', whiteTeam: 'Beta', blackTeam: 'Alpha'),
            _game(round: 'r1', whiteTeam: 'Gamma', blackTeam: 'Delta'),
          ],
        ),
        isFalse,
      );
    });

    test('clubmates paired 1v1 (same team both sides) never count', () {
      expect(
        resolveIsTeamEvent(
          teamTable: null,
          formatString: null,
          players: const [],
          games: [
            _game(round: 'r1', whiteTeam: 'Alpha', blackTeam: 'Alpha'),
            _game(round: 'r1', whiteTeam: 'Alpha', blackTeam: 'Alpha', board: 2),
          ],
        ),
        isFalse,
      );
    });

    test(
      'club-tagged individual knockout (FIDE World Cup shape) stays false',
      () {
        // Every player carries a club AND boards repeat a pair, but the
        // curated "N-player" format token vetoes the inferred signals.
        expect(
          resolveIsTeamEvent(
            teamTable: null,
            formatString: '206-player Single-elimination Knockout',
            players: [
              _player('A', team: 'Club A'),
              _player('B', team: 'Club B'),
            ],
            games: _teamMatchGames(),
          ),
          isFalse,
        );
      },
    );

    test('team battle / arena formats are excluded', () {
      for (final format in ['Team Battle', 'team-battle', 'Arena']) {
        expect(
          resolveIsTeamEvent(
            teamTable: null,
            formatString: format,
            players: [_player('A', team: 'Alpha'), _player('B', team: 'Beta')],
            games: _teamMatchGames(),
          ),
          isFalse,
          reason: 'format "$format" must not be a board-vs-board team event',
        );
      }
    });

    test('"team" must match as a whole word — "Steam" does not qualify', () {
      expect(
        resolveIsTeamEvent(
          teamTable: null,
          formatString: '5-round Steam Masters Swiss',
          players: const [],
          games: const [],
        ),
        isFalse,
      );
      // But real word-boundary hits do, including hyphen-normalized ones.
      expect(
        resolveIsTeamEvent(
          teamTable: null,
          formatString: '16-team Knockout',
          players: const [],
          games: const [],
        ),
        isTrue,
      );
    });

    test('roster threshold: >= 80% teamed qualifies, below does not', () {
      final fourOfFive = [
        _player('A', team: 'Alpha'),
        _player('B', team: 'Alpha'),
        _player('C', team: 'Beta'),
        _player('D', team: 'Beta'),
        _player('E'), // untagged substitute must not flip the layout
      ];
      expect(
        resolveIsTeamEvent(
          teamTable: null,
          formatString: 'Knockout',
          players: fourOfFive,
          games: const [],
        ),
        isTrue,
      );

      final threeOfFive = [
        _player('A', team: 'Alpha'),
        _player('B', team: 'Alpha'),
        _player('C', team: 'Beta'),
        _player('D'),
        _player('E', team: '   '), // whitespace-only tag does not count
      ];
      expect(
        resolveIsTeamEvent(
          teamTable: null,
          formatString: 'Knockout',
          players: threeOfFive,
          games: const [],
        ),
        isFalse,
      );
    });

    test('no signals at all resolves to false', () {
      expect(
        resolveIsTeamEvent(
          teamTable: null,
          formatString: null,
          players: const [],
          games: const [],
        ),
        isFalse,
      );
    });
  });

  group('TourInfo.teamTable parsing', () {
    test('parses explicit booleans and keeps absence as null', () {
      expect(TourInfo.fromJson(const {'teamTable': true}).teamTable, isTrue);
      expect(TourInfo.fromJson(const {'teamTable': false}).teamTable, isFalse);
      expect(TourInfo.fromJson(const {}).teamTable, isNull);
      // Defensive: a non-bool value is unknown, not a positive.
      expect(TourInfo.fromJson(const {'teamTable': 'yes'}).teamTable, isNull);
    });

    test('toJson round-trips the flag and omits it when null', () {
      expect(const TourInfo(teamTable: true).toJson()['teamTable'], isTrue);
      expect(const TourInfo().toJson().containsKey('teamTable'), isFalse);
    });
  });
}
