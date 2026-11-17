import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_display_rounds.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_flattened_layout.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selectGamesTourDisplayRounds', () {
    // Team events render this same list (European Club Cup 2026-10-20: the
    // live round stayed hidden until its first move).
    test('leads with a live round whose boards have no moves yet', () {
      final now = DateTime(2026, 10, 20, 15);
      final played = _round(
        'r3',
        RoundStatus.completed,
        startsAt: now.subtract(const Duration(days: 1)),
      );
      final live = _round(
        'r4',
        RoundStatus.live,
        startsAt: now.subtract(const Duration(minutes: 5)),
      );

      final visible = selectGamesTourDisplayRounds(
        rounds: [played, live],
        effectiveRounds: [played, live],
        gamesByRound: {
          played.id: [_game('finished', status: GameStatus.draw)],
          live.id: [_game('waiting-board')],
        },
        upcomingPairingRoundIds: {live.id},
        isSearchMode: false,
        isMultiStageKnockout: false,
        now: now,
      );

      expect(visible.map((round) => round.id), ['r4', 'r3']);
    });

    test('puts a populated synthetic semifinal above quarterfinals', () {
      final now = DateTime(2026, 8, 13, 19, 31);
      final quarterfinals = _round(
        'knockout-stage-quarterfinals',
        RoundStatus.completed,
        startsAt: DateTime(2026, 8, 10, 22),
      );
      final semifinals = _round(
        'knockout-stage-semifinals',
        RoundStatus.upcoming,
        startsAt: DateTime(2026, 8, 13, 22, 3),
      );

      final visible = selectGamesTourDisplayRounds(
        rounds: [semifinals, quarterfinals],
        effectiveRounds: [semifinals, quarterfinals],
        gamesByRound: {
          quarterfinals.id: [_game('qf-1')],
          semifinals.id: [_game('sf-1')],
        },
        upcomingPairingRoundIds: const {},
        isSearchMode: false,
        isMultiStageKnockout: true,
        now: now,
      );

      expect(visible.map((round) => round.id), [
        semifinals.id,
        quarterfinals.id,
      ]);
    });

    test('promotes the next ready pairing at the two-hour boundary', () {
      final now = DateTime(2026, 7, 13, 12);
      final round1 = _round(
        'r1',
        RoundStatus.completed,
        startsAt: now.subtract(const Duration(hours: 4)),
      );
      final round2 = _round(
        'r2',
        RoundStatus.completed,
        startsAt: now.subtract(const Duration(hours: 2)),
      );
      final round3 = _round(
        'r3',
        RoundStatus.upcoming,
        startsAt: now.add(const Duration(hours: 2)),
      );
      final round4 = _round(
        'r4',
        RoundStatus.upcoming,
        startsAt: now.add(const Duration(hours: 3)),
      );

      final visible = selectGamesTourDisplayRounds(
        rounds: [round4, round2, round3, round1],
        effectiveRounds: [round4, round2, round3, round1],
        gamesByRound: {
          round1.id: [_game('finished-1', status: GameStatus.draw)],
          round2.id: [_game('finished-2', status: GameStatus.draw)],
          round3.id: [_game('pairing-3')],
          round4.id: [_game('pairing-4')],
        },
        upcomingPairingRoundIds: {round3.id, round4.id},
        isSearchMode: false,
        isMultiStageKnockout: false,
        now: now,
      );

      expect(visible.map((round) => round.id), ['r3', 'r2', 'r1', 'r4']);
    });

    test('does not promote an upcoming round before its boards are ready', () {
      final now = DateTime(2026, 7, 13, 12);
      final completed = _round(
        'r1',
        RoundStatus.completed,
        startsAt: now.subtract(const Duration(hours: 2)),
      );
      final awaitingBoards = _round(
        'r2',
        RoundStatus.upcoming,
        startsAt: now.add(const Duration(minutes: 90)),
      );

      final visible = selectGamesTourDisplayRounds(
        rounds: [awaitingBoards, completed],
        effectiveRounds: [awaitingBoards, completed],
        gamesByRound: {
          completed.id: [_game('finished', status: GameStatus.draw)],
          awaitingBoards.id: const <GamesTourModel>[],
        },
        upcomingPairingRoundIds: {awaitingBoards.id},
        isSearchMode: false,
        isMultiStageKnockout: false,
        now: now,
      );

      expect(visible.map((round) => round.id), ['r1', 'r2']);
    });

    test('keeps future pairings last while a played round is unfinished', () {
      final now = DateTime(2026, 7, 13, 12);
      final completed = _round(
        'r1',
        RoundStatus.completed,
        startsAt: now.subtract(const Duration(hours: 4)),
      );
      final ongoing = _round(
        'r2',
        RoundStatus.ongoing,
        startsAt: now.subtract(const Duration(hours: 2)),
      );
      final next = _round(
        'r3',
        RoundStatus.upcoming,
        startsAt: now.add(const Duration(minutes: 30)),
      );
      final later = _round(
        'r4',
        RoundStatus.upcoming,
        startsAt: now.add(const Duration(hours: 2)),
      );

      final visible = selectGamesTourDisplayRounds(
        rounds: [next, completed, later, ongoing],
        effectiveRounds: [next, completed, later, ongoing],
        gamesByRound: {
          completed.id: [_game('finished', status: GameStatus.draw)],
          ongoing.id: [_game('ongoing')],
          next.id: [_game('pairing-next')],
          later.id: [_game('pairing-later')],
        },
        upcomingPairingRoundIds: {next.id, later.id},
        isSearchMode: false,
        isMultiStageKnockout: false,
        now: now,
      );

      expect(visible.map((round) => round.id), ['r2', 'r1', 'r3', 'r4']);
    });
  });

  group('buildGamesTourFlattenedLayout', () {
    test('reversed-color legs produce one canonical match header', () {
      final round = _round('knockout-stage-quarterfinals', RoundStatus.live);
      final games = [
        _game(
          'leg-1',
          slug: 'game-1',
          lastMoveTime: DateTime.utc(2026, 7, 15, 14),
        ),
        _game(
          'leg-2',
          reverseColors: true,
          slug: 'game-2',
          lastMoveTime: DateTime.utc(2026, 7, 15, 15),
        ),
      ];

      final layout = _layout(rounds: [round], gamesByRound: {round.id: games});

      expect(
        layout.entries.whereType<GamesTourMatchHeaderEntry>(),
        hasLength(1),
      );
      // Boards render latest-first inside the matchup: leg 2 above leg 1.
      expect(layout.itemIndexForGameId('leg-2'), 2);
      expect(layout.itemIndexForGameId('leg-1'), 3);
    });

    test('collapsed round and match shift the next header exactly', () {
      final first = _round(
        'knockout-stage-quarterfinals',
        RoundStatus.completed,
      );
      final second = _round('knockout-stage-semifinals', RoundStatus.live);
      final gamesByRound = {
        first.id: [
          _game('qf-1', slug: 'game-1'),
          _game('qf-2', reverseColors: true, slug: 'game-2'),
        ],
        second.id: [
          _game('sf-1', slug: 'game-1', identityOffset: 100),
          _game(
            'sf-2',
            reverseColors: true,
            slug: 'game-2',
            identityOffset: 100,
          ),
        ],
      };

      final collapsedRound = _layout(
        rounds: [first, second],
        gamesByRound: gamesByRound,
        roundExpansionState: {first.id: false},
      );
      expect(collapsedRound.roundHeaderIndex(first.id), 0);
      expect(collapsedRound.roundHeaderIndex(second.id), 1);
      expect(collapsedRound.itemIndexForGameId('qf-1'), isNull);

      final firstMatchKey =
          _layout(
            rounds: [first],
            gamesByRound: {first.id: gamesByRound[first.id]!},
          ).matchGroupsByRound[first.id]!.keys.single;
      final collapsedMatch = _layout(
        rounds: [first, second],
        gamesByRound: gamesByRound,
        matchExpansionState: {firstMatchKey: false},
      );
      expect(collapsedMatch.roundHeaderIndex(second.id), 2);
      expect(collapsedMatch.itemIndexForGameId('qf-1'), isNull);
      expect(collapsedMatch.itemIndexForGameId('sf-1'), isNotNull);
    });

    test('collapsed knockout matchups render latest-first by round start', () {
      final stage = _round('knockout-stage-round-of-16', RoundStatus.completed);
      // Eight-matchup RO16 collapsed into one stage. Two matchups share each
      // calendar day, so ordering must fall back to the round start TIME, which
      // the date-granular game rows cannot supply.
      final games = [
        _game('ju', identityOffset: 0, roundId: 'r-ju'), // 07-06 14:00
        _game(
          'vaishali',
          identityOffset: 100,
          roundId: 'r-vaishali',
        ), // 07-06 16:30
        _game('hou', identityOffset: 200, roundId: 'r-hou'), // 07-13 12:00
        _game(
          'polina',
          identityOffset: 300,
          roundId: 'r-polina',
        ), // 07-13 14:30
      ];

      final layout = _layout(
        rounds: [stage],
        gamesByRound: {stage.id: games},
        roundStartTimesById: {
          'r-ju': DateTime.utc(2026, 7, 6, 14, 0),
          'r-vaishali': DateTime.utc(2026, 7, 6, 16, 30),
          'r-hou': DateTime.utc(2026, 7, 13, 12, 0),
          'r-polina': DateTime.utc(2026, 7, 13, 14, 30),
        },
      );

      final matchupOrder =
          layout.entries
              .whereType<GamesTourGameRowEntry>()
              .map((entry) => entry.game1.gameId)
              .toList();

      // Descending datetime: latest day first, same-day tie broken by time.
      expect(matchupOrder, ['polina', 'hou', 'vaishali', 'ju']);

      // Every matchup card carries the exact datetime the sort used, so the
      // rendered order is verifiable at a glance.
      final playedAts =
          layout.entries
              .whereType<GamesTourMatchHeaderEntry>()
              .map((entry) => entry.matchHeader.playedAt)
              .toList();
      expect(playedAts, [
        DateTime.utc(2026, 7, 13, 14, 30),
        DateTime.utc(2026, 7, 13, 12, 0),
        DateTime.utc(2026, 7, 6, 16, 30),
        DateTime.utc(2026, 7, 6, 14, 0),
      ]);
    });

    test('actual play time outranks a stale scheduled start', () {
      final stage = _round('knockout-stage-round-of-16', RoundStatus.completed);
      // The "postponed matchup" shape: scheduled for the earlier slot but
      // actually streamed a day later, while the broadcast's starts_at was
      // never corrected. The live-streamed lastMoveTime must win.
      final games = [
        _game(
          'postponed',
          identityOffset: 0,
          roundId: 'r-postponed',
          lastMoveTime: DateTime.utc(2026, 7, 11, 20, 14),
        ),
        _game('on-schedule', identityOffset: 100, roundId: 'r-on-schedule'),
      ];

      final layout = _layout(
        rounds: [stage],
        gamesByRound: {stage.id: games},
        roundStartTimesById: {
          'r-postponed': DateTime.utc(2026, 7, 10, 14, 0),
          'r-on-schedule': DateTime.utc(2026, 7, 10, 16, 30),
        },
      );

      final matchupOrder =
          layout.entries
              .whereType<GamesTourGameRowEntry>()
              .map((entry) => entry.game1.gameId)
              .toList();

      expect(matchupOrder, ['postponed', 'on-schedule']);
    });

    test('focus-on-live mode keeps finished boards visible in the grid', () {
      final round = _round('knockout-stage-finals', RoundStatus.live);
      final games = [
        _game(
          'live-1',
          slug: 'game-1',
          lastMoveTime: DateTime.utc(2026, 7, 15, 14),
        ),
        _game(
          'live-2',
          reverseColors: true,
          slug: 'game-2',
          lastMoveTime: DateTime.utc(2026, 7, 15, 15),
        ),
        _game('finished', slug: 'tiebreak-1-rapid-1', status: GameStatus.draw),
      ];

      final layout = _layout(
        rounds: [round],
        gamesByRound: {round.id: games},
        mode: GamesListViewMode.chessBoardGrid,
        // hideFinishedGames is the Focus-on-live mode: sort-only, no filter.
        displayMode: GameDisplayMode.hideFinishedGames,
      );

      expect(layout.itemIndexForGameId('live-1'), 2);
      expect(layout.itemIndexForGameId('live-2'), 2);
      // Latest-first inside the matchup: game 2 leads the row.
      expect(layout.firstGameIdAt(2), 'live-2');
      // Finished board stays in the layout (focus mode no longer filters).
      expect(layout.itemIndexForGameId('finished'), isNotNull);
      expect(layout.itemCount, greaterThanOrEqualTo(3));
    });

    test(
      'live board floats above boards that finished after its last move',
      () {
        final stage = _round('knockout-stage-semifinals', RoundStatus.live);
        // Matchup-labeled feed (speed-championship shape): every game of the
        // matchup shares one round slug, so slug order ties everywhere and only
        // status plus actual play time can rank the boards. The live board must
        // hold the top even while other boards finish after its last move.
        final games = [
          _game(
            'finished-late',
            slug: 'semifinals',
            status: GameStatus.whiteWins,
            lastMoveTime: DateTime.utc(2026, 7, 15, 20, 0),
          ),
          _game(
            'live',
            slug: 'semifinals',
            // A board being played has a move; a 0-move shell is not live.
            lastMove: 'e2e4',
            lastMoveTime: DateTime.utc(2026, 7, 15, 19, 30),
          ),
          _game(
            'finished-early',
            slug: 'semifinals',
            status: GameStatus.draw,
            lastMoveTime: DateTime.utc(2026, 7, 15, 18, 0),
          ),
        ];

        final layout = _layout(
          rounds: [stage],
          gamesByRound: {stage.id: games},
        );

        final boardOrder =
            layout.entries
                .whereType<GamesTourGameRowEntry>()
                .map((entry) => entry.game1.gameId)
                .toList();
        expect(boardOrder, ['live', 'finished-late', 'finished-early']);
      },
    );

    test('matchup with a live board outranks matchups that finished later', () {
      final stage = _round('knockout-stage-semifinals', RoundStatus.live);
      final games = [
        _game(
          'finished',
          identityOffset: 0,
          roundId: 'r-finished',
          status: GameStatus.blackWins,
          lastMoveTime: DateTime.utc(2026, 7, 15, 20, 0),
        ),
        _game(
          'live',
          identityOffset: 100,
          roundId: 'r-live',
          lastMoveTime: DateTime.utc(2026, 7, 15, 19, 30),
        ),
      ];

      final layout = _layout(rounds: [stage], gamesByRound: {stage.id: games});

      final matchupOrder =
          layout.entries
              .whereType<GamesTourGameRowEntry>()
              .map((entry) => entry.game1.gameId)
              .toList();
      expect(matchupOrder, ['live', 'finished']);
    });

    // Total Chess semifinals between Game 5 and Game 6: every match plays one
    // board in each "Game N" round. The match that finished last
    // (Mishra-Vaishali, a lower board) jumped to the top.
    test('matches played side by side keep board order between games', () {
      final stage = _round('knockout-stage-semifinals', RoundStatus.live);
      final day = DateTime.utc(2026, 11, 17, 14);
      final games = [
        for (final (offset, board, finishedAt) in [
          (0, 1, day.add(const Duration(minutes: 30))),
          (100, 2, day.add(const Duration(minutes: 50))),
        ])
          for (final n in [1, 2])
            _game(
              'b$board-g$n',
              slug: 'game-$n',
              roundId: 'r-game-$n',
              identityOffset: offset,
              boardNr: board,
              reverseColors: n.isEven,
              status: GameStatus.draw,
              lastMove: 'e2e4',
              lastMoveTime: finishedAt.add(Duration(hours: n)),
            ),
      ];

      final layout = _layout(rounds: [stage], gamesByRound: {stage.id: games});
      final headers = [
        for (final entry
            in layout.entries.whereType<GamesTourMatchHeaderEntry>())
          entry.matchHeader.player1,
      ];
      expect(headers, ['GM Alpha Player 0', 'GM Alpha Player 100']);
    });

    test('matches played side by side keep board order while one is live', () {
      final stage = _round('knockout-stage-semifinals', RoundStatus.live);
      final day = DateTime.utc(2026, 11, 17, 16, 30);
      final games = [
        for (final (offset, board, live) in [(0, 1, false), (100, 2, true)])
          for (final n in [1, 2])
            _game(
              'b$board-g$n',
              slug: 'game-$n',
              roundId: 'r-game-$n',
              identityOffset: offset,
              boardNr: board,
              reverseColors: n.isEven,
              // Board 1 finished game 2 first; board 2 is still playing it.
              status: live && n == 2 ? GameStatus.ongoing : GameStatus.draw,
              lastMove: 'e2e4',
              lastMoveTime: day.add(Duration(hours: n, minutes: board)),
            ),
      ];

      final layout = _layout(rounds: [stage], gamesByRound: {stage.id: games});
      final headers = [
        for (final entry
            in layout.entries.whereType<GamesTourMatchHeaderEntry>())
          entry.matchHeader.player1,
      ];
      expect(headers, ['GM Alpha Player 0', 'GM Alpha Player 100']);
    });
  });

  // Production fixture: Speed Chess Championship XI, Round of 16, round
  // 60IswAYI of tour fqCjSUpE at 2026-11-16 ~17:20 UTC. Every match of the
  // stage is in one round file; game 1 of each match was created up front as
  // a 0-move shell, then game 2. Nakamura-Erdogmus is the only match played.
  group('match-play knockout (Speed Chess Championship)', () {
    const expectedSideA = [
      'Nakamura, Hikaru',
      'Carlsen, Magnus',
      'Abdusattorov, Nodirbek',
      'Nihal Sarin',
      'Firouzja, Alireza',
      'Caruana, Fabiano',
      'Lazavik, Denis',
      'So, Wesley',
    ];
    const expectedSideB = [
      'Erdogmus, Yagiz Kaan',
      'Movahed, Sina',
      'Keymer, Vincent',
      'Niemann, Hans Moke',
      'Artemiev, Vladislav',
      'Sindarov, Javokhir',
      'Andreikin, Dmitry',
      'Praggnanandhaa R',
    ];

    List<MatchHeaderModel> headersOf(GamesTourFlattenedLayout layout) => [
      for (final entry in layout.entries.whereType<GamesTourMatchHeaderEntry>())
        entry.matchHeader,
    ];

    /// The rows under the match header whose side A is [sideA].
    List<GamesTourGameRowEntry> rowsOf(
      GamesTourFlattenedLayout layout,
      String sideA,
    ) {
      final rows = <GamesTourGameRowEntry>[];
      var inMatch = false;
      for (final entry in layout.entries) {
        if (entry is GamesTourMatchHeaderEntry) {
          inMatch = entry.matchHeader.player1 == sideA;
        } else if (inMatch && entry is GamesTourGameRowEntry) {
          rows.add(entry);
        }
      }
      return rows;
    }

    test('eight matches, the live one first, then bracket order', () {
      // The grouped provider hands this round over newest board first.
      final layout = _sccLayout(_sccRoundOf16().reversed.toList());

      final headers = headersOf(layout);
      expect(headers.map((header) => header.player1), expectedSideA);
      expect(headers.map((header) => header.player2), expectedSideB);
      expect(headers.every((header) => header.isMatchPlay), isTrue);
      expect(layout.orderedGames, hasLength(16));
    });

    for (final mode in GamesListViewMode.values) {
      test('finished Nakamura-Erdogmus stays above future matches ($mode)', () {
        final layout = _sccLayout(
          _sccRoundOf16(nakamuraGame2: GameStatus.blackWins).reversed.toList(),
          mode: mode,
          matchSchedule: _sccSchedule,
          roundStartTimesById: {'60IswAYI': DateTime.utc(2026, 11, 16, 17)},
        );
        final headers = headersOf(layout);
        expect(headers.map((header) => header.player1), [
          'Nakamura, Hikaru',
          'Lazavik, Denis',
          'Firouzja, Alireza',
          'So, Wesley',
          'Carlsen, Magnus',
          'Caruana, Fabiano',
          'Abdusattorov, Nodirbek',
          'Nihal Sarin',
        ]);
        expect(headers.map((header) => header.playedAt), [
          DateTime.utc(2026, 11, 16, 17),
          DateTime.utc(2026, 11, 20, 17),
          DateTime.utc(2026, 11, 27, 17, 30),
          DateTime.utc(2026, 12, 9, 15),
          DateTime.utc(2026, 12, 16, 14),
          DateTime.utc(2026, 12, 16, 17, 30),
          null,
          null,
        ]);
        expect(headers.every((header) => !header.hasLiveGame), isTrue);
        expect(
          headers.first.playedAt,
          isNot(DateTime.utc(2026, 11, 16, 17, 31)),
          reason: 'the final move is not the match kickoff',
        );
      });
    }

    test(
      'the event model preserves the published schedule across cache reads',
      () {
        final info = TourInfo.fromJson({
          'matchSchedule': [..._sccSchedule, null, 7],
        });
        expect(info.matchSchedule, _sccSchedule);
        expect(TourInfo.fromJson(info.toJson()).matchSchedule, _sccSchedule);
        expect(
          TourInfo.fromJson({'matchSchedule': 'bad'}).matchSchedule,
          isEmpty,
        );
      },
    );

    test(
      'a wrong-stage, malformed or conflicting schedule invents no time',
      () {
        for (final schedule in [
          [
            {
              'roundId': 'other-stage',
              'fideIds': ['2016192', '44599790'],
              'startsAt': '2026-11-16T17:00:00Z',
            },
          ],
          [
            {
              'roundId': '60IswAYI',
              'fideIds': ['2016192', '44599790'],
              'startsAt': '2026-02-31T17:00:00Z',
            },
          ],
          [
            {
              'roundId': '60IswAYI',
              'fideIds': ['2016192', '44599790'],
              'startsAt': '2026-11-16T17:00:00',
            },
          ],
          [
            _sccSchedule.first,
            {..._sccSchedule.first, 'startsAt': '2026-11-16T18:00:00Z'},
          ],
        ]) {
          expect(
            headersOf(
              _sccLayout(_sccRoundOf16(), matchSchedule: schedule),
            ).first.playedAt,
            isNull,
          );
        }
      },
    );

    test('Nakamura keeps one side in both games of his match', () {
      final layout = _sccLayout(_sccRoundOf16().reversed.toList());

      final header = headersOf(layout).first;
      expect(header.player1, 'Nakamura, Hikaru');
      expect(header.player1Score, 0.5);
      expect(header.player2Score, 0.5);

      final rows = rowsOf(layout, 'Nakamura, Hikaru');
      // Live game 2 (board 12) above finished game 1 (board 1).
      expect(rows.map((row) => row.game1.gameId), [
        '60IswAYI-1md2dlh',
        '60IswAYI-pq36vc',
      ]);
      // Nakamura is Black in game 2 and White in game 1, yet he is side A
      // (left of the card, bottom of the board) in both rows.
      expect(rows.map((row) => row.anchorIsWhite1), [false, true]);
      expect(rows.map((row) => row.fixedBottomSide1), [Side.black, Side.white]);
    });

    test('a match that has not started is neither live nor timed', () {
      final layout = _sccLayout(
        _sccRoundOf16().reversed.toList(),
        // Every match shares the round's scheduled start; it must not be
        // printed as the time of matches that have not been played.
        roundStartTimesById: {'60IswAYI': DateTime.utc(2026, 11, 16, 17)},
      );

      final headers = headersOf(layout);
      expect(headers.first.hasLiveGame, isTrue);
      expect(headers.first.playedAt, isNull,
          reason: 'a latest-move stamp is not a known match kickoff');
      for (final header in headers.skip(1)) {
        expect(header.hasLiveGame, isFalse, reason: header.player1);
        expect(header.playedAt, isNull, reason: header.player1);
        expect(header.player1Score + header.player2Score, 0);
      }

      // Unplayed shells sit in game order: game 1, then game 2.
      final carlsen = rowsOf(layout, 'Carlsen, Magnus');
      expect(carlsen.map((row) => row.game1.gameId), [
        '60IswAYI-src7cv',
        '60IswAYI-1a45jh4',
      ]);
      expect(carlsen.map((row) => row.anchorIsWhite1), [true, false]);
    });

    test('the layout does not depend on the order games arrive in', () {
      final boardOrder = _sccLayout(_sccRoundOf16());
      final newestFirst = _sccLayout(_sccRoundOf16().reversed.toList());
      final interleaved = _sccLayout([
        for (var i = 0; i < 16; i += 2) _sccRoundOf16()[i],
        for (var i = 15; i > 0; i -= 2) _sccRoundOf16()[i],
      ]);

      final expected = _matchPlaySnapshot(boardOrder);
      expect(_matchPlaySnapshot(newestFirst), expected);
      expect(_matchPlaySnapshot(interleaved), expected);
    });

    for (final deferFinishedPgn in [true, false]) {
      test('game 3 inserted mid-file with a lower board keeps the anchor '
          '(finished PGNs ${deferFinishedPgn ? 'deferred' : 'loaded'})', () {
        // Game 2 ends (Erdogmus wins with White) and game 3 starts with
        // Nakamura White. Chess.com inserts it mid-file, so the ingest
        // renumbers it to board 2 and every later board moves down one.
        final games = <GamesTourModel>[
          for (final game in _sccRoundOf16(
            deferFinishedPgn: deferFinishedPgn,
            nakamuraGame2: GameStatus.whiteWins,
          ))
            game.boardNr! >= 2
                ? game.copyWith(boardNr: game.boardNr! + 1)
                : game,
          _sccGame(
            'new3',
            2,
            _nakamura,
            _erdogmus,
            '01.03',
            lastMove: 'c2c4',
            lastMoveTime: DateTime.utc(2026, 11, 16, 17, 40),
          ),
        ];

        final layout = _sccLayout(games.reversed.toList());

        final headers = headersOf(layout);
        expect(headers.map((header) => header.player1), expectedSideA);
        expect(headers.first.player1Score, 0.5);
        expect(headers.first.player2Score, 1.5);

        final rows = rowsOf(layout, 'Nakamura, Hikaru');
        expect(rows.map((row) => row.game1.gameId), [
          '60IswAYI-new3',
          '60IswAYI-1md2dlh',
          '60IswAYI-pq36vc',
        ]);
        expect(rows.map((row) => row.anchorIsWhite1), [true, false, true]);
      });
    }

    // Nakamura-Erdogmus at 2.5-1.5 after four games. A search hands the
    // layout only its hits (local search also stops at 50 per tour); the
    // match still reads side A and the score from the whole round.
    test('a search showing some games keeps side A and the full score', () {
      final stage = _round(
        'knockout-stage-fqCjSUpE-round-of-16',
        RoundStatus.live,
      );
      final round = <GamesTourModel>[
        _sccGame(
          'g1',
          1,
          _nakamura,
          _erdogmus,
          '01.01',
          status: GameStatus.draw,
          lastMove: 'g8f6',
          lastMoveTime: DateTime.utc(2026, 11, 16, 17, 5),
        ),
        _sccGame('src7cv', 2, _carlsen, _movahed, '01.01'),
        _sccGame(
          'g2',
          3,
          _erdogmus,
          _nakamura,
          '01.02',
          status: GameStatus.whiteWins,
          lastMove: 'h2h3',
          lastMoveTime: DateTime.utc(2026, 11, 16, 17, 31),
        ),
        _sccGame(
          'g3',
          4,
          _nakamura,
          _erdogmus,
          '01.03',
          status: GameStatus.whiteWins,
          lastMove: 'c2c4',
          lastMoveTime: DateTime.utc(2026, 11, 16, 17, 50),
        ),
        _sccGame(
          'g4',
          5,
          _erdogmus,
          _nakamura,
          '01.04',
          status: GameStatus.blackWins,
          lastMove: 'd7d5',
          lastMoveTime: DateTime.utc(2026, 11, 16, 18, 10),
        ),
        _sccGame('1a45jh4', 6, _movahed, _carlsen, '01.02'),
      ];
      GamesTourFlattenedLayout search(List<String> hitIds) => _layout(
        rounds: [stage],
        gamesByRound: {
          stage.id: [
            for (final game in round)
              if (hitIds.contains(game.gameId.split('-').last)) game,
          ],
        },
        isSearchMode: true,
        fullGamesByRound: {stage.id: round},
      );

      // Only Erdogmus's White games match (an opening he plays as White).
      final asWhite = search(['g2', 'g4']);
      final header = headersOf(asWhite).single;
      expect(header.player1, 'Nakamura, Hikaru');
      expect(header.player1Score, 2.5);
      expect(header.player2Score, 1.5);
      expect(header.isMatchPlay, isTrue);
      final rows = asWhite.entries.whereType<GamesTourGameRowEntry>();
      expect(rows.map((row) => row.game1.gameId), [
        '60IswAYI-g4',
        '60IswAYI-g2',
      ]);
      expect(rows.map((row) => row.anchorIsWhite1), [false, false]);
      expect(asWhite.orderedGames, hasLength(2));

      // "1-0": one hit per colour, still the whole match's score.
      final whiteWins = headersOf(search(['g2', 'g3'])).single;
      expect(whiteWins.player1, 'Nakamura, Hikaru');
      expect(whiteWins.player1Score, 2.5);
      expect(whiteWins.player2Score, 1.5);
    });

    test('board grid keeps side A at the bottom, not the higher rating', () {
      final layout = _sccLayout(
        _sccRoundOf16().reversed.toList(),
        mode: GamesListViewMode.chessBoardGrid,
      );

      // Niemann outrates Nihal, but Nihal had White in game 1.
      final row = rowsOf(layout, 'Nihal Sarin').single;
      expect(row.game1.gameId, '60IswAYI-ck9pdy');
      expect(row.game2?.gameId, '60IswAYI-67v3yr');
      expect(row.fixedBottomSide1, Side.white);
      expect(row.fixedBottomSide2, Side.black);
      expect(row.anchorIsWhite1, isTrue);
      expect(row.anchorIsWhite2, isFalse);
    });
  });

  // World Cup shape: every leg and tiebreak is a source round of its own, so
  // no pairing repeats inside one round. The expected text was captured from
  // the layout before match play existed (stable e199243f) and must not move.
  test('a knockout with one game per pairing per round renders as before', () {
    GamesTourFlattenedLayout build(GamesListViewMode mode) =>
        buildGamesTourFlattenedLayout(
          rounds: [
            _round('knockout-stage-wc-round-3', RoundStatus.live),
            _round('knockout-stage-wc-round-2', RoundStatus.completed),
            _round('r-swiss-5', RoundStatus.completed),
          ],
          gamesByRound: {
            'knockout-stage-wc-round-3': _worldCupRound3(),
            'knockout-stage-wc-round-2': _worldCupRound2(),
            'r-swiss-5': _swissRound(),
          },
          mode: mode,
          matchExpansionState: const {},
          roundExpansionState: const {},
          isKnockoutTournament: true,
          displayMode: GameDisplayMode.all,
          roundStartTimesById: {
            'wc-r3-g1': DateTime.utc(2026, 7, 10, 10),
            'wc-r3-g2': DateTime.utc(2026, 7, 11, 10),
            'wc-r2-g1': DateTime.utc(2026, 7, 7, 10),
            'wc-r2-g2': DateTime.utc(2026, 7, 8, 10),
          },
        );

    final cards = build(GamesListViewMode.gamesCard);
    expect(
      _legacySnapshot(cards),
      '''
round knockout-stage-wc-round-3 n=4
header fide:1111|fide:46616543 Lower, Player 0.0-1.0 Gukesh D played=2026-07-11 11:00:00.000Z complete=false games=x-g1,x-g2 lit=true
row x-g2#0 b=white null#null b2=null last=false
row x-g1#1 b=black null#null b2=null last=true
header fide:2222|fide:3333 Abc, Def 0.5-0.5 Xyz, Uvw played=2026-07-11 10:00:00.000Z complete=false games=y-g1,y-g2 lit=true
row y-g2#2 b=white null#null b2=null last=false
row y-g1#3 b=black null#null b2=null last=true
round knockout-stage-wc-round-2 n=3
header fide:4444|fide:46616543 Swiss, One 1.5-1.5 Gukesh D played=2026-07-08 15:00:00.000Z complete=true games=z-g1,z-g2,z-tb lit=false
row z-tb#4 b=black null#null b2=null last=false
row z-g2#5 b=white null#null b2=null last=false
row z-g1#6 b=black null#null b2=null last=true
round r-swiss-5 n=2
row s-1#7 b=null null#null b2=null last=false
row s-2#8 b=null null#null b2=null last=true
ordered x-g2,x-g1,y-g2,y-g1,z-tb,z-g2,z-g1,s-1,s-2
headers {knockout-stage-wc-round-3: 0, knockout-stage-wc-round-2: 7, r-swiss-5: 12}
items {x-g2: 2, x-g1: 3, y-g2: 5, y-g1: 6, z-tb: 9, z-g2: 10, z-g1: 11, s-1: 13, s-2: 14}''',
    );

    final grid = build(GamesListViewMode.chessBoardGrid);
    expect(
      _legacySnapshot(grid),
      '''
round knockout-stage-wc-round-3 n=4
header fide:1111|fide:46616543 Lower, Player 0.0-1.0 Gukesh D played=2026-07-11 11:00:00.000Z complete=false games=x-g1,x-g2 lit=true
row x-g2#0 b=white x-g1#1 b2=black last=true
header fide:2222|fide:3333 Abc, Def 0.5-0.5 Xyz, Uvw played=2026-07-11 10:00:00.000Z complete=false games=y-g1,y-g2 lit=true
row y-g2#2 b=white y-g1#3 b2=black last=true
round knockout-stage-wc-round-2 n=3
header fide:4444|fide:46616543 Swiss, One 1.5-1.5 Gukesh D played=2026-07-08 15:00:00.000Z complete=true games=z-g1,z-g2,z-tb lit=false
row z-tb#4 b=black z-g2#5 b2=white last=false
row z-g1#6 b=black null#null b2=null last=true
round r-swiss-5 n=2
row s-1#7 b=null s-2#8 b2=null last=true
ordered x-g2,x-g1,y-g2,y-g1,z-tb,z-g2,z-g1,s-1,s-2
headers {knockout-stage-wc-round-3: 0, knockout-stage-wc-round-2: 5, r-swiss-5: 9}
items {x-g2: 2, x-g1: 2, y-g2: 4, y-g1: 4, z-tb: 7, z-g2: 7, z-g1: 8, s-1: 10, s-2: 10}''',
    );

    // Nothing outside match play gets the fixed-side card or the new rules.
    for (final layout in [cards, grid]) {
      for (final row in layout.entries.whereType<GamesTourGameRowEntry>()) {
        expect(row.anchorIsWhite1, isNull);
        expect(row.anchorIsWhite2, isNull);
      }
      for (final header
          in layout.entries.whereType<GamesTourMatchHeaderEntry>()) {
        expect(header.matchHeader.isMatchPlay, isFalse);
        expect(
          header.matchHeader.hasLiveGame,
          header.matchHeader.games.any(
            (game) => !game.effectiveGameStatus.isFinished,
          ),
        );
      }
    }
  });

  // Women's Speed Chess Championship 2026 (tour QfveGZSJ): one source round
  // per match, 14-16 games each, every last_move_time NULL so games carry
  // only their game day. Each match's own round start is the one precise
  // time, as before match play.
  test('a round of its own dates and orders a played match-play match', () {
    final stage = _round(
      'knockout-stage-QfveGZSJ-round-of-16',
      RoundStatus.completed,
    );
    List<GamesTourModel> match(
      String roundId,
      PlayerCard a,
      PlayerCard b,
      DateTime day,
    ) => [
      for (var game = 1; game <= 3; game++)
        _legGame(
          '$roundId-$game',
          game.isOdd ? a : b,
          game.isOdd ? b : a,
          roundId,
          'round-of-16',
          status: game == 2 ? GameStatus.whiteWins : GameStatus.draw,
          lastMove: 'e2e4',
          lastMoveTime: day,
          board: game,
        ),
    ];
    final games = [
      ...match('ju', _abc, _xyz, DateTime.utc(2026, 7, 6)),
      ...match('vaishali', _swissOne, _swissTwo, DateTime.utc(2026, 7, 6)),
      ...match('aaMB3ZxC', _gukesh, _lower, DateTime.utc(2026, 7, 13)),
      ...match('Rv7eXO8s', _swissThree, _swissFour, DateTime.utc(2026, 7, 13)),
    ];

    final layout = _layout(
      rounds: [stage],
      gamesByRound: {stage.id: games},
      roundStartTimesById: {
        'ju': DateTime.utc(2026, 7, 6, 14),
        'vaishali': DateTime.utc(2026, 7, 6, 16, 30),
        'aaMB3ZxC': DateTime.utc(2026, 7, 13, 12),
        'Rv7eXO8s': DateTime.utc(2026, 7, 13, 14, 30),
      },
    );

    final headers = [
      for (final entry in layout.entries.whereType<GamesTourMatchHeaderEntry>())
        entry.matchHeader,
    ];
    expect(headers.every((header) => header.isMatchPlay), isTrue);
    expect(headers.map((header) => header.player1), [
      'Swiss, Three',
      'Gukesh D',
      'Swiss, One',
      'Abc, Def',
    ]);
    expect(headers.map((header) => header.playedAt), [
      DateTime.utc(2026, 7, 13, 14, 30),
      DateTime.utc(2026, 7, 13, 12),
      DateTime.utc(2026, 7, 6, 16, 30),
      DateTime.utc(2026, 7, 6, 14),
    ]);
  });

  // A stage can mix both kinds: a round per match where one round so far
  // holds a single 0-move board (no pairing repeats there yet). That match
  // keeps the legacy reading (highest rating at the bottom); the others are
  // match play. A 0-move board is not play in either reading, so the played
  // match leads.
  test('a stage mixing match-play and legacy matches reads each its way', () {
    final stage = _round('knockout-stage-mixed-round-of-16', RoundStatus.live);
    final games = [
      for (final (id, white, black, board) in [
        ('a1', _gukesh, _lower, 1),
        ('a2', _lower, _gukesh, 2),
      ])
        _legGame(
          id,
          white,
          black,
          'match-a',
          'round-of-16',
          status: GameStatus.draw,
          lastMove: 'e2e4',
          lastMoveTime: DateTime.utc(2026, 7, 6, 15, board),
          board: board,
        ),
      _legGame(
        'c1',
        _swissOne,
        _swissTwo,
        'match-c',
        'round-of-16',
        board: 1,
      ),
    ];

    final layout = _layout(rounds: [stage], gamesByRound: {stage.id: games});
    final headers = [
      for (final entry in layout.entries.whereType<GamesTourMatchHeaderEntry>())
        entry.matchHeader,
    ];
    expect(headers.map((header) => header.player1), [
      'Gukesh D',
      'Swiss, One',
    ]);
    expect(headers.map((header) => header.isMatchPlay), [true, false]);
    expect(headers.last.hasLiveGame, isFalse);
    final legacyRow =
        layout.entries.whereType<GamesTourGameRowEntry>().firstWhere(
          (row) => row.game1.gameId == 'c1',
        );
    expect(legacyRow.anchorIsWhite1, isNull);
    expect(legacyRow.fixedBottomSide1, Side.black);
  });

  // Dutch Championship 2026 Open, Round 4 (weYdpnGl): the classical legs are
  // rounds of their own; only pair P's rapid tiebreak games share a round.
  // No match of the stage is match play, so it renders exactly as on stable
  // e199243f (the expected text was captured there).
  test('a tiebreak round shared by one pairing leaves the stage as before', () {
    final stage = _round('knockout-stage-weYdpnGl-round-4', RoundStatus.live);
    final games = [
      _legGame(
        'p1',
        _gukesh,
        _lower,
        'r41',
        'game-1',
        status: GameStatus.draw,
        lastMove: 'a7a6',
        lastMoveTime: DateTime.utc(2026, 6, 4, 15),
        board: 1,
        pgn: '[Round "4.1"]\n\n1/2-1/2',
      ),
      // Pair Q: the lower-rated player has White in game 1, and the
      // higher-rated one stays at the bottom of every board.
      _legGame(
        'q1',
        _abc,
        _xyz,
        'r41',
        'game-1',
        status: GameStatus.blackWins,
        lastMove: 'a7a6',
        lastMoveTime: DateTime.utc(2026, 6, 4, 16),
        board: 2,
        pgn: '[Round "4.2"]\n\n0-1',
      ),
      _legGame(
        'p2',
        _lower,
        _gukesh,
        'r42',
        'game-2',
        status: GameStatus.draw,
        lastMove: 'a7a6',
        lastMoveTime: DateTime.utc(2026, 6, 5, 15),
        board: 1,
        pgn: '[Round "5.1"]\n\n1/2-1/2',
      ),
      _legGame(
        'q2',
        _xyz,
        _abc,
        'r42',
        'game-2',
        status: GameStatus.draw,
        lastMove: 'a7a6',
        lastMoveTime: DateTime.utc(2026, 6, 5, 16),
        board: 2,
        pgn: '[Round "5.2"]\n\n1/2-1/2',
      ),
      _legGame(
        'p3',
        _gukesh,
        _lower,
        'r4tb',
        'tiebreak-1-rapid-1',
        status: GameStatus.whiteWins,
        lastMove: 'a7a6',
        lastMoveTime: DateTime.utc(2026, 6, 6, 12),
        board: 1,
        pgn: '[Round "6.1"]\n\n1-0',
      ),
      _legGame(
        'p4',
        _lower,
        _gukesh,
        'r4tb',
        'tiebreak-1-rapid-2',
        lastMove: 'e2e4',
        lastMoveTime: DateTime.utc(2026, 6, 6, 13),
        board: 2,
        pgn: '[Round "7.1"]\n\n*',
      ),
    ];

    GamesTourFlattenedLayout build(GamesListViewMode mode) => _layout(
      rounds: [stage],
      gamesByRound: {stage.id: games},
      mode: mode,
      roundStartTimesById: {
        'r41': DateTime.utc(2026, 6, 4, 12),
        'r42': DateTime.utc(2026, 6, 5, 12),
        'r4tb': DateTime.utc(2026, 6, 6, 11),
      },
    );

    expect(_legacySnapshot(build(GamesListViewMode.gamesCard)), '''
round knockout-stage-weYdpnGl-round-4 n=6
header fide:1111|fide:46616543 Gukesh D 2.0-1.0 Lower, Player played=2026-06-06 13:00:00.000Z complete=false games=p1,p2,p3,p4 lit=true
row p4#0 b=black null#null b2=null last=false
row p3#1 b=white null#null b2=null last=false
row p2#2 b=black null#null b2=null last=false
row p1#3 b=white null#null b2=null last=true
header fide:2222|fide:3333 Abc, Def 0.5-1.5 Xyz, Uvw played=2026-06-05 16:00:00.000Z complete=true games=q1,q2 lit=false
row q2#4 b=white null#null b2=null last=false
row q1#5 b=black null#null b2=null last=true
ordered p4,p3,p2,p1,q2,q1
headers {knockout-stage-weYdpnGl-round-4: 0}
items {p4: 2, p3: 3, p2: 4, p1: 5, q2: 7, q1: 8}''');
    expect(_legacySnapshot(build(GamesListViewMode.chessBoardGrid)), '''
round knockout-stage-weYdpnGl-round-4 n=6
header fide:1111|fide:46616543 Gukesh D 2.0-1.0 Lower, Player played=2026-06-06 13:00:00.000Z complete=false games=p1,p2,p3,p4 lit=true
row p4#0 b=black p3#1 b2=white last=false
row p2#2 b=black p1#3 b2=white last=true
header fide:2222|fide:3333 Abc, Def 0.5-1.5 Xyz, Uvw played=2026-06-05 16:00:00.000Z complete=true games=q1,q2 lit=false
row q2#4 b=white q1#5 b2=black last=true
ordered p4,p3,p2,p1,q2,q1
headers {knockout-stage-weYdpnGl-round-4: 0}
items {p4: 2, p3: 2, p2: 3, p1: 3, q2: 5, q1: 5}''');
    for (final mode in GamesListViewMode.values) {
      final layout = build(mode);
      for (final row in layout.entries.whereType<GamesTourGameRowEntry>()) {
        expect(row.anchorIsWhite1, isNull);
        expect(row.anchorIsWhite2, isNull);
      }
      for (final header
          in layout.entries.whereType<GamesTourMatchHeaderEntry>()) {
        expect(header.matchHeader.isMatchPlay, isFalse);
      }
    }
  });

  test('group-event spans omit cards when the round is collapsed', () {
    expect(
      groupEventRoundListItemCount(isExpanded: true, matchupCardCount: 3),
      4,
    );
    expect(
      groupEventRoundListItemCount(isExpanded: false, matchupCardCount: 3),
      1,
    );
  });

  test('empty sibling loading never covers an already loaded stage', () {
    expect(
      shouldKeepGroupedGamesLoading(
        representedSiblingIsLoading: true,
        hasGroupedGames: false,
      ),
      isTrue,
    );
    expect(
      shouldKeepGroupedGamesLoading(
        representedSiblingIsLoading: true,
        hasGroupedGames: true,
      ),
      isFalse,
    );
  });

  test('priority refresh keeps loading when only new boards are visible', () {
    expect(
      shouldKeepPrioritySnapshotLoading(
        isSearchMode: false,
        hadGroupedGamesBeforeOrdering: true,
        hasGroupedGamesAfterOrdering: false,
        hasResolvedAutoPins: true,
        isRefreshingAutoPins: true,
      ),
      isTrue,
    );
    expect(
      shouldKeepPrioritySnapshotLoading(
        isSearchMode: false,
        hadGroupedGamesBeforeOrdering: true,
        hasGroupedGamesAfterOrdering: true,
        hasResolvedAutoPins: true,
        isRefreshingAutoPins: true,
      ),
      isFalse,
    );
  });
}

