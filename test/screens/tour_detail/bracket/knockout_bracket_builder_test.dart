import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/screens/tour_detail/bracket/utils/knockout_bracket_builder.dart';
import 'package:chessever2/screens/tour_detail/bracket/utils/knockout_stage_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('knockout stage parsing', () {
    test('parses empty, inline, and pipe-separated category lanes', () {
      final worldCup = parseKnockoutTourStageDescriptor(
        'FIDE World Cup 2025 | Round 3',
      );
      expect(worldCup.eventRoot, 'FIDE World Cup 2025');
      expect(worldCup.lane, isEmpty);
      expect(worldCup.stage?.label, 'Round 3');

      final azerbaijan = parseKnockoutTourStageDescriptor(
        'Azerbaijan Chess Championship 2026 | Men Quarterfinals',
      );
      expect(azerbaijan.lane, 'men');
      expect(azerbaijan.stage?.label, 'Quarterfinals');

      final french = parseKnockoutTourStageDescriptor(
        'French Chess Championship 2025 | Women | Finals',
      );
      expect(french.lane, 'women');
      expect(french.stage?.label, 'Finals');
    });

    test(
      'resolves logical legs without inventing generic stage boundaries',
      () {
        expect(
          resolveLogicalKnockoutStage('Round 3.1', 'round-31')?.key,
          'round-3',
        );
        expect(
          resolveLogicalKnockoutStage('Round 3.2', 'round-32')?.key,
          'round-3',
        );
        expect(
          resolveLogicalKnockoutStage(
            'Round 3 | Tiebreaks',
            'round-3-tiebreaks',
          )?.key,
          'round-3',
        );
        expect(
          resolveLogicalKnockoutStage(
            'Quarterfinals | Game 2',
            'quarter-finals--game-2',
          )?.label,
          'Quarterfinals',
        );
        expect(
          resolveLogicalKnockoutStage('', 'quarter-finals--game-1')?.key,
          'quarterfinals',
        );
        expect(
          resolveLogicalKnockoutStage(
            'Game 1',
            'game-1',
            tourName: 'Invitational | Semifinals',
          )?.key,
          'semifinals',
        );
        expect(resolveLogicalKnockoutStage('Game 1', 'game-1'), isNull);
      },
    );

    test('filters Azerbaijan sibling tours to the selected lane', () {
      final menQuarter = _tour(
        'men-qf',
        'Azerbaijan Chess Championship 2026 | Men Quarterfinals',
        day: 1,
      );
      final womenQuarter = _tour(
        'women-qf',
        'Azerbaijan Chess Championship 2026 | Women Quarterfinals',
        day: 1,
      );
      final menSemi = _tour(
        'men-sf',
        'Azerbaijan Chess Championship 2026 | Men Semifinals',
        day: 2,
      );
      final otherEvent = _tour(
        'other',
        'Another Championship | Men Finals',
        day: 3,
      );

      expect(
        filterKnockoutSiblingTours(
          selectedTour: menQuarter,
          siblingTours: [womenQuarter, menSemi, otherEvent],
        ).map((tour) => tour.id),
        ['men-qf', 'men-sf'],
      );
    });

    test('requires sibling stages to share the group and be individual', () {
      final selected = _tour(
        'selected',
        'Cup | Quarterfinals',
        day: 1,
        groupId: 'cup-group',
      );
      final valid = _tour(
        'valid',
        'Cup | Semifinals',
        day: 2,
        groupId: 'cup-group',
      );
      final missingGroup = _tour(
        'missing-group',
        'Cup | Finals',
        day: 3,
        groupId: null,
      );
      final team = _tour(
        'team',
        'Cup | Finals',
        day: 3,
        groupId: 'cup-group',
        format: '16-team Knockout',
      );
      final swiss = _tour(
        'swiss',
        'Cup | Finals',
        day: 3,
        groupId: 'cup-group',
        format: 'Swiss',
      );
      final ungroupedSelected = _tour(
        'ungrouped-selected',
        'Ungrouped Cup | Semifinals',
        day: 1,
        groupId: null,
      );
      final ungroupedFinal = _tour(
        'ungrouped-final',
        'Ungrouped Cup | Finals',
        day: 2,
        groupId: null,
      );

      expect(
        filterKnockoutSiblingTours(
          selectedTour: selected,
          siblingTours: [missingGroup, team, swiss, valid],
        ).map((tour) => tour.id),
        ['selected', 'valid'],
      );
      expect(
        filterKnockoutSiblingTours(
          selectedTour: ungroupedSelected,
          siblingTours: [ungroupedFinal],
        ).map((tour) => tour.id),
        ['ungrouped-selected'],
      );
    });
  });

  group('knockout bracket builder', () {
    test('orders FIDE World Cup sibling stage tours chronologically', () {
      final finalTour = _tour('final', 'FIDE World Cup 2025 | Finals', day: 20);
      final round3 = _tour('r3', 'FIDE World Cup 2025 | Round 3', day: 3);
      final semifinal = _tour(
        'semi',
        'FIDE World Cup 2025 | Semifinals',
        day: 12,
      );

      final bracket = buildKnockoutBracket(
        selectedTour: round3,
        siblingTours: [finalTour, semifinal],
        roundsByTourId: {
          'r3': [_round('r3-leg', 'r3', 'Game 1', 'game-1', day: 3)],
          'semi': [_round('semi-leg', 'semi', 'Game 1', 'game-1', day: 12)],
          'final': [_round('final-leg', 'final', 'Game 1', 'game-1', day: 20)],
        },
        gamesByTourId: {
          'r3': [_game('r3-game', 'r3-leg', 'r3', 'Alpha', 'Beta', '1-0')],
          'semi': [
            _game('semi-game', 'semi-leg', 'semi', 'Alpha', 'Gamma', '1-0'),
          ],
          'final': [
            _game('final-game', 'final-leg', 'final', 'Alpha', 'Delta', '*'),
          ],
        },
      );

      expect(bracket.stages.map((stage) => stage.label), [
        'Round 3',
        'Semifinals',
        'Finals',
      ]);
      expect(bracket.selectedStageKey, bracket.stages.first.key);
      expect(bracket.edges, hasLength(2));
    });

    test('includes one named sibling stage beside a generic selected tour', () {
      final selected = _tour('root', 'Open Cup', day: 1);
      final finalTour = _tour('final', 'Open Cup | Finals', day: 4);
      final bracket = buildKnockoutBracket(
        selectedTour: selected,
        siblingTours: [finalTour],
        roundsByTourId: {
          'root': [
            _round('r3', 'root', 'Round 3.1', 'round-31', day: 1),
            _round('r4', 'root', 'Round 4.1', 'round-41', day: 2),
          ],
          'final': [_round('final-leg', 'final', 'Game 1', 'game-1', day: 4)],
        },
        gamesByTourId: {
          'root': [
            _game('r3-game', 'r3', 'root', 'Alpha', 'Beta', '1-0'),
            _game('r4-game', 'r4', 'root', 'Alpha', 'Gamma', '*'),
          ],
          'final': [
            _game('final-game', 'final-leg', 'final', 'Alpha', 'Delta', '*'),
          ],
        },
        liveTourIds: const {'root'},
        liveRoundIds: const {'r4'},
      );

      expect(bracket.stages.map((stage) => stage.label), [
        'Round 3',
        'Round 4',
        'Finals',
      ]);
      expect(bracket.stages.first.sourceTourIds, ['root']);
      expect(bracket.stages.last.sourceTourIds, ['final']);
      expect(bracket.stages.first.isLive, isFalse);
      expect(bracket.stages[1].isLive, isTrue);
      expect(bracket.stages.last.isLive, isFalse);

      final siblingOnly = buildKnockoutBracket(
        selectedTour: selected,
        siblingTours: [finalTour],
        roundsByTourId: {
          'final': [_round('final-leg', 'final', 'Game 1', 'game-1', day: 4)],
        },
        gamesByTourId: {
          'final': [
            _game('final-game', 'final-leg', 'final', 'Alpha', 'Delta', '*'),
          ],
        },
      );
      expect(siblingOnly.stages.map((stage) => stage.label), ['Finals']);
    });

    test('groups Dutch Stage | Game rounds into logical stages', () {
      final tour = _tour('dutch', 'Dutch Knockout Championship', day: 1);
      final rounds = [
        _round(
          'qf-1',
          'dutch',
          'Quarterfinals | Game 1',
          'quarter-finals--game-1',
          day: 1,
        ),
        _round(
          'qf-2',
          'dutch',
          'Quarterfinals | Game 2',
          'quarter-finals--game-2',
          day: 2,
        ),
        _round(
          'sf-1',
          'dutch',
          'Semifinals | Game 1',
          'semi-finals--game-1',
          day: 3,
        ),
      ];

      final bracket = buildKnockoutBracket(
        selectedTour: tour,
        siblingTours: const [],
        roundsByTourId: {'dutch': rounds},
        gamesByTourId: {
          'dutch': [
            _game('q1', 'qf-1', 'dutch', 'Alpha', 'Beta', '1-0'),
            _game('q2', 'qf-2', 'dutch', 'Beta', 'Alpha', '1/2-1/2'),
            _game('s1', 'sf-1', 'dutch', 'Alpha', 'Gamma', '*'),
          ],
        },
      );

      expect(bracket.stages.map((stage) => stage.label), [
        'Quarterfinals',
        'Semifinals',
      ]);
      final quarterfinal = bracket.stages.first.matches.single;
      expect(quarterfinal.games.map((game) => game.id), ['q1', 'q2']);
      expect(quarterfinal.participant1Score, 1.5);
      expect(quarterfinal.participant2Score, 0.5);
      expect(quarterfinal.leader?.name, 'Alpha');
      expect(quarterfinal.winner?.name, 'Alpha');
    });

    test('groups Turkish decimal rounds and keeps rematches stage-scoped', () {
      final tour = _tour('turkish', 'Turkish Cup', day: 1);
      final rounds = [
        _round('r3-1', 'turkish', 'Round 3.1', 'round-31', day: 1),
        _round('r3-2', 'turkish', 'Round 3.2', 'round-32', day: 2),
        _round(
          'r3-tb',
          'turkish',
          'Round 3 | Tiebreaks',
          'round-3-tiebreaks',
          day: 3,
        ),
        _round('r4-1', 'turkish', 'Round 4.1', 'round-41', day: 4),
      ];
      final bracket = buildKnockoutBracket(
        selectedTour: tour,
        siblingTours: const [],
        roundsByTourId: {'turkish': rounds},
        gamesByTourId: {
          'turkish': [
            _game('31', 'r3-1', 'turkish', 'Alpha', 'Beta', '1-0'),
            _game('32', 'r3-2', 'turkish', 'Beta', 'Alpha', '0-1'),
            _game('3tb', 'r3-tb', 'turkish', 'Alpha', 'Beta', '*'),
            _game('41', 'r4-1', 'turkish', 'Beta', 'Alpha', '*'),
          ],
        },
      );

      expect(bracket.stages.map((stage) => stage.label), [
        'Round 3',
        'Round 4',
      ]);
      expect(bracket.stages.first.matches.single.games, hasLength(3));
      expect(bracket.stages.last.matches.single.games, hasLength(1));
      expect(
        bracket.stages.first.matches.single.key,
        isNot(bracket.stages.last.matches.single.key),
      );
    });

    test(
      'separates leader from proven winner and infers only evidenced edges',
      () {
        final tour = _tour('proof', 'Proof Cup', day: 1);
        final rounds = [
          _round('r1-1', 'proof', 'Round 1.1', 'round-11', day: 1),
          _round('r1-2', 'proof', 'Round 1.2', 'round-12', day: 2),
          _round('r2-1', 'proof', 'Round 2.1', 'round-21', day: 3),
        ];
        final bracket = buildKnockoutBracket(
          selectedTour: tour,
          siblingTours: const [],
          roundsByTourId: {'proof': rounds},
          gamesByTourId: {
            'proof': [
              _game(
                'ab1',
                'r1-1',
                'proof',
                'GM Alpha',
                'Beta',
                '1-0',
                board: 1,
              ),
              _game(
                'ab2',
                'r1-2',
                'proof',
                'Beta',
                'Alpha',
                '1/2-1/2',
                board: 1,
              ),
              _game(
                'cd1',
                'r1-1',
                'proof',
                'Charlie',
                'Delta',
                '1/2-1/2',
                board: 2,
              ),
              _game('ac', 'r2-1', 'proof', 'Alpha', 'Charlie', '*', board: 1),
              _game('xe', 'r2-1', 'proof', 'Bye Player', 'Echo', '*', board: 2),
            ],
          },
        );

        final firstStage = bracket.stages.first;
        final alphaMatch = firstStage.matches.first;
        final tiedMatch = firstStage.matches.last;
        expect(alphaMatch.leader?.name, 'Alpha');
        expect(alphaMatch.winner?.name, 'Alpha');
        expect(tiedMatch.leader, isNull);
        expect(tiedMatch.winner?.name, 'Charlie');
        expect(bracket.edges, hasLength(2));

        final bye = bracket.stages.last.matches.last.participant1;
        expect(
          bracket.edges.where((edge) => edge.participantId == bye.id),
          isEmpty,
        );
        expect(bracket.currentStageKey, bracket.stages.last.key);
        expect(bracket.isPartial, isTrue);
      },
    );

    test('leaves a terminal tied match undecided', () {
      final tour = _tour('tie', 'Tie Cup | Finals', day: 1);
      final round = _round('final', 'tie', 'Game 1', 'game-1', day: 1);
      final bracket = buildKnockoutBracket(
        selectedTour: tour,
        siblingTours: const [],
        roundsByTourId: {
          'tie': [round],
        },
        gamesByTourId: {
          'tie': [_game('draw', 'final', 'tie', 'Alpha', 'Beta', '½-½')],
        },
      );

      final match = bracket.stages.single.matches.single;
      expect(match.isComplete, isTrue);
      expect(match.leader, isNull);
      expect(match.winner, isNull);
    });

    test('does not declare a winner before a scheduled second leg', () {
      final tour = _tour('live-final', 'Live Cup | Finals', day: 1);
      final bracket = buildKnockoutBracket(
        selectedTour: tour,
        siblingTours: const [],
        roundsByTourId: {
          'live-final': [
            _round('game-1', 'live-final', 'Game 1', 'game-1', day: 1),
            _round('game-2', 'live-final', 'Game 2', 'game-2', day: 2),
          ],
        },
        gamesByTourId: {
          'live-final': [
            _game('first-leg', 'game-1', 'live-final', 'Alpha', 'Beta', '1-0'),
          ],
        },
        now: DateTime.utc(2026, 1, 1, 12),
      );

      final stage = bracket.stages.single;
      final match = stage.matches.single;
      expect(stage.state, KnockoutStageState.inProgress);
      expect(match.leader?.name, 'Alpha');
      expect(match.winner, isNull);
    });

    test('scopes live state to the active round in a single-tour bracket', () {
      final tour = _tour('single-live', 'Single Tour Cup', day: 1);
      final bracket = buildKnockoutBracket(
        selectedTour: tour,
        siblingTours: const [],
        roundsByTourId: {
          'single-live': [
            _round('round-1', 'single-live', 'Round 1.1', 'round-11', day: 1),
            _round('round-2', 'single-live', 'Round 2.1', 'round-21', day: 2),
          ],
        },
        gamesByTourId: {
          'single-live': [
            _game('finished', 'round-1', 'single-live', 'Alpha', 'Beta', '1-0'),
            _game('playing', 'round-2', 'single-live', 'Alpha', 'Charlie', '*'),
          ],
        },
        liveTourIds: const {'single-live'},
        liveRoundIds: const {'round-2'},
      );

      final firstStage = bracket.stages.first;
      final secondStage = bracket.stages.last;
      expect(firstStage.isLive, isFalse);
      expect(firstStage.matches.single.isLive, isFalse);
      expect(secondStage.isLive, isTrue);
      expect(secondStage.matches.single.isLive, isTrue);
      expect(bracket.currentStageKey, secondStage.key);
    });

    test('does not treat a third-place appearance as advancement', () {
      final tour = _tour('placement', 'Placement Cup', day: 1, endDay: 5);
      final bracket = buildKnockoutBracket(
        selectedTour: tour,
        siblingTours: const [],
        roundsByTourId: {
          'placement': [
            _round(
              'semifinal',
              'placement',
              'Semifinals | Game 1',
              'semifinals--game-1',
              day: 1,
            ),
            _round(
              'bronze',
              'placement',
              'Third place | Game 1',
              'third-place--game-1',
              day: 2,
            ),
          ],
        },
        gamesByTourId: {
          'placement': [
            _game(
              'semifinal-game',
              'semifinal',
              'placement',
              'Alpha',
              'Beta',
              '1-0',
            ),
            _game('bronze-game', 'bronze', 'placement', 'Beta', 'Charlie', '*'),
          ],
        },
        now: DateTime.utc(2026, 1, 3),
      );

      final semifinal = bracket.stages.first.matches.single;
      expect(semifinal.leader?.name, 'Alpha');
      expect(semifinal.winner, isNull);
      expect(
        bracket.edges
            .singleWhere((edge) => edge.sourceMatchKey == semifinal.key)
            .participantId,
        semifinal.participant2.id,
      );
    });

    test('waits for the listed event window before terminal inference', () {
      final tour = _tour(
        'unpublished-leg',
        'Unpublished Leg Cup | Finals',
        day: 1,
        endDay: 2,
      );
      KnockoutBracket buildAt(DateTime now) => buildKnockoutBracket(
        selectedTour: tour,
        siblingTours: const [],
        roundsByTourId: {
          'unpublished-leg': [
            _round(
              'only-published-leg',
              'unpublished-leg',
              'Game 1',
              'game-1',
              day: 1,
            ),
          ],
        },
        gamesByTourId: {
          'unpublished-leg': [
            _game(
              'first-leg',
              'only-published-leg',
              'unpublished-leg',
              'Alpha',
              'Beta',
              '1-0',
            ),
          ],
        },
        now: now,
      );

      final ongoing = buildAt(DateTime.utc(2026, 1, 2, 12));
      expect(ongoing.stages.single.state, KnockoutStageState.inProgress);
      expect(ongoing.stages.single.matches.single.leader?.name, 'Alpha');
      expect(ongoing.stages.single.matches.single.winner, isNull);

      final ended = buildAt(DateTime.utc(2026, 1, 3, 1));
      expect(ended.stages.single.state, KnockoutStageState.completed);
      expect(ended.stages.single.matches.single.winner?.name, 'Alpha');
    });

    test('omits placeholder pairings as partial evidence', () {
      final tour = _tour('placeholders', 'Placeholder Cup | Finals', day: 1);
      final bracket = buildKnockoutBracket(
        selectedTour: tour,
        siblingTours: const [],
        roundsByTourId: {
          'placeholders': [
            _round('final', 'placeholders', 'Game 1', 'game-1', day: 1),
          ],
        },
        gamesByTourId: {
          'placeholders': [
            _game('tbd', 'final', 'placeholders', 'TBD', 'Alpha', '*'),
            _game('unknown', 'final', 'placeholders', '?', 'Unknown', '*'),
          ],
        },
      );

      expect(bracket.stages.single.matches, isEmpty);
      expect(bracket.isPartial, isTrue);
    });

    test('sorts matches by board and then source feed order', () {
      final tour = _tour('feed-order', 'Feed Order Cup | Finals', day: 1);
      final bracket = buildKnockoutBracket(
        selectedTour: tour,
        siblingTours: const [],
        roundsByTourId: {
          'feed-order': [
            _round('final', 'feed-order', 'Game 1', 'game-1', day: 1),
          ],
        },
        gamesByTourId: {
          'feed-order': [
            _game('z-first', 'final', 'feed-order', 'Zulu', 'Yankee', '*'),
            _game('a-second', 'final', 'feed-order', 'Alpha', 'Beta', '*'),
          ],
        },
      );

      expect(
        bracket.stages.single.matches.map((match) => match.games.single.id),
        ['z-first', 'a-second'],
      );
    });

    test('recognizes adjudicated and forfeit result encodings', () {
      final tour = _tour('forfeits', 'Forfeit Cup | Finals', day: 1);
      final bracket = buildKnockoutBracket(
        selectedTour: tour,
        siblingTours: const [],
        roundsByTourId: {
          'forfeits': [_round('final', 'forfeits', 'Game 1', 'game-1', day: 1)],
        },
        gamesByTourId: {
          'forfeits': [
            _game('white', 'final', 'forfeits', 'Alpha', 'Beta', '+:-'),
            _game('black', 'final', 'forfeits', 'Charlie', 'Delta', '-:+'),
            _game('draw', 'final', 'forfeits', 'Echo', 'Foxtrot', '=:='),
            _game('double', 'final', 'forfeits', 'Golf', 'Hotel', '0-0'),
          ],
        },
      );

      KnockoutMatch match(String gameId) => bracket.stages.single.matches
          .singleWhere((match) => match.games.single.id == gameId);
      expect(match('white').participant1Score, 1);
      expect(match('white').participant2Score, 0);
      expect(match('black').participant1Score, 0);
      expect(match('black').participant2Score, 1);
      expect(match('draw').participant1Score, 0.5);
      expect(match('draw').participant2Score, 0.5);
      expect(match('double').participant1Score, 0);
      expect(match('double').participant2Score, 0);
      expect(match('double').isComplete, isTrue);
    });

    test(
      'settles an old terminal stage when imported tour dates are empty',
      () {
        final tour = _tour(
          'undated',
          'Undated Cup | Finals',
          day: 1,
          includeDates: false,
        );
        KnockoutBracket buildAt(int day) => buildKnockoutBracket(
          selectedTour: tour,
          siblingTours: const [],
          roundsByTourId: {
            'undated': [_round('final', 'undated', 'Game 1', 'game-1', day: 1)],
          },
          gamesByTourId: {
            'undated': [
              _game('game', 'final', 'undated', 'Alpha', 'Beta', '1-0'),
            ],
          },
          now: DateTime.utc(2026, 1, day),
        );

        expect(buildAt(5).stages.single.matches.single.winner, isNull);
        expect(buildAt(10).stages.single.matches.single.winner?.name, 'Alpha');
      },
    );

    test('keeps ambiguous pairings without inventing connector paths', () {
      final tour = _tour('ambiguous', 'Ambiguous Cup', day: 1);
      final bracket = buildKnockoutBracket(
        selectedTour: tour,
        siblingTours: const [],
        roundsByTourId: {
          'ambiguous': [
            _round('r3', 'ambiguous', 'Round 3.1', 'round-31', day: 1),
            _round(
              'semi',
              'ambiguous',
              'Semifinals | Game 1',
              'semifinals--game-1',
              day: 2,
            ),
            _round('arm', 'ambiguous', 'Armageddon', 'armageddon', day: 3),
            _round(
              'final',
              'ambiguous',
              'Finals | Game 1',
              'finals--game-1',
              day: 4,
            ),
          ],
        },
        gamesByTourId: {
          'ambiguous': [
            _game('r3-game', 'r3', 'ambiguous', 'Alpha', 'Beta', '1-0'),
            _game('semi-game', 'semi', 'ambiguous', 'Alpha', 'Charlie', '1-0'),
            _game('arm-game', 'arm', 'ambiguous', 'Alpha', 'Beta', '1-0'),
            _game('final-game', 'final', 'ambiguous', 'Alpha', 'Delta', '*'),
          ],
        },
      );

      final other = bracket.stages.singleWhere(
        (stage) => stage.label == 'Other pairings',
      );
      expect(other.matches.single.games.single.id, 'arm-game');
      expect(
        bracket.edges.where(
          (edge) =>
              edge.sourceMatchKey.startsWith(other.key) ||
              edge.destinationMatchKey.startsWith(other.key),
        ),
        isEmpty,
      );
      final semifinal = bracket.stages.singleWhere(
        (stage) => stage.label == 'Semifinals',
      );
      final finalStage = bracket.stages.singleWhere(
        (stage) => stage.label == 'Finals',
      );
      expect(
        bracket.edges.any(
          (edge) =>
              edge.sourceMatchKey == semifinal.matches.single.key &&
              edge.destinationMatchKey == finalStage.matches.single.key,
        ),
        isTrue,
      );
    });

    test('retains a game whose round metadata is still missing', () {
      final tour = _tour('missing-round', 'Missing Round Cup', day: 1);
      final bracket = buildKnockoutBracket(
        selectedTour: tour,
        siblingTours: const [],
        roundsByTourId: {
          'missing-round': [
            _round('r3', 'missing-round', 'Round 3.1', 'round-31', day: 1),
            _round('r4', 'missing-round', 'Round 4.1', 'round-41', day: 2),
          ],
        },
        gamesByTourId: {
          'missing-round': [
            _game('r3-game', 'r3', 'missing-round', 'Alpha', 'Beta', '1-0'),
            _game(
              'unknown-game',
              'not-yet-fetched',
              'missing-round',
              'Echo',
              'Foxtrot',
              '*',
            ),
          ],
        },
      );

      final other = bracket.stages.singleWhere(
        (stage) => stage.label == 'Other pairings',
      );
      expect(other.matches.single.games.single.id, 'unknown-game');
      expect(bracket.isPartial, isTrue);
    });

    test('omits advancement when a player has multiple source matches', () {
      final tour = _tour(
        'duplicate-source',
        'Duplicate Source Cup',
        day: 1,
        endDay: 5,
      );
      final bracket = buildKnockoutBracket(
        selectedTour: tour,
        siblingTours: const [],
        roundsByTourId: {
          'duplicate-source': [
            _round(
              'round-1',
              'duplicate-source',
              'Round 1.1',
              'round-11',
              day: 1,
            ),
            _round(
              'round-2',
              'duplicate-source',
              'Round 2.1',
              'round-21',
              day: 2,
            ),
          ],
        },
        gamesByTourId: {
          'duplicate-source': [
            _game(
              'alpha-beta',
              'round-1',
              'duplicate-source',
              'Alpha',
              'Beta',
              '1-0',
            ),
            _game(
              'alpha-gamma',
              'round-1',
              'duplicate-source',
              'Alpha',
              'Gamma',
              '1-0',
            ),
            _game(
              'alpha-delta',
              'round-2',
              'duplicate-source',
              'Alpha',
              'Delta',
              '*',
            ),
          ],
        },
        now: DateTime.utc(2026, 1, 2),
      );

      final firstStage = bracket.stages.first;
      expect(
        bracket.edges.where(
          (edge) => firstStage.matches.any(
            (match) => match.key == edge.sourceMatchKey,
          ),
        ),
        isEmpty,
      );
      expect(firstStage.matches.every((match) => match.winner == null), isTrue);
      expect(bracket.isPartial, isTrue);
    });
  });
}

