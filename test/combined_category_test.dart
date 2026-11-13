import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_games_provider.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_round_sections.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_round_buckets.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_flattened_layout.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed clock so "started" never depends on the wall clock.
final _now = DateTime.utc(2026, 11, 11, 18);

TourModel _tour(
  String name, {
  int? avgElo,
  String? id,
  String? slug,
  bool isMirror = false,
}) {
  return TourModel(
    tour: Tour(
      id: id ?? name,
      name: name,
      slug: slug ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
      info: const TourInfo(),
      createdAt: DateTime.utc(2026, 1, 1),
      url: 'https://example.test/$name',
      tier: 0,
      dates: [DateTime.utc(2026, 11, 11)],
      players: const <TournamentPlayer>[],
      avgElo: avgElo,
      isMirror: isMirror,
    ),
    roundStatus: RoundStatus.ongoing,
  );
}

CombinedCategory _category(
  String label, {
  int? avgElo,
  required int order,
  DateTime? startsAt,
}) => CombinedCategory(
  tourId: label,
  label: label,
  avgElo: avgElo,
  order: order,
  startsAt: startsAt,
);

Round _round(String id, String tourId, String name, DateTime? startsAt) =>
    Round(
      id: id,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      tourId: tourId,
      tourSlug: tourId.toLowerCase(),
      name: name,
      createdAt: DateTime.utc(2026, 11, 1),
      startsAt: startsAt,
      url: 'https://example.test/$id',
    );

PlayerCard _player(String name, {String fed = 'USA'}) => PlayerCard(
  name: name,
  federation: fed,
  title: 'GM',
  rating: 2700,
  countryCode: fed,
  team: null,
);

GamesTourModel _game(
  String id, {
  required String tourId,
  required String roundId,
  int? board,
  GameStatus status = GameStatus.draw,
  String? lastMove = 'e2e4',
  String? white,
  String? black,
  DateTime? lastMoveTime,
}) => GamesTourModel(
  gameId: id,
  // Every board has its own two players unless a test says otherwise, so a
  // board is never mistaken for a copy of another.
  whitePlayer: _player(white ?? 'White $id'),
  blackPlayer: _player(black ?? 'Black $id', fed: 'NOR'),
  whiteTimeDisplay: '10:00',
  blackTimeDisplay: '10:00',
  whiteClockCentiseconds: 60000,
  blackClockCentiseconds: 60000,
  whiteClockSeconds: 600,
  blackClockSeconds: 600,
  gameStatus: status,
  roundId: roundId,
  roundSlug: 'round-1',
  tourId: tourId,
  lastMove: lastMove,
  boardNr: board,
  lastMoveTime: lastMoveTime,
);

List<String> _order(List<CombinedRoundSection> sections) => [
  for (final section in sections)
    '${section.category.label} ${section.round.name}',
];

class _MemoryStore implements TourSelectionStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> setString(String key, String value) async => values[key] = value;
}