GamesTourFlattenedLayout _layout({
  required List<GamesAppBarModel> rounds,
  required Map<String, List<GamesTourModel>> gamesByRound,
  GamesListViewMode mode = GamesListViewMode.gamesCard,
  Map<String, bool> matchExpansionState = const {},
  Map<String, bool> roundExpansionState = const {},
  GameDisplayMode displayMode = GameDisplayMode.all,
  Map<String, DateTime?> roundStartTimesById = const {},
  bool isSearchMode = false,
  Map<String, List<GamesTourModel>> fullGamesByRound = const {},
  List<Map<String, dynamic>> matchSchedule = const [],
}) => buildGamesTourFlattenedLayout(
  rounds: rounds,
  gamesByRound: gamesByRound,
  mode: mode,
  matchExpansionState: matchExpansionState,
  roundExpansionState: roundExpansionState,
  isKnockoutTournament: true,
  displayMode: displayMode,
  roundStartTimesById: roundStartTimesById,
  isSearchMode: isSearchMode,
  fullGamesByRound: fullGamesByRound,
  matchSchedulesByTourId: {'fqCjSUpE': matchSchedule},
);

GamesAppBarModel _round(String id, RoundStatus status, {DateTime? startsAt}) =>
    GamesAppBarModel(id: id, name: id, startsAt: startsAt, roundStatus: status);

