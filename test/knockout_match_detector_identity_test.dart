import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KnockoutMatchDetector participant identity', () {
    test('groups legs by FIDE ids despite title and case changes', () {
      final matches = KnockoutMatchDetector.groupByMatches([
        _game(
          id: 'g1',
          white: _player('GM Alpha Player', fideId: 11),
          black: _player('Beta Player', fideId: 22),
          slug: 'game-1',
        ),
        _game(
          id: 'g2',
          white: _player('beta player', fideId: 22),
          black: _player('ALPHA PLAYER', fideId: 11),
          slug: 'game-2',
        ),
      ]);

      expect(matches, hasLength(1));
      expect(matches.values.single.map((game) => game.gameId), ['g1', 'g2']);
      expect(matches.keys.single, 'fide:11|fide:22');
    });

    test('uses title-free case-normalized names without FIDE ids', () {
      final matches = KnockoutMatchDetector.groupByMatches([
        _game(
          id: 'g1',
          white: _player('IM Gamma  Player'),
          black: _player('WGM Delta Player'),
          slug: 'game-1',
        ),
        _game(
          id: 'g2',
          white: _player('delta player'),
          black: _player('gamma player'),
          slug: 'game-2',
        ),
      ]);

      expect(matches, hasLength(1));
      expect(matches.keys.single, 'name:delta player|name:gamma player');
    });

    test('fills a missing leg FIDE id from an unambiguous normalized name', () {
      final matches = KnockoutMatchDetector.groupByMatches([
        _game(
          id: 'g1',
          white: _player('GM Alpha Player', fideId: 11),
          black: _player('Beta Player', fideId: 22),
          slug: 'game-1',
        ),
        _game(
          id: 'g2',
          white: _player('beta player'),
          black: _player('alpha player'),
          slug: 'game-2',
        ),
      ]);

      expect(matches, hasLength(1));
      expect(matches.keys.single, 'fide:11|fide:22');
    });

    test('does not create repeatable matchups from placeholder players', () {
      final games = [
        _game(
          id: 'g1',
          white: _player('?'),
          black: _player('TBD'),
          slug: 'game-1',
        ),
        _game(
          id: 'g2',
          white: _player('Unknown Player'),
          black: _player('TBA'),
          slug: 'game-2',
        ),
        _game(
          id: 'g3',
          white: _player('?'),
          black: _player('TBD'),
          slug: 'game-1',
        ),
        _game(
          id: 'g4',
          white: _player('Unknown Player'),
          black: _player('TBA'),
          slug: 'game-2',
        ),
      ];

      expect(KnockoutMatchDetector.groupByMatches(games), isEmpty);
      expect(KnockoutMatchDetector.isKnockoutMatchFormat(games), isFalse);
    });

    test('detects replay games appended to one source round', () {
      final alpha = _player('Alpha', fideId: 11);
      final beta = _player('Beta', fideId: 22);
      final gamma = _player('Gamma', fideId: 33);
      final delta = _player('Delta', fideId: 44);
      final games = [
        _game(
          id: 'board-1',
          white: alpha,
          black: beta,
          slug: 'lower-round-1',
          roundId: 'source-round',
          boardNr: 1,
        ),
        _game(
          id: 'board-2',
          white: gamma,
          black: delta,
          slug: 'lower-round-1',
          roundId: 'source-round',
          boardNr: 2,
        ),
        _game(
          id: 'board-3',
          white: beta,
          black: alpha,
          slug: 'lower-round-1',
          roundId: 'source-round',
          boardNr: 3,
        ),
      ];

      expect(
        KnockoutMatchDetector.hasRepeatedMatchupInSingleSourceRound(
          isKnockoutTournament: true,
          games: games,
        ),
        isTrue,
      );
      expect(
        KnockoutMatchDetector.hasRepeatedMatchupInSingleSourceRound(
          isKnockoutTournament: false,
          games: games,
        ),
        isFalse,
        reason: 'ordinary tournament formats must retain board order',
      );
    });

    test('an open-ended head-to-head round shows newest boards first', () {
      // Dubov vs BulletGrandpa: one round, one pairing, colours alternating,
      // every new game appended with the next board number.
      final dubov = _player('Dubov, Daniil', fideId: 24126055);
      final smith = _player('Smith, Josh', fideId: 30962692);
      final games = [
        for (var board = 1; board <= 5; board++)
          _game(
            id: 'game-$board',
            white: board.isOdd ? dubov : smith,
            black: board.isOdd ? smith : dubov,
            slug: '100-game-finale',
            roundId: 'qndQxsJI',
            boardNr: board,
          ),
      ];

      expect(
        KnockoutMatchDetector.isSinglePairingAppendRound(games),
        isTrue,
      );
    });

    test('single-pairing detection ignores legs in separate rounds', () {
      final alpha = _player('Alpha', fideId: 11);
      final beta = _player('Beta', fideId: 22);
      final games = [
        _game(id: 'leg-1', white: alpha, black: beta, slug: 'game-1'),
        _game(id: 'leg-2', white: beta, black: alpha, slug: 'game-2'),
      ];

      expect(KnockoutMatchDetector.isSinglePairingAppendRound(games), isFalse);
    });

    test('a non-knockout round with several pairings keeps board order', () {
      final alpha = _player('Alpha', fideId: 11);
      final beta = _player('Beta', fideId: 22);
      final gamma = _player('Gamma', fideId: 33);
      final delta = _player('Delta', fideId: 44);
      final games = [
        _game(
          id: 'leg-1-board-1',
          white: alpha,
          black: beta,
          slug: 'round-1',
          boardNr: 1,
        ),
        _game(
          id: 'leg-1-board-2',
          white: gamma,
          black: delta,
          slug: 'round-1',
          boardNr: 2,
        ),
        _game(
          id: 'leg-2-board-1',
          white: beta,
          black: alpha,
          slug: 'round-1',
          boardNr: 3,
        ),
      ];

      expect(
        KnockoutMatchDetector.isSinglePairingAppendRound(games),
        isFalse,
      );
    });

    test(
      'does not treat legs from separate source rounds as appended boards',
      () {
        final alpha = _player('Alpha', fideId: 11);
        final beta = _player('Beta', fideId: 22);
        final games = [
          _game(
            id: 'leg-1',
            white: alpha,
            black: beta,
            slug: 'game-1',
            roundId: 'round-game-1',
          ),
          _game(
            id: 'leg-2',
            white: beta,
            black: alpha,
            slug: 'game-2',
            roundId: 'round-game-2',
          ),
        ];

        expect(
          KnockoutMatchDetector.hasRepeatedMatchupInSingleSourceRound(
            isKnockoutTournament: true,
            games: games,
          ),
          isFalse,
        );
      },
    );

    test('uses descending board number when timestamps and slugs tie', () {
      final alpha = _player('Alpha', fideId: 11);
      final beta = _player('Beta', fideId: 22);
      final syncedAt = DateTime.utc(2026, 8, 13, 12, 12);
      final ordered = KnockoutMatchDetector.orderMatchGamesLatestFirst([
        _game(
          id: 'z-older',
          white: alpha,
          black: beta,
          slug: 'lower-round-1',
          boardNr: 1,
          lastMoveTime: syncedAt,
        ),
        _game(
          id: 'a-newer',
          white: beta,
          black: alpha,
          slug: 'lower-round-1',
          boardNr: 3,
          lastMoveTime: syncedAt,
        ),
      ]);

      expect(ordered.map((game) => game.gameId), ['a-newer', 'z-older']);
    });

    // Total Chess World Championship Tour Pilot 2026, Semifinals (qEXour3L)
    // on 2026-11-17: Games 1-14 published on day one as 0-move `*` boards,
    // one per round. Games 1-4 played, Game 5 in play.
    test('live game, then finished newest first, then future games in '
        'order', () {
      final giri = _player('Giri, Anish', fideId: 24116068);
      final mvl = _player('Vachier-Lagrave, Maxime', fideId: 623539);
      final day = DateTime.utc(2026, 11, 17, 14);
      final games = [
        for (var n = 14; n >= 1; n--)
          _game(
            id: 'g$n',
            white: n.isOdd ? giri : mvl,
            black: n.isOdd ? mvl : giri,
            slug: 'game-$n',
            boardNr: 1,
            status: n <= 4 ? GameStatus.draw : GameStatus.ongoing,
            lastMove: n <= 5 ? 'e2e4' : null,
            lastMoveTime: n <= 5 ? day.add(Duration(minutes: 20 * n)) : null,
          ),
      ];

      final ordered = KnockoutMatchDetector.orderMatchGamesLatestFirst(games);

      expect(ordered.map((game) => game.gameId), [
        'g5',
        'g4',
        'g3',
        'g2',
        'g1',
        for (var n = 6; n <= 14; n++) 'g$n',
      ]);
    });
  });

  // Speed Chess Championship XI, Round of 16 (round 60IswAYI): all eight
  // matches in one round file, game 1 of each created up front as a 0-move
  // shell, then game 2, ... `board_nr` follows the file and is renumbered.
  group('match-play rounds', () {
    final nakamura = _player('Nakamura, Hikaru', fideId: 2016192);
    final erdogmus = _player('Erdogmus, Yagiz Kaan', fideId: 44599790);
    final carlsen = _player('Carlsen, Magnus', fideId: 1503014);
    final movahed = _player('Movahed, Sina', fideId: 42520835);

    test('a repeated pairing inside one knockout source round is match '
        'play', () {
      final games = [
        _game(
          id: 'g1',
          white: nakamura,
          black: erdogmus,
          slug: 'round-of-16',
          roundId: '60IswAYI',
          boardNr: 1,
        ),
        _game(
          id: 'c1',
          white: carlsen,
          black: movahed,
          slug: 'round-of-16',
          roundId: '60IswAYI',
          boardNr: 2,
        ),
        _game(
          id: 'g2',
          white: erdogmus,
          black: nakamura,
          slug: 'round-of-16',
          roundId: '60IswAYI',
          boardNr: 3,
        ),
      ];

      expect(
        KnockoutMatchDetector.isMatchPlayRound(
          isKnockoutTournament: true,
          games: games,
        ),
        isTrue,
      );
      expect(
        KnockoutMatchDetector.isMatchPlayRound(
          isKnockoutTournament: false,
          games: games,
        ),
        isFalse,
        reason: 'only knockout events are match play',
      );
    });

    test('legs in separate source rounds are not match play', () {
      // World Cup shape: game 1 and game 2 are rounds of their own.
      final games = [
        _game(
          id: 'leg-1',
          white: nakamura,
          black: erdogmus,
          slug: 'game-1',
          roundId: 'round-game-1',
        ),
        _game(
          id: 'leg-2',
          white: erdogmus,
          black: nakamura,
          slug: 'game-2',
          roundId: 'round-game-2',
        ),
        _game(
          id: 'other',
          white: carlsen,
          black: movahed,
          slug: 'game-1',
          roundId: 'round-game-1',
        ),
      ];

      expect(
        KnockoutMatchDetector.isMatchPlayRound(
          isKnockoutTournament: true,
          games: games,
        ),
        isFalse,
      );
    });

    test('reads the game index from the PGN Round tag only', () {
      expect(
        KnockoutMatchDetector.matchPlayGameIndexFromPgn(
          _pgn(round: '01.02', board: '7'),
        ),
        (stage: 1, set: 0, game: 2),
      );
      expect(
        KnockoutMatchDetector.matchPlayGameIndexFromPgn(_pgn(round: '1.2.3')),
        (stage: 1, set: 2, game: 3),
      );
      // A junk Board tag never stands in for the game index.
      expect(
        KnockoutMatchDetector.matchPlayGameIndexFromPgn(
          _pgn(round: '?', board: '3'),
        ),
        isNull,
      );
      expect(
        KnockoutMatchDetector.matchPlayGameIndexFromPgn(_pgn(round: '4')),
        isNull,
      );
      expect(KnockoutMatchDetector.matchPlayGameIndexFromPgn(null), isNull);
    });

    test('game index decides chronology over renumbered boards', () {
      final ordered = KnockoutMatchDetector.orderMatchPlayGamesChronologically([
        _game(
          id: 'game-2',
          white: erdogmus,
          black: nakamura,
          slug: 'r16',
          boardNr: 13,
          pgn: _pgn(round: '01.02'),
        ),
        // Inserted mid-file: the newest game holds the lowest board number.
        _game(
          id: 'game-3',
          white: nakamura,
          black: erdogmus,
          slug: 'r16',
          boardNr: 2,
          status: GameStatus.ongoing,
          pgn: _pgn(round: '01.03'),
        ),
        _game(
          id: 'game-1',
          white: nakamura,
          black: erdogmus,
          slug: 'r16',
          boardNr: 1,
          pgn: _pgn(round: '01.01'),
        ),
      ]);

      expect(ordered.map((game) => game.gameId), [
        'game-1',
        'game-2',
        'game-3',
      ]);
    });

    test('deferred PGNs fall back to finished, live, then unplayed', () {
      // Lean rows carry no PGN for rated finished games.
      final ordered = KnockoutMatchDetector.orderMatchPlayGamesChronologically([
        _game(
          id: 'shell-4',
          white: erdogmus,
          black: nakamura,
          slug: 'r16',
          boardNr: 1,
          status: GameStatus.ongoing,
          pgn: _pgn(round: '01.04'),
        ),
        _game(
          id: 'live-3',
          white: nakamura,
          black: erdogmus,
          slug: 'r16',
          boardNr: 2,
          status: GameStatus.ongoing,
          lastMove: 'e2e4',
          pgn: _pgn(round: '01.03'),
        ),
        _game(
          id: 'finished-2',
          white: erdogmus,
          black: nakamura,
          slug: 'r16',
          boardNr: 3,
          lastMove: 'h7h6',
          lastMoveTime: DateTime.utc(2026, 11, 16, 17, 31),
        ),
        _game(
          id: 'finished-1',
          white: nakamura,
          black: erdogmus,
          slug: 'r16',
          boardNr: 4,
          lastMove: 'a7a6',
          lastMoveTime: DateTime.utc(2026, 11, 16, 17, 12),
        ),
      ]);

      expect(ordered.map((game) => game.gameId), [
        'finished-1',
        'finished-2',
        'live-3',
        'shell-4',
      ]);
      expect(
        KnockoutMatchDetector.orderMatchPlayGamesForDisplay(
          ordered,
        ).map((game) => game.gameId),
        ['live-3', 'finished-2', 'finished-1', 'shell-4'],
      );
      // Side A is game 1's White on every board, matched by FIDE id.
      expect(KnockoutMatchDetector.matchPlayAnchorIsWhiteByGameId(ordered), {
        'finished-1': true,
        'finished-2': false,
        'live-3': true,
        'shell-4': false,
      });
    });

    // Dutch Championship 2026 Round 2, Ernst-Vrolijk: Lichess writes the
    // [Round] tag as round.board, so '9.1' is not game 1 of anything. The
    // PGN of a decisive game is deferred once it finishes, which used to
    // move side A from Vrolijk (while 9.1 was live) to Ernst (after it).
    test('round.board tags never decide the first game', () {
      final ernst = _player('Ernst, Sipke', fideId: 1004441);
      final vrolijk = _player('Vrolijk, Liam', fideId: 1052098);
      GamesTourModel dutch(
        String id,
        PlayerCard white,
        PlayerCard black,
        String round,
        int hour, {
        GameStatus status = GameStatus.draw,
        bool deferPgn = false,
        bool started = true,
      }) => _game(
        id: id,
        white: white,
        black: black,
        slug: 'round-2',
        roundId: 'round-2-$id',
        boardNr: 1,
        status: status,
        lastMove: started ? 'e2e4' : null,
        lastMoveTime: DateTime.utc(2026, 6, 1, hour),
        pgn: deferPgn ? null : _pgn(round: round),
      );

      List<GamesTourModel> match({required bool nineOneFinished}) => [
        dutch('syQvO72u', ernst, vrolijk, '5.3', 10),
        dutch('WNOSSeFS', vrolijk, ernst, '6.3', 11),
        dutch('Z9hQhA6C', ernst, vrolijk, '7.3', 12),
        dutch('VdexMasW', vrolijk, ernst, '8.3', 13),
        dutch(
          'fE5ksz62',
          vrolijk,
          ernst,
          '9.1',
          14,
          status: nineOneFinished ? GameStatus.whiteWins : GameStatus.ongoing,
          deferPgn: nineOneFinished,
        ),
        dutch(
          'KluT2RO4',
          ernst,
          vrolijk,
          '10.1',
          15,
          status: GameStatus.ongoing,
          started: false,
        ),
      ];

      for (final nineOneFinished in [false, true]) {
        final ordered =
            KnockoutMatchDetector.orderMatchPlayGamesChronologically(
              match(nineOneFinished: nineOneFinished),
            );
        expect(
          ordered.first.gameId,
          'syQvO72u',
          reason: '9.1 finished: $nineOneFinished',
        );
        expect(
          KnockoutMatchDetector.matchPlayAnchorIsWhiteByGameId(
            ordered,
          )['fE5ksz62'],
          isFalse,
          reason: 'Ernst stays side A; Vrolijk has White in 9.1',
        );
      }
    });

    test('an index claiming one game twice is not trusted', () {
      final ordered = KnockoutMatchDetector.orderMatchPlayGamesChronologically([
        _game(
          id: 'b',
          white: erdogmus,
          black: nakamura,
          slug: 'r16',
          boardNr: 1,
          lastMove: 'e2e4',
          lastMoveTime: DateTime.utc(2026, 11, 16, 17, 30),
          pgn: _pgn(round: '01.01'),
        ),
        _game(
          id: 'a',
          white: nakamura,
          black: erdogmus,
          slug: 'r16',
          boardNr: 2,
          lastMove: 'e2e4',
          lastMoveTime: DateTime.utc(2026, 11, 16, 17),
          pgn: _pgn(round: '01.01'),
        ),
      ]);

      // Both claim game 1: fall back to play time.
      expect(ordered.map((game) => game.gameId), ['a', 'b']);
    });

    group('which matches are match play', () {
      GamesTourModel leg(
        String id,
        PlayerCard white,
        PlayerCard black,
        String roundId,
      ) => _game(
        id: id,
        white: white,
        black: black,
        slug: roundId,
        roundId: roundId,
      );
      final so = _player('So, Wesley', fideId: 5202213);
      final pragg = _player('Praggnanandhaa R', fideId: 25059530);

      test('every match of a shared round file, shells included', () {
        // Only Nakamura-Erdogmus has a second game so far.
        final keys = KnockoutMatchDetector.matchPlayMatchKeys(
          isKnockoutTournament: true,
          games: [
            leg('g1', nakamura, erdogmus, '60IswAYI'),
            leg('c1', carlsen, movahed, '60IswAYI'),
            leg('s1', so, pragg, '60IswAYI'),
            leg('g2', erdogmus, nakamura, '60IswAYI'),
          ],
        );
        expect(keys, hasLength(3));
      });

      test('a round per match (Women\'s Speed Chess Championship)', () {
        final keys = KnockoutMatchDetector.matchPlayMatchKeys(
          isKnockoutTournament: true,
          games: [
            leg('a1', nakamura, erdogmus, 'match-a'),
            leg('a2', erdogmus, nakamura, 'match-a'),
            leg('b1', carlsen, movahed, 'match-b'),
            leg('b2', movahed, carlsen, 'match-b'),
          ],
        );
        expect(keys, hasLength(2));
        expect(
          KnockoutMatchDetector.singleMatchSourceRoundIds([
            leg('a1', nakamura, erdogmus, 'match-a'),
            leg('b1', carlsen, movahed, 'match-b'),
            leg('c1', so, pragg, 'shared'),
            leg('d1', erdogmus, movahed, 'shared'),
          ]),
          {'match-a', 'match-b'},
        );
      });

      test('a tiebreak round shared by one pairing changes no match', () {
        // Dutch Championship 2026 Open, Round 4: classical legs in rounds of
        // their own, the rapid tiebreak games of one pairing in one round.
        final keys = KnockoutMatchDetector.matchPlayMatchKeys(
          isKnockoutTournament: true,
          games: [
            leg('p1', nakamura, erdogmus, 'r41'),
            leg('q1', carlsen, movahed, 'r41'),
            leg('p2', erdogmus, nakamura, 'r42'),
            leg('q2', movahed, carlsen, 'r42'),
            leg('p3', nakamura, erdogmus, 'r4tb'),
            leg('p4', erdogmus, nakamura, 'r4tb'),
          ],
        );
        expect(keys, isEmpty);
        expect(
          KnockoutMatchDetector.isMatchPlayRound(
            isKnockoutTournament: true,
            games: [
              leg('p3', nakamura, erdogmus, 'r4tb'),
              leg('p4', erdogmus, nakamura, 'r4tb'),
            ],
          ),
          isTrue,
        );
      });
    });

    test('two live matches keep their bracket order on every move', () {
      // Dec 16: Carlsen-Movahed and Caruana-Sindarov at 1+1 at once.
      final caruana = _player('Caruana, Fabiano', fideId: 2020009);
      final sindarov = _player('Sindarov, Javokhir', fideId: 14205483);
      Map<String, List<GamesTourModel>> matches(DateTime carlsenMove) => {
        'caruana': [
          _game(
            id: 'cs1',
            white: caruana,
            black: sindarov,
            slug: 'r16',
            boardNr: 6,
            status: GameStatus.ongoing,
            lastMove: 'e2e4',
            lastMoveTime: DateTime.utc(2026, 12, 16, 18, 0, 30),
          ),
        ],
        'carlsen': [
          _game(
            id: 'cm1',
            white: carlsen,
            black: movahed,
            slug: 'r16',
            boardNr: 2,
            status: GameStatus.ongoing,
            lastMove: 'e2e4',
            lastMoveTime: carlsenMove,
          ),
        ],
      };

      for (final carlsenMove in [
        DateTime.utc(2026, 12, 16, 18),
        DateTime.utc(2026, 12, 16, 18, 1),
      ]) {
        expect(
          KnockoutMatchDetector.orderMatchPlayMatches(
            matches(carlsenMove),
          ).keys,
          ['carlsen', 'caruana'],
        );
      }
    });

    test('a round of its own dates a played match, a shared one never', () {
      // Bulk-imported finished games carry only their game day.
      final played = _game(
        id: 'hou-1',
        white: carlsen,
        black: movahed,
        slug: 'r16',
        roundId: 'aaMB3ZxC',
        lastMove: 'e2e4',
        lastMoveTime: DateTime.utc(2026, 7, 13),
      );
      final shell = _game(
        id: 'next-1',
        white: nakamura,
        black: erdogmus,
        slug: 'r16',
        roundId: 'next',
        status: GameStatus.ongoing,
        lastMoveTime: DateTime.utc(2026, 7, 14),
      );
      final starts = {
        'aaMB3ZxC': DateTime.utc(2026, 7, 13, 12),
        'next': DateTime.utc(2026, 7, 14, 12),
      };

      expect(
        KnockoutMatchDetector.matchPlayRecency([
          played,
        ], ownRoundStartsById: starts),
        DateTime.utc(2026, 7, 13, 12),
      );
      expect(
        KnockoutMatchDetector.matchPlayRecency([played]),
        DateTime.utc(2026, 7, 13),
      );
      expect(
        KnockoutMatchDetector.matchPlayRecency([
          shell,
        ], ownRoundStartsById: starts),
        isNull,
      );
    });

    test('a 0-move shell is neither live nor a played time', () {
      final shell = _game(
        id: 'shell',
        white: carlsen,
        black: movahed,
        slug: 'r16',
        status: GameStatus.ongoing,
        lastMoveTime: DateTime.utc(2026, 11, 16),
      );
      final live = _game(
        id: 'live',
        white: erdogmus,
        black: nakamura,
        slug: 'r16',
        status: GameStatus.ongoing,
        lastMove: 'e2e4',
        lastMoveTime: DateTime.utc(2026, 11, 16, 17, 20),
      );

      expect(KnockoutMatchDetector.isMatchPlayGameLive(shell), isFalse);
      expect(KnockoutMatchDetector.isMatchPlayGameLive(live), isTrue);
      expect(KnockoutMatchDetector.matchPlayRecency([shell]), isNull);
      expect(
        KnockoutMatchDetector.matchPlayRecency([shell, live]),
        DateTime.utc(2026, 11, 16, 17, 20),
      );
    });
  });
}

