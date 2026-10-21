import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_overview_tab.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A small career: two clocks, both colours, three opponents, three years.
List<PrepGame> _career() {
  var index = 0;
  PrepGame game(
    String result, {
    required bool white,
    required String eco,
    required String opponent,
    required int year,
    PrepTimeControl speed = PrepTimeControl.blitz,
    int plies = 60,
  }) => PrepGame(
    index: index++,
    source: PrepSource.lichess,
    sourcePath: '/prep/lichess.pgn',
    white: white ? 'Hero' : opponent,
    black: white ? opponent : 'Hero',
    result: result,
    plies: plies,
    playerIsWhite: white,
    whiteElo: 2000,
    blackElo: 2000,
    eco: eco,
    speed: speed,
    date: DateTime.utc(year, 5, 1 + index % 27),
  );
  return [
    // Blitz with White: the Italian, mostly won.
    for (var i = 0; i < 6; i++)
      game(
        i < 4 ? '1-0' : '0-1',
        white: true,
        eco: 'C50',
        opponent: 'Anna',
        year: 2024,
      ),
    // Blitz with Black: the Sicilian, evenly.
    for (var i = 0; i < 4; i++)
      game(
        i.isEven ? '0-1' : '1-0',
        white: false,
        eco: 'B90',
        opponent: 'Boris',
        year: 2023,
      ),
    // Classical: one opening with each colour, drawn, in long games.
    for (var i = 0; i < 2; i++)
      game(
        '1/2-1/2',
        white: true,
        eco: 'D37',
        opponent: 'Clara',
        year: 2022,
        speed: PrepTimeControl.classical,
        plies: 120,
      ),
    game(
      '1/2-1/2',
      white: false,
      eco: 'E60',
      opponent: 'Clara',
      year: 2022,
      speed: PrepTimeControl.classical,
      plies: 120,
    ),
  ];
}