GamesTourModel _game(
  String id, {
  bool reverseColors = false,
  String slug = 'game-1',
  GameStatus status = GameStatus.ongoing,
  int identityOffset = 0,
  String? roundId,
  DateTime? lastMoveTime,
  String? lastMove,
  int? boardNr,
}) {
  final alpha = _player(
    'GM Alpha Player $identityOffset',
    11 + identityOffset,
    2700,
  );
  final beta = _player(
    'Beta Player $identityOffset',
    22 + identityOffset,
    2600,
  );
  return GamesTourModel(
    gameId: id,
    whitePlayer: reverseColors ? beta : alpha,
    blackPlayer: reverseColors ? alpha : beta,
    whiteTimeDisplay: '',
    blackTimeDisplay: '',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    whiteClockSeconds: lastMove == null ? null : 300,
    blackClockSeconds: lastMove == null ? null : 300,
    gameStatus: status,
    roundId: roundId ?? slug,
    roundSlug: slug,
    tourId: 'tour',
    boardNr: boardNr,
    lastMoveTime: lastMoveTime,
    lastMove: lastMove,
  );
}

PlayerCard _player(String name, int fideId, int rating) => PlayerCard(
  name: name,
  federation: 'FIDE',
  title: '',
  rating: rating,
  countryCode: 'FIDE',
  team: null,
  fideId: fideId,
);

