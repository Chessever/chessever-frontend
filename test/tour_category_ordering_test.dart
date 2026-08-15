import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_category_ordering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed clock so "started" vs "upcoming" never depends on the wall clock.
final _now = DateTime.utc(2026, 8, 14, 12);

TourModel _tour(
  String name, {
  required List<DateTime> dates,
  int? avgElo,
  String? id,
  RoundStatus? status,
}) {
  return TourModel(
    tour: Tour(
      id: id ?? name,
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      info: TourInfo(),
      createdAt: DateTime.utc(2026, 1, 1),
      url: 'https://example.test/$name',
      tier: 0,
      dates: dates,
      players: const <TournamentPlayer>[],
      avgElo: avgElo,
    ),
    roundStatus:
        status ??
        (dates.isNotEmpty && dates.first.isAfter(_now)
            ? RoundStatus.upcoming
            : RoundStatus.completed),
  );
}

List<String> _labels(List<TourModel> models) =>
    models.map((model) => tourCategoryLabel(model.tour.name)).toList();

void main() {
  group('sortTourCategoriesForDisplay', () {
    test('puts the live playoff stage above the groups it grew out of', () {
      // The reported bug: Playoffs is under way, yet it sat at the bottom of
      // the popup because its average rating tie-broke against the groups.
      final sorted = sortTourCategoriesForDisplay(
        [
          _tour(
            'Event | 5th-6th',
            dates: [DateTime.utc(2026, 8, 13)],
            avgElo: 2790,
          ),
          _tour(
            'Event | Group C',
            dates: [DateTime.utc(2026, 8, 12)],
            avgElo: 2780,
          ),
          _tour(
            'Event | Group D',
            dates: [DateTime.utc(2026, 8, 12)],
            avgElo: 2775,
          ),
          _tour(
            'Event | Group A',
            dates: [DateTime.utc(2026, 8, 12)],
            avgElo: 2770,
          ),
          _tour(
            'Event | Group B',
            dates: [DateTime.utc(2026, 8, 12)],
            avgElo: 2765,
          ),
          _tour(
            'Event | Playoffs',
            dates: [DateTime.utc(2026, 8, 14, 11)],
            avgElo: 2760,
            status: RoundStatus.live,
          ),
        ],
        now: _now,
      );

      expect(_labels(sorted).first, 'Playoffs');
      expect(_labels(sorted), [
        'Playoffs',
        '5th-6th',
        'Group A',
        'Group B',
        'Group C',
        'Group D',
      ]);
    });

    test('reads a knockout event back to front (Freestyle Las Vegas)', () {
      final sorted = sortTourCategoriesForDisplay(
        [
          _tour(
            'FCGS | Semi-Finals Lower Bracket',
            dates: [DateTime.utc(2025, 7, 19, 21, 10)],
            avgElo: 2801,
          ),
          _tour(
            'FCGS | Intermediate Matches GREEN',
            dates: [DateTime.utc(2025, 7, 19, 18)],
            avgElo: 2792,
          ),
          _tour(
            'FCGS | Grand Final & Match for 3rd-4th',
            dates: [DateTime.utc(2025, 7, 20, 18)],
            avgElo: 2781,
          ),
          _tour(
            'FCGS | Matches for 5th-6th and 7th-8th',
            dates: [DateTime.utc(2025, 7, 20, 18)],
            avgElo: 2771,
          ),
          _tour(
            'FCGS | Quarter-Finals Upper Bracket',
            dates: [DateTime.utc(2025, 7, 17, 18)],
            avgElo: 2764,
          ),
          _tour(
            'FCGS | Round-Robin White',
            dates: [
              DateTime.utc(2025, 7, 16, 18),
              DateTime.utc(2025, 7, 18, 1, 50),
            ],
            avgElo: 2685,
          ),
        ],
        now: _now,
      );

      expect(_labels(sorted), [
        'Grand Final & Match for 3rd-4th',
        'Matches for 5th-6th and 7th-8th',
        'Semi-Finals Lower Bracket',
        'Intermediate Matches GREEN',
        'Quarter-Finals Upper Bracket',
        'Round-Robin White',
      ]);
    });

    test('orders a recurring series newest edition first', () {
      final sorted = sortTourCategoriesForDisplay(
        [
          _tour('Series | VIII', dates: [DateTime.utc(2025, 4, 5)], avgElo: 1909),
          _tour('Series | FINAL', dates: [DateTime.utc(2025, 6, 28)], avgElo: 1787),
          _tour('Series | XII', dates: [DateTime.utc(2025, 5, 3)], avgElo: 1935),
          _tour('Series | X', dates: [DateTime.utc(2025, 4, 19)], avgElo: 1845),
        ],
        now: _now,
      );

      expect(_labels(sorted), ['FINAL', 'XII', 'X', 'VIII']);
    });

    test('keeps the strength ladder for sections that start together', () {
      // 58% of multi-tour events have every category on one date; there the
      // stronger section still belongs on top.
      final sameDay = [DateTime.utc(2025, 7, 15)];
      final sorted = sortTourCategoriesForDisplay(
        [
          _tour('Congress | Minor', dates: sameDay, avgElo: 1519),
          _tour('Congress | Open', dates: sameDay, avgElo: 2180),
          _tour('Congress | Major', dates: sameDay, avgElo: 1776),
        ],
        now: _now,
      );

      expect(_labels(sorted), ['Open', 'Major', 'Minor']);
    });

    test('falls back to a natural label order when strength ties', () {
      final sameDay = [DateTime.utc(2025, 7, 15)];
      final sorted = sortTourCategoriesForDisplay(
        [
          _tour('Open | Boards 21+', dates: sameDay, avgElo: 0),
          _tour('Open | Boards 11-20', dates: sameDay, avgElo: 0),
          _tour('Open | Boards 2-10', dates: sameDay, avgElo: 0),
        ],
        now: _now,
      );

      // Numeric-aware: "2-10" before "11-20", not lexicographically after it.
      expect(_labels(sorted), ['Boards 2-10', 'Boards 11-20', 'Boards 21+']);
    });

    test('reads a same-day A/B/C/D block by letter, not by rating', () {
      // The scramble from the report: four peer groups that drew different
      // fields, listed B/D/E/A because rating decided the order.
      final sameDay = [DateTime.utc(2025, 5, 2)];
      final sorted = sortTourCategoriesForDisplay(
        [
          _tour('Radt | Group B', dates: sameDay, avgElo: 2204),
          _tour('Radt | Group D', dates: sameDay, avgElo: 1884),
          _tour('Radt | Group E', dates: sameDay, avgElo: 1684),
          _tour('Radt | Group A', dates: sameDay, avgElo: 1574),
        ],
        now: _now,
      );

      expect(_labels(sorted), [
        'Group A',
        'Group B',
        'Group D',
        'Group E',
      ]);
    });

    test('reads a norm-tournament series by letter (GM-A before GM-B)', () {
      final sameDay = [DateTime.utc(2025, 6, 1)];
      final sorted = sortTourCategoriesForDisplay(
        [
          _tour('Budapest | GM B', dates: sameDay, avgElo: 2457),
          _tour('Budapest | GM A', dates: sameDay, avgElo: 2452),
          _tour('Budapest | IM C', dates: sameDay, avgElo: 2331),
          _tour('Budapest | IM A', dates: sameDay, avgElo: 2323),
          _tour('Budapest | IM B', dates: sameDay, avgElo: 2308),
        ],
        now: _now,
      );

      expect(_labels(sorted), ['GM A', 'GM B', 'IM A', 'IM B', 'IM C']);
    });

    test('leaves named sections on the strength ladder', () {
      // "Masters"/"Challengers" are names, not indices — no series reordering.
      final sameDay = [DateTime.utc(2025, 2, 3)];
      final sorted = sortTourCategoriesForDisplay(
        [
          _tour('Al Beruniy | Futures', dates: sameDay, avgElo: 2527),
          _tour('Al Beruniy | Masters', dates: sameDay, avgElo: 2585),
          _tour('Al Beruniy | Challengers', dates: sameDay, avgElo: 2555),
        ],
        now: _now,
      );

      expect(_labels(sorted), ['Masters', 'Challengers', 'Futures']);
    });

    test('never lets a series override the event chronology', () {
      final sorted = sortTourCategoriesForDisplay(
        [
          _tour('Event | Group A', dates: [DateTime.utc(2026, 8, 1)], avgElo: 2400),
          _tour('Event | Group B', dates: [DateTime.utc(2026, 8, 3)], avgElo: 2400),
        ],
        now: _now,
      );

      // Different days, so the later group stays on top despite the letters.
      expect(_labels(sorted), ['Group B', 'Group A']);
    });

    test('holds an unstarted stage below stages that already have games', () {
      final sorted = sortTourCategoriesForDisplay(
        [
          _tour(
            'Event | Playoffs',
            dates: [DateTime.utc(2026, 8, 20)],
            avgElo: 2744,
            status: RoundStatus.upcoming,
          ),
          _tour(
            'Event | Group Stage',
            dates: [DateTime.utc(2026, 8, 12)],
            avgElo: 2715,
            status: RoundStatus.live,
          ),
          _tour(
            'Event | Play-in',
            dates: [DateTime.utc(2026, 8, 11)],
            avgElo: 2678,
          ),
        ],
        now: _now,
      );

      expect(_labels(sorted), ['Group Stage', 'Play-in', 'Playoffs']);
    });

    test('lists an all-upcoming event soonest first', () {
      final sorted = sortTourCategoriesForDisplay(
        [
          _tour(
            'Event | Final',
            dates: [DateTime.utc(2026, 9, 5)],
            avgElo: 2700,
            status: RoundStatus.upcoming,
          ),
          _tour(
            'Event | Round Robin',
            dates: [DateTime.utc(2026, 9, 1)],
            avgElo: 2650,
            status: RoundStatus.upcoming,
          ),
        ],
        now: _now,
      );

      expect(_labels(sorted), ['Round Robin', 'Final']);
    });

    test('sinks dateless tours instead of letting them head the list', () {
      final sorted = sortTourCategoriesForDisplay(
        [
          _tour('Event | TCEC', dates: const [], avgElo: 3500),
          _tour(
            'Event | Main',
            dates: [DateTime.utc(2026, 8, 10)],
            avgElo: 2700,
          ),
        ],
        now: _now,
      );

      expect(_labels(sorted), ['Main', 'TCEC']);
    });

    test('is stable and total for identical inputs', () {
      final sameDay = [DateTime.utc(2026, 8, 1)];
      final models = [
        _tour('Event | Same', dates: sameDay, avgElo: 2000, id: 'b'),
        _tour('Event | Same', dates: sameDay, avgElo: 2000, id: 'a'),
      ];

      final sorted = sortTourCategoriesForDisplay(models, now: _now);

      expect(sorted.map((model) => model.tour.id), ['a', 'b']);
      // The source list is never mutated in place.
      expect(models.map((model) => model.tour.id), ['b', 'a']);
    });

    test('passes short lists straight through', () {
      final single = [
        _tour('Event | Only', dates: [DateTime.utc(2026, 8, 1)]),
      ];
      expect(sortTourCategoriesForDisplay(single, now: _now), hasLength(1));
      expect(sortTourCategoriesForDisplay(const [], now: _now), isEmpty);
    });
  });

  group('tourCategoryLabel', () {
    test('keeps the distinguishing tail of a broadcast name', () {
      expect(
        tourCategoryLabel('Esports World Cup 2026 | Playoffs'),
        'Playoffs',
      );
      expect(
        tourCategoryLabel('Esports World Cup 2026 | Group Stage | A'),
        'A',
      );
      expect(tourCategoryLabel('Some Event: Masters'), 'Masters');
    });

    test('removes the exact parent name before a category separator', () {
      const parent = 'Rubinstein Chess Festival 2026';

      expect(
        tourCategoryLabel('$parent - BLITZ Open', groupName: parent),
        'BLITZ Open',
      );
      expect(
        tourCategoryLabel('$parent – Open B', groupName: parent),
        'Open B',
      );
      expect(
        tourCategoryLabel('$parent | Open C', groupName: parent),
        'Open C',
      );
    });

    test('still reduces to the distinguishing tail after stripping the parent', () {
      const parent = 'Esports World Cup 2026';

      // Returning the first segment after the parent would render
      // "Group Stage | A" — longer than the "A" the same name produces with
      // no groupName at all, which is the opposite of the point.
      expect(
        tourCategoryLabel('$parent | Group Stage | A', groupName: parent),
        'A',
      );
      expect(tourCategoryLabel('$parent | Group Stage | A'), 'A');
      expect(
        tourCategoryLabel('$parent - Playoffs: Upper', groupName: parent),
        'Upper',
      );
      expect(
        tourCategoryLabel('$parent - Masters Boards 1-10', groupName: parent),
        'Boards 1-10',
      );
    });

    test('handles parents and children that end at a separator', () {
      // A parent stored with its own trailing dash still matches.
      expect(
        tourCategoryLabel(
          'Rubinstein Chess Festival 2026 - Open B',
          groupName: 'Rubinstein Chess Festival 2026 -',
        ),
        'Open B',
      );
      // Nothing left after the separator: keep the name rather than return an
      // empty chip, and keep it trimmed.
      expect(
        tourCategoryLabel(
          'Rubinstein Chess Festival 2026 - ',
          groupName: 'Rubinstein Chess Festival 2026',
        ),
        'Rubinstein Chess Festival 2026 -',
      );
    });

    test('accepts the other separators broadcasts ship', () {
      const parent = 'Rubinstein Chess Festival 2026';

      expect(tourCategoryLabel('$parent ― Open D', groupName: parent), 'Open D');
      expect(tourCategoryLabel('$parent − Open E', groupName: parent), 'Open E');
      expect(tourCategoryLabel('$parent / Open F', groupName: parent), 'Open F');
      expect(tourCategoryLabel('$parent • Open G', groupName: parent), 'Open G');
    });

    test('does not remove a partial or separator-free parent prefix', () {
      expect(
        tourCategoryLabel(
          'Rubinstein Chess Festival 2026 Open',
          groupName: 'Rubinstein Chess Festival 2026',
        ),
        'Rubinstein Chess Festival 2026 Open',
      );
      expect(
        tourCategoryLabel(
          'Rubinstein Chess Festival 2026 - Open',
          groupName: 'Rubinstein Chess Festival',
        ),
        'Rubinstein Chess Festival 2026 - Open',
      );
    });

    test('recognises board bands and group suffixes without a separator', () {
      expect(tourCategoryLabel('Big Open 2026 Boards 1-10'), 'Boards 1-10');
      expect(tourCategoryLabel('Big Open 2026 Group B'), 'Group B');
    });

    test('leaves an unstructured name whole', () {
      expect(
        tourCategoryLabel('Tata Steel Chess Tournament'),
        'Tata Steel Chess Tournament',
      );
    });
  });

  group('compareLabelsNaturally', () {
    test('reads digit runs as numbers', () {
      expect(compareLabelsNaturally('Board 2', 'Board 11'), lessThan(0));
      expect(compareLabelsNaturally('Board 11', 'Board 2'), greaterThan(0));
      expect(compareLabelsNaturally('U8', 'U10'), lessThan(0));
    });

    test('ignores case and leading zeros', () {
      expect(compareLabelsNaturally('group a', 'GROUP B'), lessThan(0));
      // A naive string compare reads '0' < '9' and gets this backwards.
      expect(compareLabelsNaturally('Round 010', 'Round 9'), greaterThan(0));
    });

    test('does not overflow on absurd digit runs', () {
      final long = '9' * 40;
      final longer = '9' * 41;
      expect(compareLabelsNaturally('R$long', 'R$longer'), lessThan(0));
    });

    test('orders a shorter prefix first', () {
      expect(compareLabelsNaturally('Group', 'Group A'), lessThan(0));
    });
  });
}
