import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_event_view.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
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

    test(
      'keeps finished named no-move games (no-show / forfeit result boards)',
      () {
        final forfeit = _game(
          id: 'forfeit-no-moves',
          whiteName: 'Player A',
          blackName: 'Player B',
          fen: _initialFen,
          gameStatus: GameStatus.whiteWins,
        );

        expect(forfeit.lastMove, isNull);
        expect(forfeit.pgn, isNull);
        expect(isEventBoardGameVisible(forfeit), isTrue);
      },
    );

    test('still hides finished games when players are unresolved', () {
      final unfinishedPlaceholder = _game(
        id: 'finished-placeholder',
        whiteName: '?',
        blackName: '?',
        fen: _initialFen,
        gameStatus: GameStatus.whiteWins,
      );

      expect(isEventBoardGameVisible(unfinishedPlaceholder), isFalse);
    });
  });

  // Ported from the desktop Games view (4b6f2eda). European Club Cup
  // 2026-10-20: each board appeared only after its own first move.
  group('named pairings on an open round', () {
    test('merges unstarted boards onto a live round that has a move', () {
      final started = _game(
        id: 'started-board',
        whiteName: 'White 1',
        blackName: 'Black 1',
        lastMove: 'e2e4',
        boardNr: 1,
      );
      final waiting = [
        _game(
          id: 'waiting-3',
          whiteName: 'White 3',
          blackName: 'Black 3',
          fen: _initialFen,
          boardNr: 3,
        ),
        _game(
          id: 'waiting-2',
          whiteName: 'White 2',
          blackName: 'Black 2',
          fen: _initialFen,
          boardNr: 2,
        ),
      ];

      final merge = _merge(
        roundStatus: RoundStatus.live,
        games: [started, ...waiting],
        visibleIds: {started.gameId},
      );

      expect(merge.markAsPairingOnly, isFalse);
      expect(merge.gamesToAdd.map((game) => game.gameId), [
        'waiting-2',
        'waiting-3',
      ]);
    });

    test('a live round with no moves yet keeps every named board', () {
      final merge = _merge(
        roundStatus: RoundStatus.live,
        games: [
          _game(
            id: 'waiting-1',
            whiteName: 'White 1',
            blackName: 'Black 1',
            fen: _initialFen,
          ),
          _game(id: 'placeholder', whiteName: '?', blackName: '?'),
        ],
        visibleIds: <String>{},
      );

      expect(merge.markAsPairingOnly, isTrue);
      expect(merge.gamesToAdd.map((game) => game.gameId), ['waiting-1']);
    });

    test('leaves a completed round alone', () {
      final merge = _merge(
        roundStatus: RoundStatus.completed,
        games: [
          _game(
            id: 'late-pairing',
            whiteName: 'White 1',
            blackName: 'Black 1',
            fen: _initialFen,
          ),
        ],
        visibleIds: <String>{},
      );

      expect(merge.gamesToAdd, isEmpty);
      expect(merge.markAsPairingOnly, isFalse);
    });

    test(
      'a knockout stage row keeps the named boards of its source rounds',
      () {
        // Speed Chess Championship: the stage row is synthetic, so the boards'
        // own round id never equals it; membership comes from the stage.
        final merge = resolveNamedPairingsForRound(
          roundStatus: RoundStatus.upcoming,
          allGames: [
            _game(
              id: 'r16-1',
              whiteName: 'Nakamura, Hikaru',
              blackName: 'Erdogmus, Yagiz Kaan',
              fen: _initialFen,
            ),
          ],
          roundId: 'knockout-stage-tour-1-r16',
          knownRoundIds: const <String>{},
          defaultRoundId: null,
          alreadyVisibleGameIds: <String>{},
          includeGame: (_) => true,
          belongsToRound: (game) => game.roundId == 'round-8',
        );

        expect(merge.markAsPairingOnly, isTrue);
        expect(merge.gamesToAdd.map((game) => game.gameId), ['r16-1']);
      },
    );
  });

  // Speed Chess Championship plays one match a day for a month in a single
  // round file. Between match days the round leaves the live list and, 24
  // hours after its start, its stage row reads `completed`.
  group('a completed knockout stage keeps its unplayed matches', () {
    const stageId = 'knockout-stage-fqCjSUpE-round-of-16';
    GamesAppBarModel stage(RoundStatus status, {String id = stageId}) =>
        GamesAppBarModel(
          id: id,
          name: 'Round of 16',
          startsAt: DateTime.utc(2026, 11, 16, 17),
          roundStatus: status,
        );
    // Nakamura-Erdogmus played both games; Carlsen-Movahed has not started.
    final matchPlayStage = [
      _game(
        id: 'g1',
        whiteName: 'Nakamura, Hikaru',
        blackName: 'Erdogmus, Yagiz Kaan',
        lastMove: 'e2e4',
        gameStatus: GameStatus.draw,
      ),
      _game(
        id: 'g2',
        whiteName: 'Erdogmus, Yagiz Kaan',
        blackName: 'Nakamura, Hikaru',
        lastMove: 'e2e4',
        gameStatus: GameStatus.blackWins,
      ),
      _game(
        id: 'c1',
        whiteName: 'Carlsen, Magnus',
        blackName: 'Movahed, Sina',
        fen: _initialFen,
      ),
    ];

    test('a match-play stage with an unplayed named board stays open', () {
      final status = namedPairingStatusForKnockoutStage(
        round: stage(RoundStatus.completed),
        isKnockoutTournament: true,
        stageGames: () => matchPlayStage,
      );
      expect(status, RoundStatus.ongoing);

      final merge = resolveNamedPairingsForRound(
        roundStatus: status,
        allGames: matchPlayStage,
        roundId: stageId,
        knownRoundIds: const <String>{},
        defaultRoundId: null,
        alreadyVisibleGameIds: {'g1', 'g2'},
        includeGame: (_) => true,
        belongsToRound: (game) => game.roundId == 'round-8',
      );
      expect(merge.gamesToAdd.map((game) => game.gameId), ['c1']);
      expect(merge.markAsPairingOnly, isFalse);
    });

    test('a stale shell beside a decided match stays hidden', () {
      // Nakamura-Erdogmus is decided, yet a 0-move game-5 board remains.
      final games = [
        ...matchPlayStage,
        _game(
          id: 'g5',
          whiteName: 'Nakamura, Hikaru',
          blackName: 'Erdogmus, Yagiz Kaan',
          fen: _initialFen,
        ),
      ];
      final policy = namedPairingPolicyForKnockoutStage(
        round: stage(RoundStatus.completed),
        isKnockoutTournament: true,
        stageGames: () => games,
      );
      expect(policy.status, RoundStatus.ongoing);

      final merge = resolveNamedPairingsForRound(
        roundStatus: policy.status,
        allGames: games,
        roundId: stageId,
        knownRoundIds: const <String>{},
        defaultRoundId: null,
        alreadyVisibleGameIds: {'g1', 'g2'},
        includeGame: policy.includeGame,
        belongsToRound: (game) => game.roundId == 'round-8',
      );
      expect(merge.gamesToAdd.map((game) => game.gameId), ['c1']);
    });

    test('a match being played keeps its next board', () {
      // Match day with the row already `completed`: Lazavik-Andreikin plays
      // game 1, game 2 waits as a shell; every other match is decided.
      final games = [
        ...matchPlayStage.take(2),
        _game(
          id: 'l1',
          whiteName: 'Lazavik, Denis',
          blackName: 'Andreikin, Dmitry',
          lastMove: 'e2e4',
        ),
        _game(
          id: 'l2',
          whiteName: 'Andreikin, Dmitry',
          blackName: 'Lazavik, Denis',
          fen: _initialFen,
        ),
      ];
      final policy = namedPairingPolicyForKnockoutStage(
        round: stage(RoundStatus.completed),
        isKnockoutTournament: true,
        stageGames: () => games,
      );
      expect(policy.status, RoundStatus.ongoing);
      expect(games.where(policy.includeGame).map((game) => game.gameId), [
        'l1',
        'l2',
      ]);
    });

    // Women's Speed Chess Championship 2026 (QfveGZSJ) quarterfinals,
    // finished in July: round mxUBhpuf holds Assaubayeva-Divya's games and
    // two stale 0-move boards of matches decided in rounds of their own.
    test('stale shells never reopen a finished stage', () {
      GamesTourModel played(String id, String white, String black, String r) =>
          _game(
            id: id,
            whiteName: white,
            blackName: black,
            lastMove: 'e2e4',
            gameStatus: GameStatus.draw,
            roundId: r,
          );
      final games = [
        played('hm-1', 'Hou, Yifan', 'Muzychuk, Anna', 'qf-hm'),
        played('hm-2', 'Muzychuk, Anna', 'Hou, Yifan', 'qf-hm'),
        played('jl-1', 'Ju, Wenjun', 'Lee, Alice', 'qf-jl'),
        played('jl-2', 'Lee, Alice', 'Ju, Wenjun', 'qf-jl'),
        played('ad-1', 'Assaubayeva, Bibisara', 'Divya Deshmukh', 'mxUBhpuf'),
        played('ad-2', 'Divya Deshmukh', 'Assaubayeva, Bibisara', 'mxUBhpuf'),
        _game(
          id: 'ATOiBzAp',
          whiteName: 'Hou, Yifan',
          blackName: 'Muzychuk, Anna',
          fen: _initialFen,
          roundId: 'mxUBhpuf',
        ),
        _game(
          id: 'c15eBGgb',
          whiteName: 'Ju, Wenjun',
          blackName: 'Lee, Alice',
          fen: _initialFen,
          roundId: 'mxUBhpuf',
        ),
      ];
      final policy = namedPairingPolicyForKnockoutStage(
        round: stage(RoundStatus.completed),
        isKnockoutTournament: true,
        stageGames: () => games,
      );
      expect(policy.status, RoundStatus.completed);
      final merge = resolveNamedPairingsForRound(
        roundStatus: policy.status,
        allGames: games,
        roundId: stageId,
        knownRoundIds: const <String>{},
        defaultRoundId: null,
        alreadyVisibleGameIds: {
          for (final game in games)
            if (game.lastMove != null) game.gameId,
        },
        includeGame: policy.includeGame,
        belongsToRound: (_) => true,
      );
      expect(merge.gamesToAdd, isEmpty);
    });

    test('every other row keeps its own status', () {
      // A stage whose every board is decided.
      expect(
        namedPairingStatusForKnockoutStage(
          round: stage(RoundStatus.completed),
          isKnockoutTournament: true,
          stageGames: () => matchPlayStage.take(2),
        ),
        RoundStatus.completed,
      );
      // One game per pairing (legs in rounds of their own): not match play.
      expect(
        namedPairingStatusForKnockoutStage(
          round: stage(RoundStatus.completed),
          isKnockoutTournament: true,
          stageGames: () => [matchPlayStage.first, matchPlayStage.last],
        ),
        RoundStatus.completed,
      );
      // A plain round row, and a non-knockout event.
      expect(
        namedPairingStatusForKnockoutStage(
          round: stage(RoundStatus.completed, id: 'round-8'),
          isKnockoutTournament: true,
          stageGames: () => matchPlayStage,
        ),
        RoundStatus.completed,
      );
      expect(
        namedPairingStatusForKnockoutStage(
          round: stage(RoundStatus.completed),
          isKnockoutTournament: false,
          stageGames: () => matchPlayStage,
        ),
        RoundStatus.completed,
      );
      // Open rows are never touched.
      for (final status in [
        RoundStatus.live,
        RoundStatus.ongoing,
        RoundStatus.upcoming,
      ]) {
        expect(
          namedPairingStatusForKnockoutStage(
            round: stage(status),
            isKnockoutTournament: true,
            stageGames: () => matchPlayStage,
          ),
          status,
        );
      }
    });
  });
}

NamedPairingMerge _merge({
  required RoundStatus roundStatus,
  required List<GamesTourModel> games,
  required Set<String> visibleIds,
}) {
  return resolveNamedPairingsForRound(
    roundStatus: roundStatus,
    allGames: games,
    roundId: 'round-8',
    knownRoundIds: {'round-8'},
    defaultRoundId: 'round-8',
    alreadyVisibleGameIds: visibleIds,
    includeGame: (_) => true,
  );
}

const _initialFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

GamesTourModel _game({
  required String id,
  required String whiteName,
  required String blackName,
  String? lastMove,
  String? fen,
  String? pgn,
  int? boardNr,
  GameStatus gameStatus = GameStatus.ongoing,
  String roundId = 'round-8',
}) {
  return GamesTourModel(
    gameId: id,
    whitePlayer: _player(whiteName),
    blackPlayer: _player(blackName),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: gameStatus,
    roundId: roundId,
    tourId: 'tour-1',
    lastMove: lastMove,
    fen: fen,
    pgn: pgn,
    boardNr: boardNr,
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