// --- Speed Chess Championship XI, Round of 16 (round 60IswAYI) -------------

final _nakamura = _player('Nakamura, Hikaru', 2016192, 2802);
final _erdogmus = _player('Erdogmus, Yagiz Kaan', 44599790, 2650);
final _carlsen = _player('Carlsen, Magnus', 1503014, 2840);
final _movahed = _player('Movahed, Sina', 42520835, 2560);
final _abdusattorov = _player('Abdusattorov, Nodirbek', 14204118, 2760);
final _keymer = _player('Keymer, Vincent', 12940690, 2740);
// Niemann outrates Nihal here on purpose: side A follows game 1, not rating.
final _nihal = _player('Nihal Sarin', 25092340, 2700);
final _niemann = _player('Niemann, Hans Moke', 2093596, 2750);
final _firouzja = _player('Firouzja, Alireza', 12573981, 2770);
final _artemiev = _player('Artemiev, Vladislav', 24101605, 2720);
final _caruana = _player('Caruana, Fabiano', 2020009, 2790);
final _sindarov = _player('Sindarov, Javokhir', 14205483, 2725);
final _lazavik = _player('Lazavik, Denis', 13515110, 2650);
final _andreikin = _player('Andreikin, Dmitry', 4158814, 2700);
final _so = _player('So, Wesley', 5202213, 2760);
final _pragg = _player('Praggnanandhaa R', 25059530, 2765);

