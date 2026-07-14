import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_event_view.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('event board placeholder filtering', () {
    test('hides unresolved starting-position placeholders', () {
      final placeholder = _game(
        id: 'future-placeholder',
        whiteName: '?',
        blackName: '?',
        fen: _initialFen,
      );

      expect(isEventBoardGameVisible(placeholder), isFalse);
    });

    test(
      'hides named unstarted pairings so future rounds are not board cards',
      () {
        final futurePairing = _game(
          id: 'future-pairing',
          whiteName: 'Player A',
          blackName: 'Player B',
          fen: _initialFen,
        );

        expect(isEventBoardGameVisible(futurePairing), isFalse);
      },
    );

    test('keeps real games with resolved players and moves', () {
      final liveGame = _game(
        id: 'live-game',
        whiteName: 'Player A',
        blackName: 'Player B',
        lastMove: 'e2e4',
        fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
      );

      expect(isEventBoardGameVisible(liveGame), isTrue);
    });

    test('keeps PGN-only games even when last_move is missing', () {
      final pgnGame = _game(
        id: 'pgn-game',
        whiteName: 'Player A',
        blackName: 'Player B',
        pgn: '[Event "Demo"]\n\n1. e4 e5 2. Nf3',
      );

      expect(isEventBoardGameVisible(pgnGame), isTrue);
    });

    test('keeps completed virtual Gamebase games with header-only PGN', () {
      final games = virtualGamesFromView(
        _virtualEventView(),
        virtualId: 'gamebase::6th elllobregat Open 2025',
      );
      final model = GamesTourModel.fromGame(games.single);

      expect(model.source, GameSource.gamebase);
      expect(model.gameStatus, GameStatus.whiteWins);
      expect(model.lastMove, isNull);
      expect(model.fen, isNull);
      expect(isEventBoardGameVisible(model), isTrue);
    });
  });
}

const _initialFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

GamesTourModel _game({
  required String id,
  required String whiteName,
  required String blackName,
  String? lastMove,
  String? fen,
  String? pgn,
}) {
  return GamesTourModel(
    gameId: id,
    whitePlayer: _player(whiteName),
    blackPlayer: _player(blackName),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.ongoing,
    roundId: 'round-8',
    tourId: 'tour-1',
    lastMove: lastMove,
    fen: fen,
    pgn: pgn,
  );
}

PlayerCard _player(String name) {
  return PlayerCard(
    name: name,
    federation: 'USA',
    title: '',
    rating: 2500,
    countryCode: 'USA',
    team: null,
  );
}

GamebaseEventView _virtualEventView() {
  const white = GamebaseEventPlayerRef(
    name: 'Player A',
    fideId: '1',
    title: 'GM',
    elo: 2500,
    fed: 'ESP',
    team: null,
  );
  const black = GamebaseEventPlayerRef(
    name: 'Player B',
    fideId: '2',
    title: 'IM',
    elo: 2400,
    fed: 'ESP',
    team: null,
  );
  const game = GamebaseEventGame(
    id: 'gamebase-game-1',
    round: '1',
    board: 1,
    white: white,
    black: black,
    result: '1-0',
    date: null,
    eco: 'C50',
    opening: 'Italian Game',
  );

  return const GamebaseEventView(
    event: '6th elllobregat Open 2025',
    site: 'Sant Boi ESP',
    image: null,
    format: 'regular',
    formatLabel: null,
    truncated: false,
    about: GamebaseEventAbout(
      gameCount: 1,
      playerCount: 2,
      teamCount: null,
      roundCount: 1,
      startDate: null,
      endDate: null,
      timeControl: 'CLASSICAL',
      avgElo: 2450,
      maxElo: 2500,
      site: 'Sant Boi ESP',
      image: null,
    ),
    rounds: [
      GamebaseEventRound(label: '1', sortKey: 1, date: null, games: [game]),
    ],
    standings: GamebaseEventStandings(kind: 'player', players: [], teams: []),
    games: [game],
  );
}
