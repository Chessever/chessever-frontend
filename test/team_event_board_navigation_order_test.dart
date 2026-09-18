// Regression: team-event board swiping used to jump to the next team's match.
// The Games-tab sort is round DESC → game DESC → board ASC, and team board
// numbers restart per pairing, so the flat list interleaves matchups. The
// board switcher must page through the Games tab's rendered card order
// instead: per round, matchups in first-seen order, then their boards.
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerCard _card(String name, String? team) => PlayerCard(
  name: name,
  federation: '',
  title: '',
  rating: 2000,
  countryCode: '',
  team: team,
);

GamesTourModel _game({
  required String id,
  required String roundId,
  required int board,
  required String whiteName,
  required String? whiteTeam,
  required String blackName,
  required String? blackTeam,
  String? roundSlug,
}) => GamesTourModel(
  gameId: id,
  roundId: roundId,
  tourId: 'team-event',
  whitePlayer: _card(whiteName, whiteTeam),
  blackPlayer: _card(blackName, blackTeam),
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: GameStatus.ongoing,
  boardNr: board,
  roundSlug: roundSlug,
);

/// One round, two matchups, boards restarting at 1 per pairing — the flat
/// Games-tab sort interleaves them A1, B1, A2, B2.
List<GamesTourModel> _interleavedRound() => [
  _game(
    id: 'a1',
    roundId: 'r1',
    board: 1,
    whiteName: 'A One',
    whiteTeam: 'Team A',
    blackName: 'B One',
    blackTeam: 'Team B',
  ),
  _game(
    id: 'b1',
    roundId: 'r1',
    board: 1,
    whiteName: 'C One',
    whiteTeam: 'Team C',
    blackName: 'D One',
    blackTeam: 'Team D',
  ),
  _game(
    id: 'a2',
    roundId: 'r1',
    board: 2,
    whiteName: 'B Two',
    whiteTeam: 'Team B',
    blackName: 'A Two',
    blackTeam: 'Team A',
  ),
  _game(
    id: 'b2',
    roundId: 'r1',
    board: 2,
    whiteName: 'D Two',
    whiteTeam: 'Team D',
    blackName: 'C Two',
    blackTeam: 'Team C',
  ),
];

void main() {
  test('switcher follows the matchup cards, not the flat board-number sort', () {
    final games = _interleavedRound();
    final expected = ['a1', 'a2', 'b1', 'b2'];

    expect(
      orderTeamEventGamesForBoardNavigation(
        games,
      ).map((game) => game.gameId),
      expected,
    );
    // The immediate list built from the rendered groups must match the
    // expansion path exactly, or the switcher would re-shuffle mid-open.
    expect(
      orderedGamesForTeamMatchups(
        groupTeamGamesByMatchup(selectedRoundId: 'r1', games: games),
      ).map((game) => game.gameId),
      expected,
    );
  });

  test('round order survives regrouping', () {
    final games = [
      ..._interleavedRound().map((game) => game.copyWith(roundId: 'r2')),
      ..._interleavedRound(),
    ];
    final ordered = orderTeamEventGamesForBoardNavigation(games);

    expect(ordered.map((game) => '${game.roundId}:${game.gameId}'), [
      'r2:a1',
      'r2:a2',
      'r2:b1',
      'r2:b2',
      'r1:a1',
      'r1:a2',
      'r1:b1',
      'r1:b2',
    ]);
  });

  test('only lists where every game carries teams are regrouped', () {
    expect(looksLikeTeamMatchupGames(_interleavedRound()), isTrue);
    expect(
      looksLikeTeamMatchupGames([
        _game(
          id: 'no-team',
          roundId: 'r1',
          board: 1,
          whiteName: 'A One',
          whiteTeam: null,
          blackName: 'B One',
          blackTeam: 'Team B',
        ),
      ]),
      isFalse,
    );
    // Knockout feeds repeat a slug game-N and already render match-grouped.
    expect(
      looksLikeTeamMatchupGames([
        _game(
          id: 'k1',
          roundId: 'r1',
          board: 1,
          whiteName: 'A One',
          whiteTeam: 'Team A',
          blackName: 'B One',
          blackTeam: 'Team B',
          roundSlug: 'game-1',
        ),
        _game(
          id: 'k2',
          roundId: 'r1',
          board: 2,
          whiteName: 'A One',
          whiteTeam: 'Team A',
          blackName: 'B One',
          blackTeam: 'Team B',
          roundSlug: 'game-2',
        ),
        _game(
          id: 'k3',
          roundId: 'r1',
          board: 3,
          whiteName: 'C One',
          whiteTeam: 'Team C',
          blackName: 'D One',
          blackTeam: 'Team D',
          roundSlug: 'game-3',
        ),
        _game(
          id: 'k4',
          roundId: 'r1',
          board: 4,
          whiteName: 'C One',
          whiteTeam: 'Team C',
          blackName: 'D One',
          blackTeam: 'Team D',
          roundSlug: 'game-4',
        ),
      ]),
      isFalse,
    );
  });
}