const _initialFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

GamesTourModel _sccGame(
  String id,
  int board,
  PlayerCard white,
  PlayerCard black,
  String pgnRound, {
  GameStatus status = GameStatus.ongoing,
  String? lastMove,
  DateTime? lastMoveTime,
  bool deferPgn = false,
}) {
  final gameDay = DateTime.utc(2026, 11, 16);
  return GamesTourModel(
    gameId: '60IswAYI-$id',
    whitePlayer: white,
    blackPlayer: black,
    whiteTimeDisplay: '',
    blackTimeDisplay: '',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    whiteClockSeconds: lastMove == null ? null : 120,
    blackClockSeconds: lastMove == null ? null : 120,
    gameStatus: status,
    roundId: '60IswAYI',
    roundSlug: 'round-of-16',
    tourId: 'fqCjSUpE',
    boardNr: board,
    lastMove: lastMove,
    fen: lastMove == null ? _initialFen : null,
    // Lean rows defer the PGN of rated finished games. The [Board] tag is the
    // feed's junk value and must never be read.
    pgn: deferPgn
        ? null
        : [
            '[Event "Speed Chess Championship 2026"]',
            '[Round "$pgnRound"]',
            '[Board "${board + 40}"]',
            '[White "${white.name}"]',
            '[Black "${black.name}"]',
            '',
            status == GameStatus.ongoing ? '*' : '1/2-1/2',
          ].join('\n'),
    // Rows without a move fall back to the game day, as GamesTourModel does.
    lastMoveTime: lastMoveTime ?? gameDay,
    gameDay: gameDay,
  );
}