String _pgn({required String round, String? board}) => [
  '[Event "Speed Chess Championship 2026"]',
  '[Round "$round"]',
  if (board != null) '[Board "$board"]',
  '[White "A"]',
  '[Black "B"]',
  '',
  '*',
].join('\n');

GamesTourModel _game({
  required String id,
  required PlayerCard white,
  required PlayerCard black,
  required String slug,
  String? roundId,
  int? boardNr,
  DateTime? lastMoveTime,
  GameStatus status = GameStatus.draw,
  String? lastMove,
  String? pgn,
}) => GamesTourModel(
  gameId: id,
  whitePlayer: white,
  blackPlayer: black,
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  // Clocks stay positive so a live game is never read as lost on time.
  whiteClockSeconds: lastMove == null ? null : 300,
  blackClockSeconds: lastMove == null ? null : 300,
  gameStatus: status,
  roundId: roundId ?? slug,
  roundSlug: slug,
  tourId: 'tour',
  boardNr: boardNr,
  lastMoveTime: lastMoveTime,
  lastMove: lastMove,
  pgn: pgn,
);

PlayerCard _player(String name, {int? fideId}) => PlayerCard(
  name: name,
  federation: 'FIDE',
  title: '',
  rating: 2500,
  countryCode: 'FIDE',
  team: null,
  fideId: fideId,
);