Tour _tour(
  String id,
  String name, {
  required int day,
  int? endDay,
  String? groupId = 'broadcast',
  String format = 'Knockout',
  bool includeDates = true,
}) => Tour(
  id: id,
  name: name,
  slug: id,
  info: TourInfo(format: format),
  createdAt: DateTime.utc(2026, 1, day),
  url: 'https://lichess.org/broadcast/$id',
  tier: 1,
  dates:
      includeDates
          ? [
            DateTime.utc(2026, 1, day),
            if (endDay != null) DateTime.utc(2026, 1, endDay),
          ]
          : const [],
  players: const [],
  groupBroadcastId: groupId,
);

Round _round(
  String id,
  String tourId,
  String name,
  String slug, {
  required int day,
}) => Round(
  id: id,
  slug: slug,
  tourId: tourId,
  tourSlug: tourId,
  name: name,
  createdAt: DateTime.utc(2026, 1, day),
  startsAt: DateTime.utc(2026, 1, day),
  url: 'https://lichess.org/broadcast/$tourId/$slug/$id',
);

Games _game(
  String id,
  String roundId,
  String tourId,
  String white,
  String black,
  String status, {
  int? board,
}) => Games(
  id: id,
  roundId: roundId,
  roundSlug: roundId,
  tourId: tourId,
  tourSlug: tourId,
  players: [_player(white), _player(black)],
  status: status,
  boardNr: board,
  lastMove: status == '*' ? null : 'e2e4',
);

Player _player(String name) => Player(
  name: name,
  title: '',
  rating: 2500,
  fideId: 0,
  fed: 'FIDE',
  clock: 0,
  team: '',
);
