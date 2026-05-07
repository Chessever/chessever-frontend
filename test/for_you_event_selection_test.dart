import 'package:chessever2/providers/for_you_games_logic.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_selection_logic.dart';
import 'package:flutter_test/flutter_test.dart';

TournamentPlayer _tourPlayer({required String name, String? team}) {
  return TournamentPlayer(name: name, played: 0, team: team);
}

Tour _makeTour({
  required String id,
  required String name,
  required List<DateTime> dates,
  String? groupBroadcastId = 'event-1',
  int? avgElo = 2700,
  String? format = 'Swiss',
  List<TournamentPlayer> players = const [],
}) {
  return Tour.fromJson({
    'id': id,
    'name': name,
    'slug': id,
    'info': {
      'format': format,
      'tc': '90+30',
      'players': '',
      'location': 'Test City',
    },
    'created_at': DateTime(2025, 1, 1, 12).toIso8601String(),
    'url': 'https://example.com/$id',
    'tier': 1,
    'dates': dates.map((date) => date.toIso8601String()).toList(),
    'players': players.map((player) => player.toJson()).toList(),
    'search': const <String>[],
    'group_broadcast_id': groupBroadcastId,
    'avg_elo': avgElo,
  });
}

Round _makeRound({
  required String id,
  required String tourId,
  required String name,
  required DateTime startsAt,
}) {
  return Round(
    id: id,
    slug: id,
    tourId: tourId,
    tourSlug: tourId,
    name: name,
    createdAt: startsAt.subtract(const Duration(hours: 1)),
    startsAt: startsAt,
    url: 'https://example.com/$id',
  );
}

Player _player({required String name, String team = '', int fideId = 1}) {
  return Player(
    name: name,
    title: 'GM',
    rating: 2700,
    fideId: fideId,
    fed: 'USA',
    clock: 0,
    team: team,
  );
}

Games _makeGame({
  required String id,
  required String roundId,
  required String roundSlug,
  required String tourId,
  required List<Player> players,
  int? boardNr,
  String? status = '*',
  String? lastMove = 'e2e4',
  DateTime? lastMoveTime,
  DateTime? dateStart,
}) {
  return Games(
    id: id,
    roundId: roundId,
    roundSlug: roundSlug,
    tourId: tourId,
    tourSlug: tourId,
    players: players,
    boardNr: boardNr,
    status: status,
    lastMove: lastMove,
    lastMoveTime: lastMoveTime,
    dateStart: dateStart,
  );
}

