import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category_prompt.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_games_provider.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_round_sections.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed clock so "started" never depends on the wall clock.
final _now = DateTime.utc(2026, 11, 11, 18);

TourModel _tour(String name, {int? avgElo, String? id, String? slug}) {
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
    ),
    roundStatus: RoundStatus.ongoing,
  );
}

CombinedCategory _category(String label, {int? avgElo, required int order}) =>
    CombinedCategory(tourId: label, label: label, avgElo: avgElo, order: order);

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
  String white = 'White',
  String black = 'Black',
  DateTime? lastMoveTime,
}) => GamesTourModel(
  gameId: id,
  whitePlayer: _player(white),
  blackPlayer: _player(black, fed: 'NOR'),
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

    test('one real category beside its mirror has nothing to combine', () {
      final categories = CombinedCategories.fromTours([
        _tour('Event | Open'),
        _tour('Event | Combined'),
      ]);
      expect(categories.canCombine, isFalse);
    });

    test('a tour only named "combined" with no real section stays', () {
      final categories = CombinedCategories.fromTours([
        _tour('Combined Open'),
        _tour('Combined Women'),
      ]);
      expect(categories.canCombine, isTrue);
      expect(categories.items, hasLength(2));
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

    test('latest round first; a tie reads strongest category first', () {
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
    });

    test('a category that started later leads the ones before it', () {
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

    test('published pairings wait at the bottom while anything is live', () {
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

      expect(_order(sections), [
        'Group B Round 2',
        'Group A Round 2',
        'Group B Round 3',
        'Group A Round 3',
      ]);
    });

    test('between rounds every category\'s next round leads', () {
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
        'Group B Round 3',
        'Group A Round 3',
        'Group B Round 2',
        'Group A Round 2',
        'Group B Round 1',
        'Group A Round 1',
      ]);
    });

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

  group('combinedCategoryNames', () {
    test('lists a few categories in full', () {
      expect(combinedCategoryNames(['Open', 'Women']), 'Open and Women');
      expect(
        combinedCategoryNames(['Group A', 'Group B', 'Group C', 'Group D']),
        'Group A, Group B, Group C and Group D',
      );
    });

    test('counts the rest once the list gets long', () {
      expect(
        combinedCategoryNames(['U8', 'U10', 'U12', 'U14', 'U16', 'U18']),
        'U8, U10, U12 and 3 more',
      );
    });
  });
}