/// The round at 2026-11-16 ~17:20 UTC, in board order.
List<GamesTourModel> _sccRoundOf16({
  bool deferFinishedPgn = true,
  GameStatus nakamuraGame2 = GameStatus.ongoing,
}) => [
  _sccGame(
    'pq36vc',
    1,
    _nakamura,
    _erdogmus,
    '01.01',
    status: GameStatus.draw,
    lastMove: 'g8f6',
    lastMoveTime: DateTime.utc(2026, 11, 16, 17, 5),
    deferPgn: deferFinishedPgn,
  ),
  _sccGame('src7cv', 2, _carlsen, _movahed, '01.01'),
  _sccGame('1iw36s7', 3, _abdusattorov, _keymer, '01.01'),
  _sccGame('ck9pdy', 4, _nihal, _niemann, '01.01'),
  _sccGame('78pcxs', 5, _firouzja, _artemiev, '01.01'),
  _sccGame('um9vyy', 6, _caruana, _sindarov, '01.01'),
  _sccGame('1lcthoy', 7, _lazavik, _andreikin, '01.01'),
  _sccGame('1siueax', 8, _so, _pragg, '01.01'),
  _sccGame('67v3yr', 9, _niemann, _nihal, '01.02'),
  _sccGame('1fw7jih', 10, _andreikin, _lazavik, '01.02'),
  _sccGame('1a45jh4', 11, _movahed, _carlsen, '01.02'),
  _sccGame(
    '1md2dlh',
    12,
    _erdogmus,
    _nakamura,
    '01.02',
    status: nakamuraGame2,
    lastMove: 'e2e4',
    lastMoveTime: nakamuraGame2 == GameStatus.ongoing
        ? DateTime.utc(2026, 11, 16, 17, 20)
        : DateTime.utc(2026, 11, 16, 17, 31),
    deferPgn: deferFinishedPgn && nakamuraGame2 != GameStatus.ongoing,
  ),
  _sccGame('1i7jwd7', 13, _artemiev, _firouzja, '01.02'),
  _sccGame('1igry3e', 14, _pragg, _so, '01.02'),
  _sccGame('w84g18', 15, _keymer, _abdusattorov, '01.02'),
  _sccGame('166s5u7', 16, _sindarov, _caruana, '01.02'),
];

