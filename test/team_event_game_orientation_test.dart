import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_stable_order_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/group_event_match_card_provider.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerCard _card(String name, String team) => PlayerCard(
  name: name,
  federation: '',
  title: '',
  rating: 2000,
  countryCode: '',
  team: team,
);

GamesTourModel _game({
  required String id,
  required String whiteName,
  required String whiteTeam,
  required String blackName,
  required String blackTeam,
  int? boardNr,
}) => GamesTourModel(
  gameId: id,
  boardNr: boardNr,
  whitePlayer: _card(whiteName, whiteTeam),
  blackPlayer: _card(blackName, blackTeam),
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: GameStatus.ongoing,
  roundId: 'round-1',
  tourId: 'team-event',
);

void main() {
  final games = [
    _game(
      id: 'board-1',
      boardNr: 1,
      whiteName: 'A One',
      whiteTeam: 'Team A',
      blackName: 'B One',
      blackTeam: 'Team B',
    ),
    _game(
      id: 'board-2',
      boardNr: 2,
      whiteName: 'B Two',
      whiteTeam: 'Team B',
      blackName: 'A Two',
      blackTeam: 'Team A',
    ),
  ];

  test('one team stays on one side when its board colors alternate', () {
    final grouped = groupTeamGamesByMatchup(
      selectedRoundId: 'round-1',
      games: games,
    );

    expect(grouped.keys, ['Team A vs Team B']);
    final boards = grouped.values.single;
    expect(boards.map((board) => board.comparison), [
      MatchComparison.sameOrder,
      MatchComparison.oppositeOrder,
    ]);
    expect(boards.map((board) => teamOneBottomSide(board.comparison)), [
      Side.white,
      Side.black,
    ]);
    expect(boards.map((board) => teamOrderedPlayers(board).teamOne.team), [
      'Team A',
      'Team A',
    ]);
    expect(boards.map((board) => teamOrderedPlayers(board).teamTwo.team), [
      'Team B',
      'Team B',
    ]);
  });

  test('manual pins, auto pins and unpin all preserve matchup sides', () {
    final stableOrder = GamesTourStableOrder();
    for (final priority in [
      (manual: <String>{}, favorite: <String>{}, country: <String>{}),
      (manual: {'board-2'}, favorite: <String>{}, country: <String>{}),
      (manual: <String>{}, favorite: <String>{}, country: <String>{}),
      (manual: <String>{}, favorite: {'board-2'}, country: <String>{}),
      (manual: <String>{}, favorite: <String>{}, country: {'board-2'}),
      (manual: {'board-1'}, favorite: <String>{}, country: {'board-2'}),
      (manual: <String>{}, favorite: <String>{}, country: <String>{}),
    ]) {
      final order = resolveTournamentRoundPresentationOrder(
        stableOrder: stableOrder,
        roundId: 'round-1',
        games: games,
        isSearchMode: false,
        hasResolvedAutoPins: true,
        isRefreshingAutoPins: false,
        pinnedGameIds: priority.manual,
        favoriteGameIds: priority.favorite,
        countrymanGameIds: priority.country,
      );
      final secondBoardLeads =
          priority.manual.contains('board-2') ||
          (priority.manual.isEmpty &&
              (priority.favorite.contains('board-2') ||
                  priority.country.contains('board-2')));
      expect(order.first.gameId, secondBoardLeads ? 'board-2' : 'board-1');
      final grouped = groupTeamGamesByMatchup(
        selectedRoundId: 'round-1',
        games: order,
      );
      expect(grouped.keys, ['Team A vs Team B']);
      expect(
        grouped.values.single.map((b) => b.game.gameId),
        order.map((g) => g.gameId),
      );
      for (final board in grouped.values.single) {
        expect(teamOrderedPlayers(board).teamOne.team, 'Team A');
        expect(teamOrderedPlayers(board).teamTwo.team, 'Team B');
        expect(
          teamOneBottomSide(board.comparison),
          board.game.gameId == 'board-1' ? Side.white : Side.black,
        );
      }
    }
  });

  test('missing board numbers still keep sides stable across pin sorting', () {
    final unnumbered = [
      for (final game in games)
        _game(
          id: game.gameId,
          whiteName: game.whitePlayer.name,
          whiteTeam: game.whitePlayer.team!,
          blackName: game.blackPlayer.name,
          blackTeam: game.blackPlayer.team!,
        ),
    ];
    for (final order in [unnumbered, unnumbered.reversed.toList()]) {
      final grouped = groupTeamGamesByMatchup(
        selectedRoundId: 'round-1',
        games: order,
      );
      expect(grouped.keys, ['Team A vs Team B']);
      for (final board in grouped.values.single) {
        expect(teamOrderedPlayers(board).teamOne.team, 'Team A');
        expect(teamOrderedPlayers(board).teamTwo.team, 'Team B');
      }
    }
  });

  test('empty team tags do not invent country matchups', () {
    final unlabeled = [
      _game(
        id: 'board-1',
        whiteName: 'A One',
        whiteTeam: '',
        blackName: 'B One',
        blackTeam: '',
      ),
    ];
    final grouped = groupTeamGamesByMatchup(
      selectedRoundId: 'round-1',
      games: unlabeled,
      fallbackMatchupTitle: pairingTitleFromRoundName(
        'FYERS American Gambits - Triveni Continental Kings',
      ),
    );
    expect(grouped.keys, [
      'FYERS American Gambits vs Triveni Continental Kings',
    ]);
  });

  test('pairingTitleFromRoundName only rewrites a two-team title', () {
    expect(
      pairingTitleFromRoundName(
        'Triveni Continental Kings - Fyers American Gambits',
      ),
      'Triveni Continental Kings vs Fyers American Gambits',
    );
    expect(pairingTitleFromRoundName('Round 5'), isNull);
  });

  test('match header uses Lichess customPoints, not 1 / ½', () {
    final finished = GamesTourModel(
      gameId: 'board-1',
      whitePlayer: _card('A One', 'Team A').copyWith(customPoints: 0),
      blackPlayer: _card('B One', 'Team B').copyWith(customPoints: 4),
      whiteTimeDisplay: '',
      blackTimeDisplay: '',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.blackWins,
      roundId: 'round-1',
      tourId: 'team-event',
    );
    final score = matchScoreForGames(
      matchList: [
        MatchWithComparison(
          game: finished,
          comparison: MatchComparison.sameOrder,
        ),
      ],
    );
    expect(score, [0.0, 4.0]);
  });

  group('matchComparisonForSelectedTeamSide', () {
    test('selected team White → sameOrder (left is White)', () {
      final comparison = matchComparisonForSelectedTeamSide(
        selectedTeamIsWhite: true,
      );
      expect(comparison, MatchComparison.sameOrder);
      expect(teamOneBottomSide(comparison), Side.white);

      final ordered = teamOrderedPlayers(
        MatchWithComparison(game: games[0], comparison: comparison),
      );
      expect(ordered.teamOne.team, 'Team A');
      expect(ordered.teamOne.name, 'A One');
      expect(ordered.teamTwo.team, 'Team B');
    });

    test('selected team Black → oppositeOrder (left is Black)', () {
      // Board 2: Team A is Black. Score card must still put Team A on left.
      final comparison = matchComparisonForSelectedTeamSide(
        selectedTeamIsWhite: false,
      );
      expect(comparison, MatchComparison.oppositeOrder);
      expect(teamOneBottomSide(comparison), Side.black);

      final ordered = teamOrderedPlayers(
        MatchWithComparison(game: games[1], comparison: comparison),
      );
      expect(ordered.teamOne.team, 'Team A');
      expect(ordered.teamOne.name, 'A Two');
      expect(ordered.teamTwo.team, 'Team B');
      expect(ordered.teamTwo.name, 'B Two');
    });

    test(
      'alternating board colors keep selected team on left for every board',
      () {
        // Mirrors team score card / standings expand path: each board's
        // ourIsWhite drives comparison (games[0] Team A White, games[1] Black).
        final ourIsWhitePerBoard = [true, false];
        final comparisons = [
          for (final oursWhite in ourIsWhitePerBoard)
            matchComparisonForSelectedTeamSide(selectedTeamIsWhite: oursWhite),
        ];

        expect(comparisons, [
          MatchComparison.sameOrder,
          MatchComparison.oppositeOrder,
        ]);

        for (var i = 0; i < games.length; i++) {
          final ordered = teamOrderedPlayers(
            MatchWithComparison(game: games[i], comparison: comparisons[i]),
          );
          expect(
            ordered.teamOne.team,
            'Team A',
            reason: 'board ${i + 1}: selected team must stay left',
          );
          expect(ordered.teamTwo.team, 'Team B');
        }
      },
    );
  });
}