void main() {
  group('About counts each group of choices without its own', () {
    late PrepFacets facets;
    setUp(() => facets = PrepFacets(_career()));

    test('nothing chosen is the plain statistics', () {
      final plain = PrepStats.of(_career());
      final s = const PrepFilter().stats(facets);
      expect(s.matching, 13);
      expect(s.games, plain.games);
      expect(s.overall.wins, plain.overall.wins);
      expect(s.overall.draws, plain.overall.draws);
      expect(s.overall.losses, plain.overall.losses);
      expect(
        s.whiteOpenings.map((l) => (l.eco, l.games)),
        plain.whiteOpenings.map((l) => (l.eco, l.games)),
      );
      expect(s.clocks, plain.clocks);
    });

    test('a clock narrows everything but the clocks', () {
      final s = const PrepFilter(
        speed: PrepTimeControl.classical,
      ).stats(facets);
      expect(s.matching, 3);
      expect(s.overall.draws, 3);
      expect(s.overall.wins, 0);
      expect(s.whiteOpenings.map((l) => l.eco), ['D37']);
      expect(s.blackOpenings.map((l) => l.eco), ['E60']);
      expect(s.opponents.map((o) => o.name), ['Clara']);
      expect(s.byYear.map((y) => y.year), [2022]);
      expect(s.lengths, [0, 0, 0, 0, 3]);
      // The other clock stays beside the chosen one, to be taken instead.
      expect(s.clocks, [
        (PrepTimeControl.blitz, 10),
        (PrepTimeControl.classical, 3),
      ]);
    });

    test('a result keeps the other results to choose from', () {
      final s = const PrepFilter(outcome: PrepOutcome.win).stats(facets);
      // Six wins are left for Games, counted out of all thirteen.
      expect(s.matching, 6);
      expect(s.games, 13);
      expect(s.overall.wins, 6);
      expect(s.overall.draws, 3);
      expect(s.overall.losses, 4);
      // Everything else is of the wins alone.
      expect(s.whiteGames, 4);
      expect(s.blackGames, 2);
      expect(s.opponents.map((o) => (o.name, o.games)), [
        ('Anna', 4),
        ('Boris', 2),
      ]);
      // One result alone scores all or nothing: no performance to name.
      expect(s.performance, isNull);
    });

    test('a colour keeps the other colour, and both lists of openings', () {
      final s = const PrepFilter(side: PrepSide.black).stats(facets);
      expect(s.matching, 5);
      expect(s.overall.total, 5);
      expect(s.whiteGames, 8);
      expect(s.blackGames, 5);
      expect(s.whiteOpenings.map((l) => l.eco), ['C50', 'D37']);
      expect(s.blackOpenings.map((l) => l.eco), ['B90', 'E60']);
      expect(s.opponents.map((o) => o.name), ['Boris', 'Clara']);
    });

    test('an opening keeps its list, and is one of a colour', () {
      const filter = PrepFilter();
      final taken = filter.toggleOpening(PrepSide.white, 'C50');
      expect(taken.side, PrepSide.white);
      expect(taken.holdsOpening(PrepSide.white, 'c50'), isTrue);
      expect(taken.holdsOpening(PrepSide.black, 'C50'), isFalse);
      final s = taken.stats(facets);
      expect(s.matching, 6);
      expect(s.overall.wins, 4);
      expect(s.whiteOpenings.map((l) => l.eco), ['C50', 'D37']);
      expect(s.blackOpenings.map((l) => l.eco), ['B90', 'E60']);
      expect(s.opponents.map((o) => o.name), ['Anna']);
      // Given up, the opening goes and its colour stays.
      final left = taken.toggleOpening(PrepSide.white, 'C50');
      expect(left.eco, isNull);
      expect(left.side, PrepSide.white);
      // Another colour taken drops the line chosen under the first.
      expect(taken.toggleSide(PrepSide.black).eco, isNull);
    });

    test('what is chosen keeps a row where the other choices leave it no '
        'games', () {
      // The Italian was never played at the slow clock.
      final s = const PrepFilter(
        side: PrepSide.white,
        eco: 'C50',
        opponent: 'Anna',
        year: 2024,
        speed: PrepTimeControl.classical,
      ).stats(facets);
      expect(s.matching, 0);
      final line = s.whiteOpenings.singleWhere((l) => l.eco == 'C50');
      expect(line.games, 0);
      expect(s.opponents.singleWhere((o) => o.name == 'Anna').games, 0);
      expect(s.byYear.singleWhere((y) => y.year == 2024).total, 0);
      // A choice these games never had is still there to give up.
      final absent = const PrepFilter(
        eco: 'A00',
        opponent: 'Nobody',
        year: 1999,
        speed: PrepTimeControl.bullet,
      ).stats(facets);
      expect(absent.matching, 0);
      expect(absent.whiteOpenings.map((l) => l.eco), contains('A00'));
      expect(absent.opponents.map((o) => o.name), contains('Nobody'));
      expect(absent.byYear.map((y) => y.year), contains(1999));
      expect(absent.clocks, contains((PrepTimeControl.bullet, 0)));
    });

    test('a length is a choice like the rest', () {
      final long = const PrepFilter().toggleLength(4);
      final s = long.stats(facets);
      expect(s.matching, 3);
      expect(s.lengths, [0, 10, 0, 0, 3]);
      expect(long.labels, ['50+ moves']);
      expect(long.apply(_career()), hasLength(3));
      expect(long.toggleLength(4).length, isNull);
    });

    test('the Games filters are what every choice is made within', () {
      final recent = PrepFilter(
        base: GameFilter().copyWith(minYear: 2023),
        outcome: PrepOutcome.win,
      );
      final s = recent.stats(facets);
      expect(s.games, 10);
      expect(s.matching, 6);
      expect(s.byYear.map((y) => y.year), [2023, 2024]);
      expect(s.matching, recent.apply(_career()).length);
    });

    test('every count agrees with the games the Games tab lists', () {
      final games = _career();
      const picks = [
        PrepFilter(speed: PrepTimeControl.blitz, side: PrepSide.white),
        PrepFilter(opponent: 'boris', outcome: PrepOutcome.loss),
        PrepFilter(year: 2022, eco: 'd37', side: PrepSide.white),
        PrepFilter(length: 1, outcome: PrepOutcome.win, year: 2024),
      ];
      for (final filter in picks) {
        expect(
          filter.stats(facets).matching,
          filter.apply(games).length,
          reason: filter.summary,
        );
      }
    });
  });

  testWidgets('choices move on their springs without an error, and the '
      'banner opens and closes over the statistics', (tester) async {
    final games = _career();
    final facets = PrepFacets(games);
    var filter = const PrepFilter();
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) {
          ResponsiveHelper.init(context);
          return child!;
        },
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PrepOverviewTab(
              profile: const PrepProfile(
                id: 'p',
                kind: PrepKind.mine,
                name: 'Hero',
                createdAtMs: 1,
              ),
              stats: filter.stats(facets),
              total: games.length,
              filter: filter,
              onFilterChanged: (next) => setState(() => filter = next),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    const banner = ValueKey('prep_filter_banner');
    expect(find.byKey(banner), findsNothing);
    final summaryAt = tester.getRect(find.text('Games analyzed'));

    await tester.tap(find.text('Wins'));
    // The first frame moves nothing: the banner has yet to open.
    await tester.pump();
    expect(tester.getRect(find.text('Games analyzed')), summaryAt);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(filter.outcome, PrepOutcome.win);
    expect(find.byKey(banner), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('prep_filter_count'))).data,
      '6 of 13',
    );
    expect(
      tester.getRect(find.text('Games analyzed')).top,
      greaterThan(summaryAt.top),
    );

    // Every kind of choice, taken and given up.
    await tester.tap(find.text('Performance by colour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('As Black'));
    await tester.pumpAndSettle();
    expect(filter.side, PrepSide.black);
    await tester.tap(find.text('As Black').last);
    await tester.pumpAndSettle();
    expect(filter.side, PrepSide.both);
    await tester.tap(find.text('Wins').last);
    await tester.pumpAndSettle();
    expect(filter.narrows, isFalse);
    expect(find.byKey(banner), findsNothing);
    expect(tester.getRect(find.text('Games analyzed')), summaryAt);

    await tester.ensureVisible(find.text('More statistics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More statistics'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text("'23"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("'23"));
    await tester.pumpAndSettle();
    expect(filter.year, 2023);
    await tester.ensureVisible(find.text('50+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('50+'));
    await tester.pumpAndSettle();
    expect(filter.length, 4);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('prep_filter_count'))).data,
      '0 of 13',
    );
    expect(tester.takeException(), isNull);
  });
}