GamesTourFlattenedLayout _sccLayout(
  List<GamesTourModel> games, {
  GamesListViewMode mode = GamesListViewMode.gamesCard,
  Map<String, DateTime?> roundStartTimesById = const {},
  List<Map<String, dynamic>> matchSchedule = const [],
}) {
  final stage = _round('knockout-stage-fqCjSUpE-round-of-16', RoundStatus.live);
  return _layout(
    rounds: [stage],
    gamesByRound: {stage.id: games},
    mode: mode,
    roundStartTimesById: roundStartTimesById,
    matchSchedule: matchSchedule,
  );
}

const _sccSchedule = <Map<String, dynamic>>[
  {
    'roundId': '60IswAYI',
    'fideIds': ['2016192', '44599790'],
    'startsAt': '2026-11-16T17:00:00Z',
  },
  {
    'roundId': '60IswAYI',
    'fideIds': ['13515110', '4158814'],
    'startsAt': '2026-11-20T17:00:00Z',
  },
  {
    'roundId': '60IswAYI',
    'fideIds': ['12573981', '24101605'],
    'startsAt': '2026-11-27T17:30:00Z',
  },
  {
    'roundId': '60IswAYI',
    'fideIds': ['5202213', '25059530'],
    'startsAt': '2026-12-09T15:00:00Z',
  },
  {
    'roundId': '60IswAYI',
    'fideIds': ['1503014', '42520835'],
    'startsAt': '2026-12-16T14:00:00Z',
  },
  {
    'roundId': '60IswAYI',
    'fideIds': ['2020009', '14205483'],
    'startsAt': '2026-12-16T17:30:00Z',
  },
];