void main() {
  group('selectDefaultTour', () {
    test('reuses saved valid selection', () {
      final now = DateTime.now();
      final tourA = _makeTour(
        id: 'tour-a',
        name: 'Open',
        dates: [now.subtract(const Duration(days: 1)), now],
      );
      final tourB = _makeTour(
        id: 'tour-b',
        name: 'Challengers',
        dates: [now.subtract(const Duration(days: 1)), now],
        avgElo: 2600,
      );

      final selected = selectDefaultTour(
        tourModels: [
          TourModel(tour: tourA, roundStatus: RoundStatus.ongoing),
          TourModel(tour: tourB, roundStatus: RoundStatus.ongoing),
        ],
        liveTourIds: const [],
        savedTourId: 'tour-b',
      );

      expect(selected.id, 'tour-b');
    });

    test('ignores upcoming saved selection when a started tour exists', () {
      final now = DateTime.now();
      final liveTour = _makeTour(
        id: 'tour-live',
        name: 'Live Section',
        dates: [now.subtract(const Duration(hours: 2)), now],
      );
      final upcomingTour = _makeTour(
        id: 'tour-upcoming',
        name: 'Future Section',
        dates: [
          now.add(const Duration(days: 1)),
          now.add(const Duration(days: 2)),
        ],
      );

      final selected = selectDefaultTour(
        tourModels: [
          TourModel(tour: liveTour, roundStatus: RoundStatus.live),
          TourModel(tour: upcomingTour, roundStatus: RoundStatus.upcoming),
        ],
        liveTourIds: const ['tour-live'],
        savedTourId: 'tour-upcoming',
      );

      expect(selected.id, 'tour-live');
    });

    test('falls back to activity tour when other signals are absent', () {
      final now = DateTime.now();
      final tourA = _makeTour(
        id: 'tour-a',
        name: 'Older',
        dates: [
          now.subtract(const Duration(days: 4)),
          now.subtract(const Duration(days: 3)),
        ],
        avgElo: null,
      );
      final tourB = _makeTour(
        id: 'tour-b',
        name: 'Recent Activity',
        dates: [
          now.subtract(const Duration(days: 4)),
          now.subtract(const Duration(days: 3)),
        ],
        avgElo: null,
      );

      final selected = selectDefaultTour(
        tourModels: [
          TourModel(tour: tourA, roundStatus: RoundStatus.completed),
          TourModel(tour: tourB, roundStatus: RoundStatus.completed),
        ],
        liveTourIds: const [],
        activityTourId: 'tour-b',
      );

      expect(selected.id, 'tour-b');
    });
  });

  group('buildForYouEventGamesSnapshot', () {
    test(
      'preconfigured events prioritize the same top round as the game list',
      () {
        final now = DateTime.now();
        final tour = _makeTour(
          id: 'tour-1',
          name: 'FIDE Candidates 2026: Open',
          dates: [
            now.subtract(const Duration(days: 1)),
            now.add(const Duration(days: 10)),
          ],
        );
        final rounds = [
          _makeRound(
            id: 'round-1',
            tourId: 'tour-1',
            name: 'Round 1',
            startsAt: now.subtract(const Duration(hours: 4)),
          ),
          _makeRound(
            id: 'round-2',
            tourId: 'tour-1',
            name: 'Round 2',
            startsAt: now.add(const Duration(hours: 1)),
          ),
          _makeRound(
            id: 'round-3',
            tourId: 'tour-1',
            name: 'Round 3',
            startsAt: now.add(const Duration(days: 1)),
          ),
        ];
        final games = [
          _makeGame(
            id: 'r2-g1',
            roundId: 'round-2',
            roundSlug: 'round-2',
            tourId: 'tour-1',
            boardNr: 1,
            lastMoveTime: now,
            players: [_player(name: 'A'), _player(name: 'B', fideId: 2)],
          ),
          _makeGame(
            id: 'r2-g2',
            roundId: 'round-2',
            roundSlug: 'round-2',
            tourId: 'tour-1',
            boardNr: 2,
            lastMoveTime: now,
            players: [
              _player(name: 'C', fideId: 3),
              _player(name: 'D', fideId: 4),
            ],
          ),
          _makeGame(
            id: 'r1-g1',
            roundId: 'round-1',
            roundSlug: 'round-1',
            tourId: 'tour-1',
            boardNr: 1,
            lastMoveTime: now.subtract(const Duration(hours: 3)),
            players: [
              _player(name: 'E', fideId: 5),
              _player(name: 'F', fideId: 6),
            ],
          ),
          _makeGame(
            id: 'r1-g2',
            roundId: 'round-1',
            roundSlug: 'round-1',
            tourId: 'tour-1',
            boardNr: 2,
            lastMoveTime: now.subtract(const Duration(hours: 3)),
            players: [
              _player(name: 'G', fideId: 7),
              _player(name: 'H', fideId: 8),
            ],
          ),
          _makeGame(
            id: 'r3-g1',
            roundId: 'round-3',
            roundSlug: 'round-3',
            tourId: 'tour-1',
            boardNr: 1,
            lastMoveTime: now.subtract(const Duration(days: 1)),
            players: [
              _player(name: 'I', fideId: 9),
              _player(name: 'J', fideId: 10),
            ],
          ),
        ];

        final snapshot = buildForYouEventGamesSnapshot(
          eventId: 'event-1',
          selectedTour: tour,
          eventTours: [tour],
          selectedTourRounds: rounds,
          roundsByTourId: {'tour-1': rounds},
          selectedTourGames: games,
          gamesByTourId: {'tour-1': games},
          liveRoundIds: const [],
          pinnedIds: const [],
        );

        expect(snapshot.visibleGames.map((game) => game.gameId).take(4), [
          'r2-g1',
          'r2-g2',
          'r1-g1',
          'r1-g2',
        ]);
      },
    );

    test('actual live game rows override stale live round ids', () {
      final now = DateTime.now();
      final tour = _makeTour(
        id: 'tour-1',
        name: 'Titled Tuesday',
        dates: [now.subtract(const Duration(hours: 3)), now],
      );
      final rounds = [
        _makeRound(
          id: 'round-10',
          tourId: 'tour-1',
          name: 'Round 10',
          startsAt: now.subtract(const Duration(minutes: 30)),
        ),
        _makeRound(
          id: 'round-11',
          tourId: 'tour-1',
          name: 'Round 11',
          startsAt: now.add(const Duration(hours: 2)),
        ),
      ];
      final games = [
        _makeGame(
          id: 'r10-g1',
          roundId: 'round-10',
          roundSlug: 'round-10',
          tourId: 'tour-1',
          status: '1-0',
          boardNr: 1,
          lastMoveTime: now.subtract(const Duration(minutes: 3)),
          players: [_player(name: 'A'), _player(name: 'B', fideId: 2)],
        ),
        _makeGame(
          id: 'r11-g1',
          roundId: 'round-11',
          roundSlug: 'round-11',
          tourId: 'tour-1',
          boardNr: 1,
          lastMoveTime: now.subtract(const Duration(minutes: 1)),
          players: [
            _player(name: 'C', fideId: 3),
            _player(name: 'D', fideId: 4),
          ],
        ),
      ];

      final snapshot = buildForYouEventGamesSnapshot(
        eventId: 'event-1',
        selectedTour: tour,
        eventTours: [tour],
        selectedTourRounds: rounds,
        roundsByTourId: {'tour-1': rounds},
        selectedTourGames: games,
        gamesByTourId: {'tour-1': games},
        liveRoundIds: const ['round-10'],
        pinnedIds: const [],
      );

      expect(snapshot.visibleGames.first.gameId, 'r11-g1');
    });

    test('preconfigured future placeholders do not override live games', () {
      final now = DateTime.now();
      final tour = _makeTour(
        id: 'tour-1',
        name: 'GCT: Super Rapid & Blitz Poland 2026 | Rapid',
        dates: [now.subtract(const Duration(days: 1)), now],
      );
      final liveRound = _makeRound(
        id: 'round-8',
        tourId: 'tour-1',
        name: 'Round 8',
        startsAt: now.subtract(const Duration(minutes: 20)),
      );
      final upcomingRound = _makeRound(
        id: 'round-9',
        tourId: 'tour-1',
        name: 'Round 9',
        startsAt: now.add(const Duration(minutes: 40)),
      );
      final games = [
        _makeGame(
          id: 'r8-g1',
          roundId: liveRound.id,
          roundSlug: 'round-8',
          tourId: 'tour-1',
          boardNr: 1,
          lastMoveTime: now.subtract(const Duration(minutes: 1)),
          players: [_player(name: 'A'), _player(name: 'B', fideId: 2)],
        ),
        _makeGame(
          id: 'r8-g2',
          roundId: liveRound.id,
          roundSlug: 'round-8',
          tourId: 'tour-1',
          boardNr: 2,
          lastMoveTime: now.subtract(const Duration(minutes: 2)),
          players: [
            _player(name: 'C', fideId: 3),
            _player(name: 'D', fideId: 4),
          ],
        ),
        _makeGame(
          id: 'r9-g1',
          roundId: upcomingRound.id,
          roundSlug: 'round-9',
          tourId: 'tour-1',
          boardNr: 1,
          lastMove: null,
          lastMoveTime: null,
          dateStart: upcomingRound.startsAt,
          players: [
            _player(name: 'E', fideId: 5),
            _player(name: 'F', fideId: 6),
          ],
        ),
        _makeGame(
          id: 'r9-g2',
          roundId: upcomingRound.id,
          roundSlug: 'round-9',
          tourId: 'tour-1',
          boardNr: 2,
          lastMove: null,
          lastMoveTime: null,
          dateStart: upcomingRound.startsAt,
          players: [
            _player(name: 'G', fideId: 7),
            _player(name: 'H', fideId: 8),
          ],
        ),
      ];

      final snapshot = buildForYouEventGamesSnapshot(
        eventId: 'event-1',
        selectedTour: tour,
        eventTours: [tour],
        selectedTourRounds: [liveRound, upcomingRound],
        roundsByTourId: {
          'tour-1': [liveRound, upcomingRound],
        },
        selectedTourGames: games,
        gamesByTourId: {'tour-1': games},
        liveRoundIds: const [],
        pinnedIds: const [],
      );

      expect(snapshot.visibleGames.map((game) => game.gameId).take(2), [
        'r8-g1',
        'r8-g2',
      ]);
    });

    test('regular event returns Games-tab visible order', () {
      final now = DateTime.now();
      final tour = _makeTour(
        id: 'tour-1',
        name: 'Masters',
        dates: [now.subtract(const Duration(days: 1)), now],
      );
      final rounds = [
        _makeRound(
          id: 'round-2',
          tourId: 'tour-1',
          name: 'Round 2',
          startsAt: now.subtract(const Duration(hours: 2)),
        ),
        _makeRound(
          id: 'round-1',
          tourId: 'tour-1',
          name: 'Round 1',
          startsAt: now.subtract(const Duration(days: 1)),
        ),
      ];
      final games = [
        _makeGame(
          id: 'g1',
          roundId: 'round-2',
          roundSlug: 'round-2',
          tourId: 'tour-1',
          boardNr: 1,
          lastMoveTime: now,
          players: [_player(name: 'A'), _player(name: 'B', fideId: 2)],
        ),
        _makeGame(
          id: 'g2',
          roundId: 'round-2',
          roundSlug: 'round-2',
          tourId: 'tour-1',
          boardNr: 2,
          lastMoveTime: now,
          players: [
            _player(name: 'C', fideId: 3),
            _player(name: 'D', fideId: 4),
          ],
        ),
        _makeGame(
          id: 'g3',
          roundId: 'round-1',
          roundSlug: 'round-1',
          tourId: 'tour-1',
          boardNr: 1,
          lastMoveTime: now.subtract(const Duration(hours: 5)),
          players: [
            _player(name: 'E', fideId: 5),
            _player(name: 'F', fideId: 6),
          ],
        ),
        _makeGame(
          id: 'g4',
          roundId: 'round-1',
          roundSlug: 'round-1',
          tourId: 'tour-1',
          boardNr: 2,
          lastMoveTime: now.subtract(const Duration(hours: 5)),
          players: [
            _player(name: 'G', fideId: 7),
            _player(name: 'H', fideId: 8),
          ],
        ),
        _makeGame(
          id: 'g5',
          roundId: 'round-1',
          roundSlug: 'round-1',
          tourId: 'tour-1',
          boardNr: 3,
          lastMoveTime: now.subtract(const Duration(hours: 5)),
          players: [
            _player(name: 'I', fideId: 9),
            _player(name: 'J', fideId: 10),
          ],
        ),
      ];

      final snapshot = buildForYouEventGamesSnapshot(
        eventId: 'event-1',
        selectedTour: tour,
        eventTours: [tour],
        selectedTourRounds: rounds,
        roundsByTourId: {'tour-1': rounds},
        selectedTourGames: games,
        gamesByTourId: {'tour-1': games},
        liveRoundIds: const [],
        pinnedIds: const [],
      );

      expect(snapshot.visibleGames.map((game) => game.gameId).take(4), [
        'g1',
        'g2',
        'g3',
        'g4',
      ]);
    });

    test('group event flattens matchup cards without round headers', () {
      final now = DateTime.now();
      final tour = _makeTour(
        id: 'team-tour',
        name: 'Team Championship',
        dates: [now.subtract(const Duration(days: 1)), now],
        players: [
          _tourPlayer(name: 'A1', team: 'Team A'),
          _tourPlayer(name: 'B1', team: 'Team B'),
        ],
      );
      final rounds = [
        _makeRound(
          id: 'round-1',
          tourId: 'team-tour',
          name: 'Round 1',
          startsAt: now.subtract(const Duration(hours: 2)),
        ),
      ];
      final games = [
        _makeGame(
          id: 'match-a-1',
          roundId: 'round-1',
          roundSlug: 'round-1',
          tourId: 'team-tour',
          boardNr: 1,
          lastMoveTime: now,
          players: [
            _player(name: 'A1', team: 'Team A', fideId: 1),
            _player(name: 'B1', team: 'Team B', fideId: 2),
          ],
        ),
        _makeGame(
          id: 'match-c-1',
          roundId: 'round-1',
          roundSlug: 'round-1',
          tourId: 'team-tour',
          boardNr: 2,
          lastMoveTime: now,
          players: [
            _player(name: 'C1', team: 'Team C', fideId: 3),
            _player(name: 'D1', team: 'Team D', fideId: 4),
          ],
        ),
        _makeGame(
          id: 'match-a-2',
          roundId: 'round-1',
          roundSlug: 'round-1',
          tourId: 'team-tour',
          boardNr: 3,
          lastMoveTime: now,
          players: [
            _player(name: 'A2', team: 'Team A', fideId: 5),
            _player(name: 'B2', team: 'Team B', fideId: 6),
          ],
        ),
      ];

      final snapshot = buildForYouEventGamesSnapshot(
        eventId: 'event-1',
        selectedTour: tour,
        eventTours: [tour],
        selectedTourRounds: rounds,
        roundsByTourId: {'team-tour': rounds},
        selectedTourGames: games,
        gamesByTourId: {'team-tour': games},
        liveRoundIds: const [],
        pinnedIds: const [],
      );

      expect(snapshot.visibleGames.map((game) => game.gameId), [
        'match-a-1',
        'match-a-2',
        'match-c-1',
      ]);
    });

    test('group event keeps matchup grouping when team name contains vs', () {
      final now = DateTime.now();
      final tour = _makeTour(
        id: 'team-tour',
        name: 'Team Championship',
        dates: [now.subtract(const Duration(days: 1)), now],
        players: [
          _tourPlayer(name: 'P1', team: 'Team vs Shadows'),
          _tourPlayer(name: 'P2', team: 'Rivals Club'),
        ],
      );
      final rounds = [
        _makeRound(
          id: 'round-1',
          tourId: 'team-tour',
          name: 'Round 1',
          startsAt: now.subtract(const Duration(hours: 2)),
        ),
      ];
      final games = [
        _makeGame(
          id: 'match-1-board-1',
          roundId: 'round-1',
          roundSlug: 'round-1',
          tourId: 'team-tour',
          boardNr: 1,
          lastMoveTime: now,
          players: [
            _player(name: 'A1', team: 'Team vs Shadows', fideId: 1),
            _player(name: 'B1', team: 'Rivals Club', fideId: 2),
          ],
        ),
        _makeGame(
          id: 'other-match',
          roundId: 'round-1',
          roundSlug: 'round-1',
          tourId: 'team-tour',
          boardNr: 2,
          lastMoveTime: now,
          players: [
            _player(name: 'C1', team: 'Knights', fideId: 3),
            _player(name: 'D1', team: 'Bishops', fideId: 4),
          ],
        ),
        _makeGame(
          id: 'match-1-board-2',
          roundId: 'round-1',
          roundSlug: 'round-1',
          tourId: 'team-tour',
          boardNr: 3,
          lastMoveTime: now,
          players: [
            _player(name: 'B2', team: 'Rivals Club', fideId: 5),
            _player(name: 'A2', team: 'Team vs Shadows', fideId: 6),
          ],
        ),
      ];

      final snapshot = buildForYouEventGamesSnapshot(
        eventId: 'event-1',
        selectedTour: tour,
        eventTours: [tour],
        selectedTourRounds: rounds,
        roundsByTourId: {'team-tour': rounds},
        selectedTourGames: games,
        gamesByTourId: {'team-tour': games},
        liveRoundIds: const [],
        pinnedIds: const [],
      );

      expect(snapshot.visibleGames.map((game) => game.gameId), [
        'match-1-board-1',
        'match-1-board-2',
        'other-match',
      ]);
    });

    test('multi-stage knockout includes sibling stages in Games-tab order', () {
      final now = DateTime.now();
      final stage1 = _makeTour(
        id: 'stage-1',
        name: 'World Cup | Round 1',
        dates: [
          now.subtract(const Duration(days: 2)),
          now.subtract(const Duration(days: 1)),
        ],
        format: 'Knockout',
      );
      final stage2 = _makeTour(
        id: 'stage-2',
        name: 'World Cup | Round 2',
        dates: [now.subtract(const Duration(hours: 8)), now],
        format: 'Knockout',
      );
      final stage1Rounds = [
        _makeRound(
          id: 'stage-1-round',
          tourId: 'stage-1',
          name: 'Stage 1',
          startsAt: now.subtract(const Duration(days: 2)),
        ),
      ];
      final stage2Rounds = [
        _makeRound(
          id: 'stage-2-round',
          tourId: 'stage-2',
          name: 'Stage 2',
          startsAt: now.subtract(const Duration(hours: 8)),
        ),
      ];
      final stage1Games = [
        _makeGame(
          id: 's1-g1',
          roundId: 'stage-1-round',
          roundSlug: 'game-1',
          tourId: 'stage-1',
          boardNr: 1,
          lastMoveTime: now.subtract(const Duration(days: 1)),
          players: [_player(name: 'A'), _player(name: 'B', fideId: 2)],
        ),
        _makeGame(
          id: 's1-g2',
          roundId: 'stage-1-round',
          roundSlug: 'game-2',
          tourId: 'stage-1',
          boardNr: 1,
          lastMoveTime: now.subtract(const Duration(days: 1)),
          players: [_player(name: 'A'), _player(name: 'B', fideId: 2)],
        ),
      ];
      final stage2Games = [
        _makeGame(
          id: 's2-g1',
          roundId: 'stage-2-round',
          roundSlug: 'game-1',
          tourId: 'stage-2',
          boardNr: 1,
          lastMoveTime: now.subtract(const Duration(hours: 2)),
          players: [
            _player(name: 'C', fideId: 3),
            _player(name: 'D', fideId: 4),
          ],
        ),
        _makeGame(
          id: 's2-g2',
          roundId: 'stage-2-round',
          roundSlug: 'game-2',
          tourId: 'stage-2',
          boardNr: 1,
          lastMoveTime: now.subtract(const Duration(hours: 1)),
          players: [
            _player(name: 'C', fideId: 3),
            _player(name: 'D', fideId: 4),
          ],
        ),
      ];

      final snapshot = buildForYouEventGamesSnapshot(
        eventId: 'event-1',
        selectedTour: stage2,
        eventTours: [stage1, stage2],
        selectedTourRounds: stage2Rounds,
        roundsByTourId: {'stage-1': stage1Rounds, 'stage-2': stage2Rounds},
        selectedTourGames: stage2Games,
        gamesByTourId: {'stage-1': stage1Games, 'stage-2': stage2Games},
        liveRoundIds: const [],
        pinnedIds: const [],
      );

      expect(snapshot.visibleGames.map((game) => game.gameId).take(4), [
        's2-g1',
        's2-g2',
        's1-g1',
        's1-g2',
      ]);
    });

    test('multi-stage knockout keeps sibling-stage pins in snapshot', () {
      final now = DateTime.now();
      final stage1 = _makeTour(
        id: 'stage-1',
        name: 'World Cup | Round 1',
        dates: [
          now.subtract(const Duration(days: 2)),
          now.subtract(const Duration(days: 1)),
        ],
        format: 'Knockout',
      );
      final stage2 = _makeTour(
        id: 'stage-2',
        name: 'World Cup | Round 2',
        dates: [now.subtract(const Duration(hours: 8)), now],
        format: 'Knockout',
      );
      final stage1Rounds = [
        _makeRound(
          id: 'stage-1-round',
          tourId: 'stage-1',
          name: 'Stage 1',
          startsAt: now.subtract(const Duration(days: 2)),
        ),
      ];
      final stage2Rounds = [
        _makeRound(
          id: 'stage-2-round',
          tourId: 'stage-2',
          name: 'Stage 2',
          startsAt: now.subtract(const Duration(hours: 8)),
        ),
      ];
      final stage1Games = [
        _makeGame(
          id: 's1-g1',
          roundId: 'stage-1-round',
          roundSlug: 'game-1',
          tourId: 'stage-1',
          boardNr: 1,
          lastMoveTime: now.subtract(const Duration(days: 1)),
          players: [_player(name: 'A'), _player(name: 'B', fideId: 2)],
        ),
        _makeGame(
          id: 's1-g2',
          roundId: 'stage-1-round',
          roundSlug: 'game-2',
          tourId: 'stage-1',
          boardNr: 1,
          lastMoveTime: now.subtract(const Duration(days: 1)),
          players: [_player(name: 'A'), _player(name: 'B', fideId: 2)],
        ),
      ];
      final stage2Games = [
        _makeGame(
          id: 's2-g1',
          roundId: 'stage-2-round',
          roundSlug: 'game-1',
          tourId: 'stage-2',
          boardNr: 1,
          lastMoveTime: now.subtract(const Duration(hours: 2)),
          players: [
            _player(name: 'C', fideId: 3),
            _player(name: 'D', fideId: 4),
          ],
        ),
        _makeGame(
          id: 's2-g2',
          roundId: 'stage-2-round',
          roundSlug: 'game-2',
          tourId: 'stage-2',
          boardNr: 1,
          lastMoveTime: now.subtract(const Duration(hours: 1)),
          players: [
            _player(name: 'C', fideId: 3),
            _player(name: 'D', fideId: 4),
          ],
        ),
      ];

      final snapshot = buildForYouEventGamesSnapshot(
        eventId: 'event-1',
        selectedTour: stage2,
        eventTours: [stage1, stage2],
        selectedTourRounds: stage2Rounds,
        roundsByTourId: {'stage-1': stage1Rounds, 'stage-2': stage2Rounds},
        selectedTourGames: stage2Games,
        gamesByTourId: {'stage-1': stage1Games, 'stage-2': stage2Games},
        liveRoundIds: const [],
        pinnedIds: const ['s1-g2'],
      );

      expect(snapshot.pinnedIds, ['s1-g2']);
      expect(
        snapshot.visibleGames.map((game) => game.gameId).take(4),
        containsAll(['s2-g1', 's2-g2', 's1-g1', 's1-g2']),
      );
    });

    test(
      'pins are applied with Games-tab priority inside the selected tour',
      () {
        final now = DateTime.now();
        final tour = _makeTour(
          id: 'tour-1',
          name: 'Pinned Event',
          dates: [now.subtract(const Duration(days: 1)), now],
        );
        final rounds = [
          _makeRound(
            id: 'round-1',
            tourId: 'tour-1',
            name: 'Round 1',
            startsAt: now.subtract(const Duration(hours: 2)),
          ),
        ];
        final games = [
          _makeGame(
            id: 'g1',
            roundId: 'round-1',
            roundSlug: 'round-1',
            tourId: 'tour-1',
            boardNr: 1,
            lastMoveTime: now,
            players: [_player(name: 'A'), _player(name: 'B', fideId: 2)],
          ),
          _makeGame(
            id: 'g2',
            roundId: 'round-1',
            roundSlug: 'round-1',
            tourId: 'tour-1',
            boardNr: 2,
            lastMoveTime: now,
            players: [
              _player(name: 'C', fideId: 3),
              _player(name: 'D', fideId: 4),
            ],
          ),
          _makeGame(
            id: 'g3',
            roundId: 'round-1',
            roundSlug: 'round-1',
            tourId: 'tour-1',
            boardNr: 3,
            lastMoveTime: now,
            players: [
              _player(name: 'E', fideId: 5),
              _player(name: 'F', fideId: 6),
            ],
          ),
        ];

        final snapshot = buildForYouEventGamesSnapshot(
          eventId: 'event-1',
          selectedTour: tour,
          eventTours: [tour],
          selectedTourRounds: rounds,
          roundsByTourId: {'tour-1': rounds},
          selectedTourGames: games,
          gamesByTourId: {'tour-1': games},
          liveRoundIds: const [],
          pinnedIds: const ['g3'],
        );

        expect(snapshot.visibleGames.first.gameId, 'g3');
        expect(snapshot.pinnedIds, ['g3']);
      },
    );

    test('returns only available visible games when fewer than four exist', () {
      final now = DateTime.now();
      final tour = _makeTour(
        id: 'tour-1',
        name: 'Small Event',
        dates: [now.subtract(const Duration(days: 1)), now],
      );
      final rounds = [
        _makeRound(
          id: 'round-1',
          tourId: 'tour-1',
          name: 'Round 1',
          startsAt: now.subtract(const Duration(hours: 2)),
        ),
      ];
      final games = [
        _makeGame(
          id: 'g1',
          roundId: 'round-1',
          roundSlug: 'round-1',
          tourId: 'tour-1',
          boardNr: 1,
          lastMoveTime: now,
          players: [_player(name: 'A'), _player(name: 'B', fideId: 2)],
        ),
        _makeGame(
          id: 'g2',
          roundId: 'round-1',
          roundSlug: 'round-1',
          tourId: 'tour-1',
          boardNr: 2,
          lastMoveTime: now,
          players: [
            _player(name: 'C', fideId: 3),
            _player(name: 'D', fideId: 4),
          ],
        ),
      ];

      final snapshot = buildForYouEventGamesSnapshot(
        eventId: 'event-1',
        selectedTour: tour,
        eventTours: [tour],
        selectedTourRounds: rounds,
        roundsByTourId: {'tour-1': rounds},
        selectedTourGames: games,
        gamesByTourId: {'tour-1': games},
        liveRoundIds: const [],
        pinnedIds: const [],
      );

      expect(snapshot.visibleGames, hasLength(2));
    });
  });
}