void main() {
  group('Combined schedule blocks match web', () {
    ({
      CombinedCategory category,
      List<Round> rounds,
      List<GamesTourModel> games,
    })
    source(String id, DateTime first, int count, int played, {int elo = 2700}) {
      final rounds = [
        for (var i = 0; i < count; i++)
          _round(
            '$id-${i + 1}',
            id,
            'Round ${i + 1}',
            first.add(Duration(days: i)),
          ),
      ];
      return (
        category: _category(id, avgElo: elo, order: 0),
        rounds: rounds,
        games: [
          for (var i = 0; i < count; i++)
            _game(
              '$id-game-${i + 1}',
              tourId: id,
              roundId: rounds[i].id,
              status: i < played ? GameStatus.draw : GameStatus.ongoing,
              lastMove: i < played ? 'e2e4' : null,
            ),
        ],
      );
    }

    test('future rounds ascend numerically through Round 10', () {
      final upcoming = source(
        'upcoming',
        _now.add(const Duration(days: 1)),
        10,
        0,
      );
      final sections = buildCombinedRoundSections(
        categories: [upcoming.category],
        gamesByTourId: {'upcoming': upcoming.games},
        roundsByTourId: {'upcoming': upcoming.rounds},
        liveRoundIds: const [],
        now: _now,
      );
      expect(sections.map((section) => section.round.name), [
        for (var n = 1; n <= 10; n++) 'Round $n',
      ]);
    });

    test(
      'parallel groups stay complete before older Blitz, without mutating sources',
      () {
        final first = _now.subtract(const Duration(days: 3, hours: 12));
        final a = source('a', first, 10, 4);
        final b = source('b', first, 10, 4, elo: 2600);
        final blitz = source(
          'blitz',
          _now.subtract(const Duration(days: 10)),
          5,
          5,
          elo: 2800,
        );
        final roundsByTourId = {
          'a': a.rounds,
          'b': b.rounds,
          'blitz': blitz.rounds,
        };
        final gamesByTourId = {
          'a': a.games,
          'b': b.games,
          'blitz': blitz.games,
        };
        final beforeRounds = {
          for (final entry in roundsByTourId.entries)
            entry.key: List<Round>.of(entry.value),
        };
        final beforeGames = {
          for (final entry in gamesByTourId.entries)
            entry.key: List<GamesTourModel>.of(entry.value),
        };
        for (final categories in [
          [blitz.category, b.category, a.category],
          [a.category, blitz.category, b.category],
        ]) {
          final sections = buildCombinedRoundSections(
            categories: categories,
            gamesByTourId: gamesByTourId,
            roundsByTourId: roundsByTourId,
            liveRoundIds: const [],
            now: _now,
          );
          expect(sections.map((section) => section.round.id), [
            for (final n in [4, 3, 2, 1, 5, 6, 7, 8, 9, 10]) ...[
              'a-$n',
              'b-$n',
            ],
            for (final n in [5, 4, 3, 2, 1]) 'blitz-$n',
          ]);
          final buckets = buildCombinedRoundBuckets(
            sections,
            eventId: 'festival',
          );
          expect(buckets.take(10).map((bucket) => bucket.round.name), [
            for (final n in [4, 3, 2, 1, 5, 6, 7, 8, 9, 10]) 'Round $n',
          ]);
          expect(buckets.first.sources.map((section) => section.roundId), [
            'a-4',
            'b-4',
          ]);
          expect(roundsByTourId, beforeRounds);
          expect(gamesByTourId, beforeGames);
        }
      },
    );

    test(
      'whole schedules merge transitively even before all pairings arrive',
      () {
        final a = source('a', _now.subtract(const Duration(days: 6)), 9, 5);
        final b = source('b', _now.add(const Duration(days: 1)), 4, 0);
        final c = source('c', _now.add(const Duration(days: 3)), 1, 0);
        final blitz = source(
          'blitz',
          _now.subtract(const Duration(days: 8)),
          1,
          1,
        );
        final sections = buildCombinedRoundSections(
          categories: [c.category, blitz.category, a.category, b.category],
          gamesByTourId: {
            'a': [a.games[4]],
            'b': [b.games.first],
            'c': c.games,
            'blitz': blitz.games,
          },
          roundsByTourId: {
            'a': a.rounds,
            'b': b.rounds,
            'c': c.rounds,
            'blitz': blitz.rounds,
          },
          liveRoundIds: const [],
          now: _now,
        );
        expect(sections.map((section) => section.round.id), [
          'a-5',
          'b-1',
          'c-1',
          'blitz-1',
        ]);
      },
    );
  });

  group('isCombinedSectionLabel', () {
    test('recognises an organizer Combined section by name or slug', () {
      expect(
        isCombinedSectionLabel(
          name: 'Total Chess World Championship Tour | Group Stage Combined',
        ),
        isTrue,
      );
      expect(
        isCombinedSectionLabel(name: 'Group Stage', slug: 'group-combined'),
        isTrue,
      );
    });

    test('does not fire on a word that merely contains it', () {
      expect(isCombinedSectionLabel(name: 'Recombined Open'), isFalse);
      expect(isCombinedSectionLabel(name: 'Group A', slug: 'group-a'), isFalse);
      expect(isCombinedSectionLabel(), isFalse);
    });
  });

  group('CombinedCategories.fromTours', () {
    test('merges the real groups and skips the organizer Combined section', () {
      final categories = CombinedCategories.fromTours([
        _tour('Total Chess | Group Stage A', avgElo: 2700),
        _tour('Total Chess | Group Stage B', avgElo: 2710),
        _tour('Total Chess | Group Stage Combined', avgElo: 2705),
      ], groupName: 'Total Chess');

      expect(categories.canCombine, isTrue);
      expect(
        [for (final item in categories.items) item.label],
        ['Group Stage A', 'Group Stage B'],
      );
      expect(categories.tourIds, hasLength(2));
    });

    test('skips a section the database flags as a mirror, whatever its name', () {
      final categories = CombinedCategories.fromTours([
        _tour('Open', avgElo: 2500),
        _tour('Women', avgElo: 2300),
        _tour('All boards', avgElo: 2400, isMirror: true),
      ]);
      expect(categories.tourIds, ['Open', 'Women']);
      },
    );

    test('reads the mirror flag from the tours row', () {
      Map<String, dynamic> row({Object? isMirror}) => {
        'id': 't',
        'name': 'Event | All boards',
        'slug': 'event-all-boards',
        'is_mirror': ?isMirror,
      };
      expect(Tour.fromJson(row(isMirror: true)).isMirror, isTrue);
      expect(Tour.fromJson(row(isMirror: false)).isMirror, isFalse);
      // A cached row from before the column existed.
      expect(Tour.fromJson(row()).isMirror, isFalse);
    });

    test('one real category beside its mirror has nothing to combine', () {
      final categories = CombinedCategories.fromTours([
        _tour('Event | Open'),
        _tour('Event | Combined'),
      ]);
      expect(categories.canCombine, isFalse);
    });

    test('Combined-named tours never feed generated Combined', () {
      final categories = CombinedCategories.fromTours([
        _tour('Combined Open'),
        _tour('Combined Women'),
      ]);
      expect(categories.canCombine, isFalse);
      expect(categories.items, isEmpty);
    });

    test('is value-equal, so an unchanged refresh rebuilds nothing', () {
      CombinedCategories build() => CombinedCategories.fromTours([
        _tour('Event | Group A', avgElo: 2600),
        _tour('Event | Group B', avgElo: 2500),
      ]);
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
    });
  });

  group('CombinedCategoryPrefsNotifier', () {
    test('asks once the stored answers are read, and only then', () async {
      final notifier = CombinedCategoryPrefsNotifier(_MemoryStore());
      expect(notifier.state.shouldAsk('event'), isFalse);

      await notifier.ensureLoaded('event');
      expect(notifier.state.shouldAsk('event'), isTrue);
    });

    test('an answered event is not asked again, across sessions', () async {
      final store = _MemoryStore();
      final first = CombinedCategoryPrefsNotifier(store);
      await first.ensureLoaded('event');
      await first.markAnswered('event');
      expect(first.state.shouldAsk('event'), isFalse);

      final second = CombinedCategoryPrefsNotifier(store);
      await second.ensureLoaded('event');
      expect(second.state.shouldAsk('event'), isFalse);
      // Another event still gets its own question.
      await second.ensureLoaded('other');
      expect(second.state.shouldAsk('other'), isTrue);
    });

    test('"Never ask" silences every event', () async {
      final store = _MemoryStore();
      final first = CombinedCategoryPrefsNotifier(store);
      await first.setNeverAsk();

      final second = CombinedCategoryPrefsNotifier(store);
      await second.ensureLoaded('event');
      await second.ensureLoaded('other');
      expect(second.state.shouldAsk('event'), isFalse);
      expect(second.state.shouldAsk('other'), isFalse);
    });

    test('choosing Combined is remembered and answers the question', () async {
      final store = _MemoryStore();
      final first = CombinedCategoryPrefsNotifier(store);
      await first.setSelected('event', true);
      expect(first.state.isSelected('event'), isTrue);

      final second = CombinedCategoryPrefsNotifier(store);
      await second.ensureLoaded('event');
      expect(second.state.isSelected('event'), isTrue);
      expect(second.state.shouldAsk('event'), isFalse);

      await second.setSelected('event', false);
      final third = CombinedCategoryPrefsNotifier(store);
      await third.ensureLoaded('event');
      expect(third.state.isSelected('event'), isFalse);
      // Leaving Combined is not a reason to ask again.
      expect(third.state.shouldAsk('event'), isFalse);
    });

    test('a pick made while storage is still loading wins', () async {
      final store = _MemoryStore();
      store.values[CombinedCategoryPrefsNotifier.selectedKey('event')] = '1';
      final notifier = CombinedCategoryPrefsNotifier(store);

      final loading = notifier.ensureLoaded('event');
      await notifier.setSelected('event', false);
      await loading;

      expect(notifier.state.isSelected('event'), isFalse);
    });
  });

  group('buildCombinedRoundSections', () {
    final categories = [
      _category('Group A', avgElo: 2650, order: 0),
      _category('Group B', avgElo: 2700, order: 1),
      _category('Group C', avgElo: 2600, order: 2),
    ];
    final r1 = DateTime.utc(2026, 11, 11, 14);
    final r2 = DateTime.utc(2026, 11, 11, 16);
    final r3 = DateTime.utc(2026, 11, 11, 20);

    Map<String, List<Round>> rounds() => {
      for (final category in categories)
        category.tourId: [
          _round('${category.tourId}-r1', category.tourId, 'Round 1', r1),
          _round('${category.tourId}-r2', category.tourId, 'Round 2', r2),
          _round('${category.tourId}-r3', category.tourId, 'Round 3', r3),
        ],
    };

    test(
      'round starts first, then category strength within the same start',
      () {
      final sections = buildCombinedRoundSections(
        categories: categories,
        gamesByTourId: {
          for (final category in categories)
            category.tourId: [
              _game(
                '${category.tourId}-1',
                tourId: category.tourId,
                roundId: '${category.tourId}-r1',
              ),
              _game(
                '${category.tourId}-2',
                tourId: category.tourId,
                roundId: '${category.tourId}-r2',
                status: GameStatus.ongoing,
              ),
            ],
        },
        roundsByTourId: rounds(),
        liveRoundIds: const <String>[],
        now: _now,
      );

      expect(_order(sections), [
        'Group B Round 2',
          'Group A Round 2',
          'Group C Round 2',
          'Group B Round 1',
          'Group A Round 1',
          'Group C Round 1',
      ]);
      },
    );

    test('a newer round outranks an older round from a stronger category', () {
      final staggered = rounds();
      staggered['Group C'] = [
        _round(
          'Group C-r1',
          'Group C',
          'Round 1',
          r2.add(const Duration(minutes: 30)),
        ),
      ];
      final sections = buildCombinedRoundSections(
        categories: categories,
        gamesByTourId: {
          'Group A': [
            _game(
              'a',
              tourId: 'Group A',
              roundId: 'Group A-r2',
              status: GameStatus.ongoing,
            ),
          ],
          'Group B': [
            _game(
              'b',
              tourId: 'Group B',
              roundId: 'Group B-r2',
              status: GameStatus.ongoing,
            ),
          ],
          'Group C': [
            _game(
              'c',
              tourId: 'Group C',
              roundId: 'Group C-r1',
              status: GameStatus.ongoing,
            ),
          ],
        },
        roundsByTourId: staggered,
        liveRoundIds: const <String>[],
        now: _now,
      );

      expect(_order(sections), [
        'Group C Round 1',
        'Group B Round 2',
        'Group A Round 2',
      ]);
    });

    test(
      'equal round starts and ratings use source identity; unrated last',
      () {
      final tied = [
        _category('Unrated', order: 0, startsAt: r3),
        _category('Early', avgElo: 2700, order: 1, startsAt: r1),
        _category('Late', avgElo: 2700, order: 2, startsAt: r2),
        _category('Late too', avgElo: 2700, order: 3, startsAt: r2),
        _category('Top', avgElo: 2750, order: 4, startsAt: r1),
      ];
      final sections = buildCombinedRoundSections(
        categories: tied,
        gamesByTourId: {
          for (final category in tied)
            category.tourId: [
              _game(
                category.tourId,
                tourId: category.tourId,
                roundId: '${category.tourId}-r1',
              ),
            ],
        },
        roundsByTourId: {
          for (final category in tied)
            category.tourId: [
              _round('${category.tourId}-r1', category.tourId, 'Round 1', r1),
            ],
        },
        liveRoundIds: const <String>[],
        now: _now,
      );

      expect(
        [for (final section in sections) section.category.label],
          ['Top', 'Early', 'Late', 'Late too', 'Unrated'],
        );
      },
    );

    test('a category\'s published pairings wait below its round in play', () {
      final sections = buildCombinedRoundSections(
        categories: categories.take(2).toList(),
        gamesByTourId: {
          'Group A': [
            _game(
              'a2',
              tourId: 'Group A',
              roundId: 'Group A-r2',
              status: GameStatus.ongoing,
            ),
            _game(
              'a3',
              tourId: 'Group A',
              roundId: 'Group A-r3',
              status: GameStatus.ongoing,
              lastMove: null,
            ),
          ],
          'Group B': [
            _game('b2', tourId: 'Group B', roundId: 'Group B-r2'),
            _game(
              'b3',
              tourId: 'Group B',
              roundId: 'Group B-r3',
              status: GameStatus.ongoing,
              lastMove: null,
            ),
          ],
        },
        roundsByTourId: rounds(),
        liveRoundIds: const <String>[],
        now: _now,
      );

      // Both sources' future pairings follow the rounds already played.
      expect(_order(sections), [
        'Group B Round 2',
        'Group A Round 2',
        'Group B Round 3',
        'Group A Round 3',
      ]);
    });

    test('future pairings stay below played rounds between rounds', () {
      final sections = buildCombinedRoundSections(
        categories: categories.take(2).toList(),
        gamesByTourId: {
          for (final tourId in ['Group A', 'Group B'])
            tourId: [
              _game('$tourId-1', tourId: tourId, roundId: '$tourId-r1'),
              _game('$tourId-2', tourId: tourId, roundId: '$tourId-r2'),
              _game(
                '$tourId-3',
                tourId: tourId,
                roundId: '$tourId-r3',
                status: GameStatus.ongoing,
                lastMove: null,
              ),
            ],
        },
        roundsByTourId: rounds(),
        liveRoundIds: const <String>[],
        now: _now,
      );

      expect(_order(sections), [
        'Group B Round 2',
        'Group A Round 2',
        'Group B Round 1',
        'Group A Round 1',
        'Group B Round 3',
        'Group A Round 3',
      ]);
    });

    test('same-start knockout stages precede source rating, like web', () {
      final labels = [
        'Open',
        'Round of 16',
        'Quarter-Final',
        'Semi Final',
        'Bronze',
        'Final',
        'Grand Final',
      ];
      final sources = [
        for (var i = 0; i < labels.length; i++)
          _category(labels[i], avgElo: 2900 - i * 100, order: i),
      ];
      final sections = buildCombinedRoundSections(
        categories: sources,
        gamesByTourId: {
          for (final source in sources)
            source.tourId: [
              _game(
                source.tourId,
                tourId: source.tourId,
                roundId: '${source.tourId}-r',
              ),
            ],
        },
        roundsByTourId: {
          for (final source in sources)
            source.tourId: [
              _round('${source.tourId}-r', source.tourId, source.label, r1),
            ],
        },
        liveRoundIds: const [],
        now: _now,
      );
      expect(
        sections.map((section) => section.category.label),
        labels.reversed,
      );
    });

    test('generic round and short labels retain the source title stage', () {
      final sources = [
        const CombinedCategory(
          tourId: 'high',
          label: 'A',
          sourceName: 'Festival | Semi Final | A',
          avgElo: 2800,
          order: 0,
        ),
        const CombinedCategory(
          tourId: 'low',
          label: 'B',
          sourceName: 'Festival | Final | B',
          avgElo: 2400,
          order: 1,
        ),
      ];
      final sections = buildCombinedRoundSections(
        categories: sources,
        gamesByTourId: {
          for (final source in sources)
            source.tourId: [
              _game(
                source.tourId,
                tourId: source.tourId,
                roundId: '${source.tourId}-r',
              ),
            ],
        },
        roundsByTourId: {
          for (final source in sources)
            source.tourId: [
              _round('${source.tourId}-r', source.tourId, 'Round 1', r1),
            ],
        },
        liveRoundIds: const [],
        now: _now,
      );
      expect(sections.map((section) => section.category.tourId), ['low', 'high']);
    });

    test(
      'one time heading contains separate source grids and preserves navigation',
      () {
        final sections = buildCombinedRoundSections(
          categories: categories.take(2).toList(),
          gamesByTourId: {
            for (final source in categories.take(2))
              source.tourId: [
                for (final round in ['r1', 'r2'])
                  for (var board = 1; board <= 3; board++)
                    _game(
                      '${source.tourId}-$round-$board',
                      tourId: source.tourId,
                      roundId: '${source.tourId}-$round',
                      board: board,
                    ),
              ],
          },
          roundsByTourId: rounds(),
          liveRoundIds: const [],
          now: _now,
        );
        final buckets = buildCombinedRoundBuckets(sections, eventId: 'festival');
        expect(buckets.map((bucket) => bucket.round.name), [
          'Round 2',
          'Round 1',
        ]);
        expect(buckets.first.sources.map((source) => source.label), [
          'Group B',
          'Group A',
        ]);
        GamesTourFlattenedLayout layout({
          bool folded = false,
          bool searching = false,
          Map<String, bool> sourceExpansion = const {},
        }) => buildGamesTourFlattenedLayout(
          rounds: [for (final bucket in buckets) bucket.round],
          gamesByRound: {
            for (final bucket in buckets) bucket.round.id: bucket.games,
          },
          sourceExpansionState: sourceExpansion,
          sourceSectionsByRound: {
            for (final bucket in buckets) bucket.round.id: bucket.sources,
          },
          mode: GamesListViewMode.chessBoardGrid,
          matchExpansionState: const {},
          roundExpansionState: {if (folded) buckets.first.round.id: false},
          isKnockoutTournament: false,
          displayMode: GameDisplayMode.all,
          isSearchMode: searching,
        );
        // Folding one event must not fold a different event at the same time.
        expect(
          buildCombinedRoundBuckets(sections, eventId: 'other').first.round.id,
          isNot(buckets.first.round.id),
        );
        final expanded = layout();
        expect(
          expanded.entries.whereType<GamesTourRoundHeaderEntry>(),
          hasLength(2),
        );
        expect(
          expanded.entries.whereType<GamesTourSourceHeaderEntry>(),
          hasLength(4),
        );
        final foldedSource = buckets.first.sources.first.roundId;
        final groupFolded = layout(sourceExpansion: {foldedSource: false});
        expect(
          groupFolded.entries.whereType<GamesTourSourceHeaderEntry>(),
          hasLength(4),
        );
        expect(
          groupFolded.entries
              .whereType<GamesTourSourceHeaderEntry>()
              .firstWhere((entry) => entry.roundId == foldedSource)
              .isExpanded,
          isFalse,
        );
        expect(
          groupFolded.entries.whereType<GamesTourGameRowEntry>().where(
            (entry) => entry.roundId == foldedSource,
          ),
          isEmpty,
        );
        expect(
          groupFolded.entries.whereType<GamesTourGameRowEntry>().where(
            (entry) => entry.roundId == buckets.first.sources.last.roundId,
          ),
          isNotEmpty,
        );
        expect(
          groupFolded.orderedGames.map((game) => game.gameId),
          expanded.orderedGames.map((game) => game.gameId),
        );
        expect(
          layout(
            searching: true,
            sourceExpansion: {foldedSource: false},
          ).entries.whereType<GamesTourGameRowEntry>(),
          hasLength(8),
        );
        final rows = expanded.entries
            .whereType<GamesTourGameRowEntry>()
            .toList();
        expect(rows, hasLength(8)); // Odd source counts never share a grid row.
        for (final row in rows) {
          expect(row.game2?.tourId ?? row.game1.tourId, row.game1.tourId);
          expect(row.game2?.roundId ?? row.game1.roundId, row.game1.roundId);
          expect(
            expanded.orderedGames[row.globalIndex1].gameId,
            row.game1.gameId,
          );
          expect(expanded.itemIndexForGameId(row.game1.gameId), isNotNull);
        }
        expect(
          expanded.roundHeaderIndex('Group A-r2'),
          expanded.roundHeaderIndex(buckets.first.round.id),
        );
        final folded = layout(folded: true);
        expect(
          folded.entries.whereType<GamesTourSourceHeaderEntry>(),
          hasLength(2),
        );
        expect(folded.orderedGames, expanded.orderedGames);
        expect(
          folded.roundHeaderIndex('Group A-r2'),
          folded.roundHeaderIndex(buckets.first.round.id),
        );
        expect(
          layout(folded: true, searching: true).entries,
          hasLength(expanded.entries.length),
        );
      },
    );

    test('inside a round: pinned boards, then board order', () {
      final sections = buildCombinedRoundSections(
        categories: categories.take(1).toList(),
        gamesByTourId: {
          'Group A': [
            _game('three', tourId: 'Group A', roundId: 'Group A-r1', board: 3),
            _game('none', tourId: 'Group A', roundId: 'Group A-r1'),
            _game('one', tourId: 'Group A', roundId: 'Group A-r1', board: 1),
            _game('two', tourId: 'Group A', roundId: 'Group A-r1', board: 2),
          ],
        },
        roundsByTourId: rounds(),
        liveRoundIds: const <String>[],
        pinnedGameIds: const {'two'},
        now: _now,
      );

      expect(
        [for (final game in sections.single.games) game.gameId],
        ['two', 'one', 'three', 'none'],
      );
    });

    test('a round the schedule has not returned yet still lists', () {
      final sections = buildCombinedRoundSections(
        categories: categories.take(1).toList(),
        gamesByTourId: {
          'Group A': [
            _game(
              'new',
              tourId: 'Group A',
              roundId: 'Group A-r9',
              status: GameStatus.ongoing,
              lastMoveTime: DateTime.utc(2026, 11, 11, 17, 30),
            ),
            _game('old', tourId: 'Group A', roundId: 'Group A-r1'),
          ],
        },
        roundsByTourId: rounds(),
        liveRoundIds: const <String>[],
        now: _now,
      );

      // Named from its slug and placed by its boards' latest activity.
      expect(_order(sections), ['Group A Round 1', 'Group A Round 1']);
      expect(sections.first.round.id, 'Group A-r9');
      expect(sections.first.games.single.gameId, 'new');
    });

    test('a category with no games contributes nothing', () {
      final sections = buildCombinedRoundSections(
        categories: categories,
        gamesByTourId: {
          'Group A': [_game('a', tourId: 'Group A', roundId: 'Group A-r1')],
          'Group B': const <GamesTourModel>[],
        },
        roundsByTourId: rounds(),
        liveRoundIds: const <String>[],
        now: _now,
      );
      expect(_order(sections), ['Group A Round 1']);
    });
  });

  group('no board is listed twice', () {
    final r1 = DateTime.utc(2026, 11, 11, 14);
    final r2 = DateTime.utc(2026, 11, 11, 16);

    // Two real groups of two boards a round, and a section that repeats all
    // of them under its own tour, round and game ids. Nothing flags it and
    // its name does not say "combined".
    List<GamesTourModel> group(String tourId, String prefix) => [
      for (final round in ['r1', 'r2'])
        for (final board in [1, 2])
          _game(
            '$tourId-$round-$board',
            tourId: tourId,
            roundId: '$tourId-$round',
            board: board,
            white: '$prefix White $round $board',
            black: '$prefix Black $round $board',
          ),
    ];
    List<GamesTourModel> copyOf(List<GamesTourModel> games, String tourId) => [
      for (final game in games)
        _game(
          '$tourId-${game.gameId}',
          tourId: tourId,
          roundId: '$tourId-${game.roundId.split('-').last}',
          white: game.whitePlayer.name,
          black: game.blackPlayer.name,
        ),
    ];
    Map<String, List<Round>> schedule(
      List<String> tourIds, {
      Duration mirrorLag = Duration.zero,
    }) => {
      for (final tourId in tourIds)
        tourId: [
          _round(
            '$tourId-r1',
            tourId,
            'Round 1',
            tourId == 'All' ? r1.add(mirrorLag) : r1,
          ),
          _round(
            '$tourId-r2',
            tourId,
            'Round 2',
            tourId == 'All' ? r2.add(mirrorLag) : r2,
          ),
        ],
    };

    final a = group('A', 'a');
    final b = group('B', 'b');
    final all = [...copyOf(a, 'All'), ...copyOf(b, 'All')];

    test('an unflagged section repeating the others is left out', () {
      // The mirror is rated like the strongest group, so it would lead.
      final sections = buildCombinedRoundSections(
        categories: [
          _category('All', avgElo: 2750, order: 0),
          _category('A', avgElo: 2700, order: 1),
          _category('B', avgElo: 2750, order: 2),
        ],
        gamesByTourId: {'All': all, 'A': a, 'B': b},
        // The copy's feed starts each round a few seconds late.
        roundsByTourId: schedule([
          'All',
          'A',
          'B',
        ], mirrorLag: const Duration(seconds: 40)),
        liveRoundIds: const <String>[],
        now: _now,
      );

      expect(
        {for (final section in sections) section.category.label},
        {'A', 'B'},
      );
      final pairings = [
        for (final section in sections)
          for (final game in section.games)
            '${game.whitePlayer.name} v ${game.blackPlayer.name}',
      ];
      expect(pairings, hasLength(8));
      expect(pairings.toSet(), hasLength(8));
    });

    test('of two identical sections the first in rank stays', () {
      expect(
        findMirrorTourIds(
          tourIds: ['A', 'Copy'],
          gamesByTourId: {'A': a, 'Copy': copyOf(a, 'Copy')},
          roundsByTourId: {
            ...schedule(['A']),
            'Copy': [
              _round('Copy-r1', 'Copy', 'Round 1', r1),
              _round('Copy-r2', 'Copy', 'Round 2', r2),
            ],
          },
        ),
        {'Copy'},
      );
    });

    test('a playoff between the same players hours later is kept', () {
      final playoff = [
        for (final game in a.take(2))
          _game(
            'playoff-${game.gameId}',
            tourId: 'Playoff',
            roundId: 'Playoff-r1',
            white: game.whitePlayer.name,
            black: game.blackPlayer.name,
          ),
      ];
      expect(
        findMirrorTourIds(
          tourIds: ['A', 'Playoff'],
          gamesByTourId: {'A': a, 'Playoff': playoff},
          roundsByTourId: {
            ...schedule(['A']),
            'Playoff': [
              _round(
                'Playoff-r1',
                'Playoff',
                'Playoff',
                r1.add(const Duration(hours: 3)),
              ),
            ],
          },
        ),
        isEmpty,
      );
    });

    test('categories that share no board are all kept', () {
      expect(
        findMirrorTourIds(
          tourIds: ['A', 'B'],
          gamesByTourId: {'A': a, 'B': b},
          roundsByTourId: schedule(['A', 'B']),
        ),
        isEmpty,
      );
    });
  });

  group('filterCombinedGames', () {
    final games = [
      _game(
        'carlsen',
        tourId: 't',
        roundId: 'r',
        white: 'Carlsen, Magnus',
        black: 'Nakamura, Hikaru',
      ),
      _game(
        'gukesh',
        tourId: 't',
        roundId: 'r',
        white: 'Gukesh D',
        black: 'Caruana, Fabiano',
      ),
    ];

    test('matches a player by any part of the name, case-insensitively', () {
      expect(
        [for (final game in filterCombinedGames(games, 'magnus')) game.gameId],
        ['carlsen'],
      );
      expect(
        [for (final game in filterCombinedGames(games, 'CARU')) game.gameId],
        ['gukesh'],
      );
    });

    test('every word must match, across both players', () {
      expect(
        [
          for (final game in filterCombinedGames(games, 'carlsen hikaru'))
            game.gameId,
        ],
        ['carlsen'],
      );
      expect(filterCombinedGames(games, 'carlsen caruana'), isEmpty);
    });

    test('an empty query keeps every game', () {
      expect(filterCombinedGames(games, '   '), hasLength(2));
    });
  });
}