String _matchPlaySnapshot(GamesTourFlattenedLayout layout) => [
  for (final entry in layout.entries)
    switch (entry) {
      GamesTourMatchHeaderEntry(:final matchHeader) =>
        '${matchHeader.player1} ${matchHeader.player1Score}-'
            '${matchHeader.player2Score} ${matchHeader.player2} '
            '${matchHeader.playedAt} live=${matchHeader.hasLiveGame}',
      GamesTourGameRowEntry() =>
        '${entry.game1.gameId} a=${entry.anchorIsWhite1} '
            'b=${entry.fixedBottomSide1?.name}',
      _ => entry.runtimeType.toString(),
    },
].join('\n');

// --- Non-match-play knockout (World Cup shape) ------------------------------

final _gukesh = _player('Gukesh D', 46616543, 2780);
final _lower = _player('Lower, Player', 1111, 2650);
final _abc = _player('Abc, Def', 2222, 2700);
final _xyz = _player('Xyz, Uvw', 3333, 2710);
final _swissOne = _player('Swiss, One', 4444, 2600);
final _swissTwo = _player('Swiss, Two', 5555, 2610);
final _swissThree = _player('Swiss, Three', 6666, 2620);
final _swissFour = _player('Swiss, Four', 7777, 2630);

GamesTourModel _legGame(
  String id,
  PlayerCard white,
  PlayerCard black,
  String roundId,
  String slug, {
  GameStatus status = GameStatus.ongoing,
  String? lastMove,
  DateTime? lastMoveTime,
  int? board,
  String? pgn,
}) => GamesTourModel(
  gameId: id,
  whitePlayer: white,
  blackPlayer: black,
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  whiteClockSeconds: lastMove == null ? null : 300,
  blackClockSeconds: lastMove == null ? null : 300,
  gameStatus: status,
  roundId: roundId,
  roundSlug: slug,
  tourId: 'wc',
  lastMove: lastMove,
  lastMoveTime: lastMoveTime,
  boardNr: board,
  pgn: pgn,
);

List<GamesTourModel> _worldCupRound3() => [
  _legGame(
    'x-g2',
    _gukesh,
    _lower,
    'wc-r3-g2',
    'game-2',
    lastMove: 'e2e4',
    lastMoveTime: DateTime.utc(2026, 7, 11, 11),
    board: 1,
    pgn: '[Round "3.1"]\n[Board "1"]\n\n*',
  ),
  // The higher-rated player has Black in game 1.
  _legGame(
    'x-g1',
    _lower,
    _gukesh,
    'wc-r3-g1',
    'game-1',
    status: GameStatus.blackWins,
    lastMove: 'a7a6',
    lastMoveTime: DateTime.utc(2026, 7, 10, 13),
    board: 1,
  ),
  // A 0-move shell: outside match play it still lights the match.
  _legGame(
    'y-g2',
    _xyz,
    _abc,
    'wc-r3-g2',
    'game-2',
    board: 2,
    lastMoveTime: DateTime.utc(2026, 7, 11),
  ),
  _legGame(
    'y-g1',
    _abc,
    _xyz,
    'wc-r3-g1',
    'game-1',
    status: GameStatus.draw,
    lastMove: 'h7h6',
    lastMoveTime: DateTime.utc(2026, 7, 10, 12),
    board: 2,
  ),
];

List<GamesTourModel> _worldCupRound2() => [
  _legGame(
    'z-g1',
    _swissOne,
    _gukesh,
    'wc-r2-g1',
    'game-1',
    status: GameStatus.blackWins,
    lastMove: 'a7a6',
    lastMoveTime: DateTime.utc(2026, 7, 7, 12),
  ),
  _legGame(
    'z-g2',
    _gukesh,
    _swissOne,
    'wc-r2-g2',
    'game-2',
    status: GameStatus.draw,
    lastMove: 'a2a3',
    lastMoveTime: DateTime.utc(2026, 7, 8, 12),
  ),
  _legGame(
    'z-tb',
    _swissOne,
    _gukesh,
    'wc-r2-tb',
    'tiebreak-1-rapid-1',
    status: GameStatus.whiteWins,
    lastMove: 'a2a3',
    lastMoveTime: DateTime.utc(2026, 7, 8, 15),
  ),
];

List<GamesTourModel> _swissRound() => [
  _legGame(
    's-1',
    _swissOne,
    _swissTwo,
    'r-swiss-5',
    'round-5',
    status: GameStatus.draw,
    board: 1,
  ),
  _legGame(
    's-2',
    _swissThree,
    _swissFour,
    'r-swiss-5',
    'round-5',
    board: 2,
    lastMove: 'e2e4',
  ),
];

/// Only fields that existed before match play, so the expected text is the
/// layout's output on stable e199243f.
String _legacySnapshot(GamesTourFlattenedLayout layout) => [
  for (final entry in layout.entries)
    switch (entry) {
      GamesTourMatchHeaderEntry(:final matchHeader) =>
        'header ${matchHeader.matchKey} ${matchHeader.player1} '
            '${matchHeader.player1Score}-${matchHeader.player2Score} '
            '${matchHeader.player2} played=${matchHeader.playedAt} '
            'complete=${matchHeader.isComplete} '
            'games=${matchHeader.games.map((g) => g.gameId).join(',')} '
            'lit=${matchHeader.games.any((g) => !g.effectiveGameStatus.isFinished)}',
      GamesTourGameRowEntry() =>
        'row ${entry.game1.gameId}#${entry.globalIndex1} '
            'b=${entry.fixedBottomSide1?.name} '
            '${entry.game2?.gameId}#${entry.globalIndex2} '
            'b2=${entry.fixedBottomSide2?.name} last=${entry.isLastInSection}',
      GamesTourRoundHeaderEntry() =>
        'round ${entry.roundId} n=${entry.roundGames.length}',
      GamesTourSourceHeaderEntry() => 'source ${entry.roundId}',
      GamesTourMatchFormatHeaderEntry() => 'format',
    },
  'ordered ${layout.orderedGames.map((g) => g.gameId).join(',')}',
  'headers ${layout.roundHeaderIndices}',
  'items ${layout.gameItemIndices}',
].join('\n');
