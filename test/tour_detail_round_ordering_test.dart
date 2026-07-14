import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_ordering.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:flutter_test/flutter_test.dart';

GamesAppBarModel _round({
  required String id,
  required String name,
  required DateTime? startsAt,
  required RoundStatus status,
}) {
  return GamesAppBarModel(
    id: id,
    name: name,
    startsAt: startsAt,
    roundStatus: status,
  );
}

List<String> _ids(List<GamesAppBarModel> rounds) =>
    rounds.map((round) => round.id).toList(growable: false);

void main() {
  group('GamesAppBarModel.status', () {
    test('treats backend live ids as live even when startsAt is missing', () {
      final status = GamesAppBarModel.status(
        currentId: 'round-3',
        startsAt: null,
        liveRound: const ['round-3'],
      );

      expect(status, RoundStatus.live);
    });

    test('marks a synthetic stage live from any represented source round', () {
      final status = roundStatusForLiveSourceRounds(
        model: GamesAppBarModel(
          id: 'knockout-stage-tour-round-3',
          name: 'Round 3',
          startsAt: null,
          roundStatus: RoundStatus.upcoming,
          sourceRoundIds: const ['round-31', 'round-32'],
        ),
        liveRoundIds: const ['round-32'],
      );

      expect(status, RoundStatus.live);
    });
  });

  group('sortRoundsForDisplay', () {
    test('keeps all future rounds in ascending order', () {
      final now = DateTime(2026, 3, 29, 10);
      final rounds = [
        _round(
          id: 'r3',
          name: 'Round 3',
          startsAt: now.add(const Duration(days: 2)),
          status: RoundStatus.upcoming,
        ),
        _round(
          id: 'r1',
          name: 'Round 1',
          startsAt: now.add(const Duration(hours: 6)),
          status: RoundStatus.upcoming,
        ),
        _round(
          id: 'r2',
          name: 'Round 2',
          startsAt: now.add(const Duration(days: 1)),
          status: RoundStatus.upcoming,
        ),
      ];

      final sorted = sortRoundsForDisplay(
        rounds,
        resolveDate: (round) => round.startsAt,
        now: now,
      );

      expect(_ids(sorted), ['r1', 'r2', 'r3']);
    });

    test(
      'orders future rounds by round number when start times are missing',
      () {
        final now = DateTime(2026, 3, 29, 10);
        final rounds = [
          _round(
            id: 'r10',
            name: 'Round 10',
            startsAt: null,
            status: RoundStatus.upcoming,
          ),
          _round(
            id: 'r2',
            name: 'Round 2',
            startsAt: null,
            status: RoundStatus.upcoming,
          ),
          _round(
            id: 'r1',
            name: 'Round 1',
            startsAt: null,
            status: RoundStatus.upcoming,
          ),
        ];

        final sorted = sortRoundsForDisplay(
          rounds,
          resolveDate: (round) => round.startsAt,
          now: now,
        );

        expect(_ids(sorted), ['r1', 'r2', 'r10']);
      },
    );

    test(
      'promotes next round inside one hour after every latest-round board finishes',
      () {
        final now = DateTime(2026, 3, 30, 16);
        final rounds = [
          _round(
            id: 'r1',
            name: 'Round 1',
            startsAt: now.subtract(const Duration(hours: 4)),
            status: RoundStatus.completed,
          ),
          _round(
            id: 'r2',
            name: 'Round 2',
            startsAt: now.add(const Duration(minutes: 59)),
            status: RoundStatus.upcoming,
          ),
          _round(
            id: 'r3',
            name: 'Round 3',
            startsAt: now.add(const Duration(days: 1)),
            status: RoundStatus.upcoming,
          ),
          _round(
            id: 'r4',
            name: 'Round 4',
            startsAt: now.add(const Duration(days: 2)),
            status: RoundStatus.upcoming,
          ),
        ];

        final sorted = sortRoundsForDisplay(
          rounds,
          resolveDate: (round) => round.startsAt,
          isRoundFullyPlayed: (round) => round.id == 'r1',
          now: now,
        );

        expect(_ids(sorted), ['r2', 'r1', 'r3', 'r4']);
      },
    );

    test(
      'does not promote the next round while a latest-round board is open',
      () {
        final now = DateTime(2026, 3, 30, 16);
        final rounds = [
          _round(
            id: 'r1',
            name: 'Round 1',
            startsAt: now.subtract(const Duration(hours: 4)),
            status: RoundStatus.ongoing,
          ),
          _round(
            id: 'r2',
            name: 'Round 2',
            startsAt: now.add(const Duration(minutes: 30)),
            status: RoundStatus.upcoming,
          ),
          _round(
            id: 'r3',
            name: 'Round 3',
            startsAt: now.add(const Duration(days: 1)),
            status: RoundStatus.upcoming,
          ),
        ];

        final sorted = sortRoundsForDisplay(
          rounds,
          resolveDate: (round) => round.startsAt,
          isRoundFullyPlayed: (_) => false,
          now: now,
        );

        expect(_ids(sorted), ['r1', 'r2', 'r3']);
      },
    );

    test('promotes the next round at exactly one hour', () {
      final now = DateTime(2026, 3, 30, 16);
      final rounds = [
        _round(
          id: 'r1',
          name: 'Round 1',
          startsAt: now.subtract(const Duration(hours: 4)),
          status: RoundStatus.completed,
        ),
        _round(
          id: 'r2',
          name: 'Round 2',
          startsAt: now.add(const Duration(hours: 1)),
          status: RoundStatus.upcoming,
        ),
      ];

      final sorted = sortRoundsForDisplay(
        rounds,
        resolveDate: (round) => round.startsAt,
        isRoundFullyPlayed: (_) => true,
        now: now,
      );

      expect(_ids(sorted), ['r2', 'r1']);
    });

    test(
      'does not promote while any previously started round is unfinished',
      () {
        final now = DateTime(2026, 3, 30, 16);
        final rounds = [
          _round(
            id: 'r1',
            name: 'Round 1',
            startsAt: now.subtract(const Duration(days: 1)),
            status: RoundStatus.ongoing,
          ),
          _round(
            id: 'r2',
            name: 'Round 2',
            startsAt: now.subtract(const Duration(hours: 4)),
            status: RoundStatus.completed,
          ),
          _round(
            id: 'r3',
            name: 'Round 3',
            startsAt: now.add(const Duration(minutes: 30)),
            status: RoundStatus.upcoming,
          ),
        ];

        final sorted = sortRoundsForDisplay(
          rounds,
          resolveDate: (round) => round.startsAt,
          isRoundFullyPlayed: (round) => round.id == 'r2',
          now: now,
        );

        expect(_ids(sorted), ['r2', 'r1', 'r3']);
      },
    );

    test(
      'keeps started rounds descending and future rounds ascending below them',
      () {
        final now = DateTime(2026, 3, 31, 16);
        final rounds = [
          _round(
            id: 'r1',
            name: 'Round 1',
            startsAt: now.subtract(const Duration(days: 2)),
            status: RoundStatus.completed,
          ),
          _round(
            id: 'r2',
            name: 'Round 2',
            startsAt: now.subtract(const Duration(days: 1)),
            status: RoundStatus.completed,
          ),
          _round(
            id: 'r3',
            name: 'Round 3',
            startsAt: now.add(const Duration(minutes: 90)),
            status: RoundStatus.upcoming,
          ),
          _round(
            id: 'r4',
            name: 'Round 4',
            startsAt: now.add(const Duration(days: 1)),
            status: RoundStatus.upcoming,
          ),
        ];

        final sorted = sortRoundsForDisplay(
          rounds,
          resolveDate: (round) => round.startsAt,
          now: now,
        );

        expect(_ids(sorted), ['r2', 'r1', 'r3', 'r4']);
      },
    );

    test('ends with latest round first and all prior rounds descending', () {
      final now = DateTime(2026, 4, 12, 16);
      final rounds = [
        for (var i = 1; i <= 4; i++)
          _round(
            id: 'r$i',
            name: 'Round $i',
            startsAt: DateTime(2026, 4, 8 + i, 12),
            status: RoundStatus.completed,
          ),
      ];

      final sorted = sortRoundsForDisplay(
        rounds,
        resolveDate: (round) => round.startsAt,
        now: now,
      );

      expect(_ids(sorted), ['r4', 'r3', 'r2', 'r1']);
    });

    test('orders started generic rounds by round number when dates jump', () {
      final now = DateTime(2026, 4, 24, 16);
      final rounds = [
        _round(
          id: 'r10',
          name: 'Round 10',
          startsAt: DateTime(2026, 3, 22, 9, 15),
          status: RoundStatus.completed,
        ),
        _round(
          id: 'r11',
          name: 'Round 11',
          startsAt: DateTime(2026, 1, 10, 13, 15),
          status: RoundStatus.completed,
        ),
        _round(
          id: 'r12',
          name: 'Round 12',
          startsAt: DateTime(2026, 1, 11, 9, 15),
          status: RoundStatus.completed,
        ),
        _round(
          id: 'r13',
          name: 'Round 13',
          startsAt: DateTime(2026, 4, 24, 14, 15),
          status: RoundStatus.live,
        ),
      ];

      final sorted = sortRoundsForDisplay(
        rounds,
        resolveDate: (round) => round.startsAt,
        now: now,
      );

      expect(_ids(sorted), ['r13', 'r12', 'r11', 'r10']);
    });

    test('keeps a live generic round first when its start time is missing', () {
      final now = DateTime(2026, 6, 16, 15, 30);
      final rounds = [
        _round(
          id: 'r1',
          name: 'Round 1',
          startsAt: now.subtract(const Duration(minutes: 30)),
          status: RoundStatus.completed,
        ),
        _round(
          id: 'r2',
          name: 'Round 2',
          startsAt: now.subtract(const Duration(minutes: 15)),
          status: RoundStatus.completed,
        ),
        _round(
          id: 'r3',
          name: 'Round 3',
          startsAt: null,
          status: RoundStatus.live,
        ),
      ];

      final sorted = sortRoundsForDisplay(
        rounds,
        resolveDate: (round) => round.startsAt,
        now: now,
      );

      expect(_ids(sorted), ['r3', 'r2', 'r1']);
    });
  });

  group('pickPreferredRoundForSelection', () {
    test('selects the earliest round before an event begins', () {
      final now = DateTime(2026, 3, 30, 16);
      final rounds = [
        _round(
          id: 'r3',
          name: 'Round 3',
          startsAt: now.add(const Duration(hours: 6)),
          status: RoundStatus.upcoming,
        ),
        _round(
          id: 'r1',
          name: 'Round 1',
          startsAt: now.add(const Duration(minutes: 30)),
          status: RoundStatus.upcoming,
        ),
        _round(
          id: 'r2',
          name: 'Round 2',
          startsAt: now.add(const Duration(hours: 3)),
          status: RoundStatus.upcoming,
        ),
      ];

      final selected = pickPreferredRoundForSelection(
        rounds,
        resolveDate: (round) => round.startsAt,
        hasGames: (_) => true,
        now: now,
      );

      expect(selected?.id, 'r1');
    });

    test(
      'selects the lowest upcoming round when event start times are missing',
      () {
        final rounds = [
          _round(
            id: 'r10',
            name: 'Round 10',
            startsAt: null,
            status: RoundStatus.upcoming,
          ),
          _round(
            id: 'r2',
            name: 'Round 2',
            startsAt: null,
            status: RoundStatus.upcoming,
          ),
          _round(
            id: 'r1',
            name: 'Round 1',
            startsAt: null,
            status: RoundStatus.upcoming,
          ),
        ];

        final selected = pickPreferredRoundForSelection(
          rounds,
          resolveDate: (round) => round.startsAt,
          hasGames: (_) => true,
        );

        expect(selected?.id, 'r1');
      },
    );

    test(
      'selects next round inside one hour when latest round is fully played',
      () {
        final now = DateTime(2026, 3, 30, 16);
        final rounds = [
          _round(
            id: 'r1',
            name: 'Round 1',
            startsAt: now.subtract(const Duration(hours: 4)),
            status: RoundStatus.completed,
          ),
          _round(
            id: 'r2',
            name: 'Round 2',
            startsAt: now.add(const Duration(minutes: 59)),
            status: RoundStatus.upcoming,
          ),
          _round(
            id: 'r3',
            name: 'Round 3',
            startsAt: now.add(const Duration(days: 1)),
            status: RoundStatus.upcoming,
          ),
        ];

        final selected = pickPreferredRoundForSelection(
          rounds,
          resolveDate: (round) => round.startsAt,
          hasGames: (_) => true,
          isRoundFullyPlayed: (round) => round.id == 'r1',
          now: now,
        );

        expect(selected?.id, 'r2');
      },
    );

    test('returns null when hasGames filters out every round', () {
      final now = DateTime(2026, 3, 30, 16);
      final rounds = [
        _round(
          id: 'r1',
          name: 'Round 1',
          startsAt: now.subtract(const Duration(hours: 4)),
          status: RoundStatus.completed,
        ),
        _round(
          id: 'r2',
          name: 'Round 2',
          startsAt: now.add(const Duration(hours: 1)),
          status: RoundStatus.upcoming,
        ),
      ];

      final selected = pickPreferredRoundForSelection(
        rounds,
        resolveDate: (round) => round.startsAt,
        hasGames: (_) => false,
        now: now,
      );

      expect(selected, isNull);
    });

    test(
      'prefers the most recent live round when multiple live rounds exist',
      () {
        final now = DateTime(2026, 3, 30, 16);
        final rounds = [
          _round(
            id: 'r1',
            name: 'Round 1',
            startsAt: now.subtract(const Duration(hours: 3)),
            status: RoundStatus.live,
          ),
          _round(
            id: 'r2',
            name: 'Round 2',
            startsAt: now.subtract(const Duration(hours: 1)),
            status: RoundStatus.live,
          ),
          _round(
            id: 'r3',
            name: 'Round 3',
            startsAt: now.add(const Duration(hours: 2)),
            status: RoundStatus.upcoming,
          ),
        ];

        final selected = pickPreferredRoundForSelection(
          rounds,
          resolveDate: (round) => round.startsAt,
          hasGames: (_) => true,
          now: now,
        );

        expect(selected?.id, 'r2');
      },
    );

    test('prefers highest generic started round when round dates jump', () {
      final now = DateTime(2026, 4, 24, 16);
      final rounds = [
        _round(
          id: 'r10',
          name: 'Round 10',
          startsAt: DateTime(2026, 3, 22, 9, 15),
          status: RoundStatus.completed,
        ),
        _round(
          id: 'r11',
          name: 'Round 11',
          startsAt: DateTime(2026, 1, 10, 13, 15),
          status: RoundStatus.completed,
        ),
        _round(
          id: 'r12',
          name: 'Round 12',
          startsAt: DateTime(2026, 1, 11, 9, 15),
          status: RoundStatus.completed,
        ),
      ];

      final selected = pickPreferredRoundForSelection(
        rounds,
        resolveDate: (round) => round.startsAt,
        hasGames: (_) => true,
        now: now,
      );

      expect(selected?.id, 'r12');
    });

    test('selects a live round even when its start time is missing', () {
      final now = DateTime(2026, 6, 16, 15, 30);
      final rounds = [
        _round(
          id: 'r1',
          name: 'Round 1',
          startsAt: now.subtract(const Duration(minutes: 30)),
          status: RoundStatus.completed,
        ),
        _round(
          id: 'r2',
          name: 'Round 2',
          startsAt: now.subtract(const Duration(minutes: 15)),
          status: RoundStatus.completed,
        ),
        _round(
          id: 'r3',
          name: 'Round 3',
          startsAt: null,
          status: RoundStatus.live,
        ),
      ];

      final selected = pickPreferredRoundForSelection(
        rounds,
        resolveDate: (round) => round.startsAt,
        hasGames: (_) => true,
        now: now,
      );

      expect(selected?.id, 'r3');
    });
  });

  group('selectRoundIdAfterLiveRoundsChanged', () {
    test('switches from the current auto-selected round to the live round', () {
      final now = DateTime(2026, 6, 16, 19);
      final selected = selectRoundIdAfterLiveRoundsChanged(
        models: [
          _round(
            id: 'round-1',
            name: 'Round 1',
            startsAt: now.subtract(const Duration(minutes: 20)),
            status: RoundStatus.completed,
          ),
          _round(
            id: 'round-2',
            name: 'Round 2',
            startsAt: now,
            status: RoundStatus.live,
          ),
        ],
        currentSelectedId: 'round-1',
        stickySelection: null,
        hasGames: (_) => true,
        resolveDate: (round) => round.startsAt,
      );

      expect(selected, 'round-2');
    });

    test('does not override an explicit user-selected round', () {
      final now = DateTime(2026, 6, 16, 19);
      final selected = selectRoundIdAfterLiveRoundsChanged(
        models: [
          _round(
            id: 'round-1',
            name: 'Round 1',
            startsAt: now.subtract(const Duration(minutes: 20)),
            status: RoundStatus.completed,
          ),
          _round(
            id: 'round-2',
            name: 'Round 2',
            startsAt: now,
            status: RoundStatus.live,
          ),
        ],
        currentSelectedId: 'round-1',
        stickySelection: (id: 'round-1', userSelected: true),
        hasGames: (_) => true,
        resolveDate: (round) => round.startsAt,
      );

      expect(selected, 'round-1');
    });

    test('keeps the current round until the live round has games', () {
      final now = DateTime(2026, 6, 16, 19);
      final selected = selectRoundIdAfterLiveRoundsChanged(
        models: [
          _round(
            id: 'round-1',
            name: 'Round 1',
            startsAt: now.subtract(const Duration(minutes: 20)),
            status: RoundStatus.completed,
          ),
          _round(
            id: 'round-2',
            name: 'Round 2',
            startsAt: now,
            status: RoundStatus.live,
          ),
        ],
        currentSelectedId: 'round-1',
        stickySelection: null,
        hasGames: (roundId) => roundId == 'round-1',
        resolveDate: (round) => round.startsAt,
      );

      expect(selected, 'round-1');
    });
  });

  group('groupSingleTourKnockoutSourceRounds', () {
    test('uses the sole resolved descriptor instead of a generic fallback', () {
      final sourceRounds = [
        _sourceRound('r3-1', 'Round 3.1', 'round-31', day: 1),
        _sourceRound('r3-2', 'Round 3.2', 'round-32', day: 2),
      ];
      final groups = groupSingleTourKnockoutSourceRounds(
        sourceRounds: sourceRounds,
        roundModels: [
          _round(
            id: 'r3-1',
            name: 'Round 3.1',
            startsAt: DateTime.utc(2026, 1, 1),
            status: RoundStatus.completed,
          ),
          _round(
            id: 'r3-2',
            name: 'Round 3.2',
            startsAt: DateTime.utc(2026, 1, 2),
            status: RoundStatus.upcoming,
          ),
        ],
        gameRoundIds: const ['r3-1'],
        tourName: 'Turkish Cup',
      );

      expect(groups, hasLength(1));
      expect(groups.single.stage.label, 'Round 3');
      expect(groups.single.sourceRounds.map((round) => round.id), [
        'r3-1',
        'r3-2',
      ]);
      expect(groups.single.gameRoundIds, {'r3-1'});
    });

    test('includes a published next stage with no games', () {
      final sourceRounds = [
        _sourceRound('r3-1', 'Round 3.1', 'round-31', day: 1),
        _sourceRound('r4-1', 'Round 4.1', 'round-41', day: 3),
      ];
      final groups = groupSingleTourKnockoutSourceRounds(
        sourceRounds: sourceRounds,
        roundModels: [
          _round(
            id: 'r3-1',
            name: 'Round 3.1',
            startsAt: DateTime.utc(2026, 1, 1),
            status: RoundStatus.completed,
          ),
          _round(
            id: 'r4-1',
            name: 'Round 4.1',
            startsAt: DateTime.utc(2026, 1, 3),
            status: RoundStatus.upcoming,
          ),
        ],
        gameRoundIds: const ['r3-1'],
        tourName: 'Turkish Cup',
      );

      expect(groups.map((group) => group.stage.label), ['Round 3', 'Round 4']);
      expect(groups.first.hasGames, isTrue);
      expect(groups.last.hasGames, isFalse);
      expect(groups.last.sourceRounds.single.id, 'r4-1');
    });

    test('attaches an unresolved leg only when one stage is trustworthy', () {
      final oneStageRounds = [
        _sourceRound('r3-1', 'Round 3.1', 'round-31', day: 1),
        _sourceRound('arm', 'Armageddon', 'armageddon', day: 2),
      ];
      final oneStageGroups = groupSingleTourKnockoutSourceRounds(
        sourceRounds: oneStageRounds,
        roundModels: [
          _round(
            id: 'r3-1',
            name: 'Round 3.1',
            startsAt: DateTime.utc(2026, 1, 1),
            status: RoundStatus.completed,
          ),
          _round(
            id: 'arm',
            name: 'Armageddon',
            startsAt: DateTime.utc(2026, 1, 2),
            status: RoundStatus.upcoming,
          ),
        ],
        gameRoundIds: const ['r3-1', 'arm'],
        tourName: 'Turkish Cup',
      );

      expect(oneStageGroups.single.sourceRounds.map((round) => round.id), [
        'r3-1',
        'arm',
      ]);

      final multipleStageGroups = groupSingleTourKnockoutSourceRounds(
        sourceRounds: [
          ...oneStageRounds,
          _sourceRound('r4-1', 'Round 4.1', 'round-41', day: 3),
        ],
        roundModels: [
          ...oneStageGroups.single.roundModels,
          _round(
            id: 'r4-1',
            name: 'Round 4.1',
            startsAt: DateTime.utc(2026, 1, 3),
            status: RoundStatus.upcoming,
          ),
        ],
        gameRoundIds: const ['r3-1', 'arm'],
        tourName: 'Turkish Cup',
      );

      expect(multipleStageGroups, hasLength(3));
      final otherPairings = multipleStageGroups.singleWhere(
        (group) => group.stage.key == 'other-pairings',
      );
      expect(otherPairings.stage.label, 'Other pairings');
      expect(otherPairings.sourceRounds.single.id, 'arm');
      expect(otherPairings.hasGames, isTrue);
    });
  });

  group('shouldIncludeNamedKnockoutStageTour', () {
    test(
      'includes a format-less named sibling while its detection is pending',
      () {
        expect(
          shouldIncludeNamedKnockoutStageTour(
            _sourceTour('semi', 'Open Cup | Semifinals'),
            detectedTeamEvent: false,
          ),
          isTrue,
        );
      },
    );

    test('excludes explicit team and regular-format stages', () {
      expect(
        shouldIncludeNamedKnockoutStageTour(
          _sourceTour(
            'team-qf',
            'Team Cup | Quarterfinals',
            format: '16-team Knockout',
          ),
          detectedTeamEvent: true,
        ),
        isFalse,
      );
      expect(
        shouldIncludeNamedKnockoutStageTour(
          _sourceTour(
            'league-final',
            'National League | Finals',
            format: 'Round Robin League',
          ),
          detectedTeamEvent: false,
        ),
        isFalse,
      );
    });
  });

  group('unknown game round publication race', () {
    test('first game publication is unknown before any round row exists', () {
      expect(
        unknownGameRoundIds(
          gameRoundIds: const ['round-31'],
          displayRounds: const <GamesAppBarModel>[],
        ),
        {'round-31'},
      );
    });

    test('retries stale-success loads until the source round is published', () {
      final staleRounds = [
        _round(
          id: 'knockout-stage-tour-round-3',
          name: 'Round 3',
          startsAt: null,
          status: RoundStatus.live,
        ).copyWith(sourceRoundIds: const ['round-31']),
      ];
      expect(
        unknownGameRoundIds(
          gameRoundIds: const ['round-31', 'round-32'],
          displayRounds: staleRounds,
        ),
        {'round-32'},
      );

      final publishedRounds = [
        staleRounds.single.copyWith(
          sourceRoundIds: const ['round-31', 'round-32'],
        ),
      ];
      expect(
        unknownGameRoundIds(
          gameRoundIds: const ['round-32'],
          displayRounds: publishedRounds,
        ),
        isEmpty,
      );
    });

    test('retry delay is exponentially backed off and bounded', () {
      expect(unknownGameRoundRetryDelay(0), const Duration(milliseconds: 250));
      expect(unknownGameRoundRetryDelay(3), const Duration(seconds: 2));
      expect(unknownGameRoundRetryDelay(99), const Duration(seconds: 4));
    });
  });
}

Round _sourceRound(String id, String name, String slug, {required int day}) =>
    Round(
      id: id,
      slug: slug,
      tourId: 'tour',
      tourSlug: 'tour',
      name: name,
      createdAt: DateTime.utc(2026, 1, day),
      startsAt: DateTime.utc(2026, 1, day),
      url: 'https://lichess.org/broadcast/tour/$slug/$id',
    );

Tour _sourceTour(String id, String name, {String? format}) => Tour(
  id: id,
  name: name,
  slug: id,
  info: TourInfo(format: format),
  createdAt: DateTime.utc(2026, 1, 1),
  url: 'https://lichess.org/broadcast/$id',
  tier: 1,
  dates: [DateTime.utc(2026, 1, 1)],
  players: const [],
  groupBroadcastId: 'broadcast',
);
