import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/calendar/provider/calendar_month_events_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hamburger_menu/sidebar_month_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _created = DateTime(2026);

GroupBroadcast _broadcast(String id, DateTime? start, DateTime? end) {
  return GroupBroadcast(
    id: id,
    createdAt: _created,
    name: id,
    search: const [],
    dateStart: start,
    dateEnd: end,
  );
}

CalendarEvent _calendarEvent(
  String name,
  DateTime? start,
  DateTime? end, {
  String? fideEventId,
  bool isMajorEvent = false,
  bool isMajorUpcoming = false,
}) {
  return CalendarEvent(
    name: name,
    startDate: start,
    endDate: end,
    createdAt: _created,
    fideEventId: fideEventId,
    isMajorEvent: isMajorEvent,
    isMajorUpcoming: isMajorUpcoming,
  );
}

/// WCAG 2.x contrast of [ink] (composited over [paper]) against [paper].
double _contrast(Color ink, Color paper) {
  final fg = Color.alphaBlend(ink, paper).computeLuminance();
  final bg = paper.computeLuminance();
  final hi = fg > bg ? fg : bg;
  final lo = fg > bg ? bg : fg;
  return (hi + 0.05) / (lo + 0.05);
}

Finder _kings() => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is MajorKingPainter,
);

CalendarMonthEvents _month(
  int year,
  int month, {
  List<GroupBroadcast> broadcasts = const [],
  List<CalendarEvent> calendarEvents = const [],
}) {
  return CalendarMonthEvents(
    year: year,
    month: month,
    broadcasts: broadcasts,
    calendarEvents: calendarEvents,
  );
}

Set<int> _days(List<(DateTime?, DateTime?)> ranges) =>
    calendarEventDaysInMonth(ranges, year: 2026, month: 9);

void main() {
  group('calendarEventDaysInMonth', () {
    test('clips spans that start before or end after the month', () {
      expect(_days([(DateTime(2026, 8, 28), DateTime(2026, 9, 3))]), {1, 2, 3});
      expect(_days([(DateTime(2026, 9, 29), DateTime(2026, 10, 2))]), {29, 30});
      expect(_days([(DateTime(2026, 8), DateTime(2026, 10, 31))]), {
        for (var d = 1; d <= 30; d++) d,
      });
    });

    test('reads a lone date as one day and a reversed pair forwards', () {
      expect(_days([(DateTime(2026, 9, 10), null)]), {10});
      expect(_days([(null, DateTime(2026, 9, 12))]), {12});
      expect(_days([(DateTime(2026, 9, 20), DateTime(2026, 9, 18))]), {
        18,
        19,
        20,
      });
    });

    test('ignores undated events and events outside the month', () {
      expect(_days([(null, null)]), isEmpty);
      expect(_days([(DateTime(2026, 10, 5), DateTime(2026, 10, 9))]), isEmpty);
      expect(_days([(DateTime(2026, 8, 1), DateTime(2026, 8, 31))]), isEmpty);
    });

    test('ignores the time of day', () {
      expect(_days([(DateTime(2026, 9, 4, 23, 59), DateTime(2026, 9, 5))]), {
        4,
        5,
      });
    });

    test('counts days on the local calendar the event cards print', () {
      final utc = DateTime.utc(2026, 9, 15, 12);
      final local = calendarLocalDay(utc);
      expect(_days([(utc, utc)]), {if (local.month == 9) local.day});
    });
  });

  test('calendarEventRunsOn is inclusive at both ends', () {
    final start = DateTime(2026, 9, 21, 14);
    final end = DateTime(2026, 9, 25, 9);
    expect(calendarEventRunsOn(start, end, DateTime(2026, 9, 21)), isTrue);
    expect(calendarEventRunsOn(start, end, DateTime(2026, 9, 23, 18)), isTrue);
    expect(calendarEventRunsOn(start, end, DateTime(2026, 9, 25)), isTrue);
    expect(calendarEventRunsOn(start, end, DateTime(2026, 9, 26)), isFalse);
    expect(calendarEventRunsOn(null, null, DateTime(2026, 9, 23)), isFalse);
  });

  group('majorEventStartDays', () {
    Set<int> starts(List<CalendarEvent> events) =>
        majorEventStartDays(events, year: 2026, month: 9);

    test('rows sharing a FIDE id are one event, dated by its regular row', () {
      // The major scrape only knows the month, so it dates the event to the
      // 1st; the regular FIDE row carries the real start.
      expect(
        starts([
          _calendarEvent(
            'World Cup *',
            DateTime(2026, 9, 1),
            DateTime(2026, 9, 30),
            fideEventId: ' 4242 ',
            isMajorEvent: true,
          ),
          _calendarEvent(
            'FIDE World Cup',
            DateTime(2026, 9, 14),
            DateTime(2026, 9, 29),
            fideEventId: '4242',
          ),
        ]),
        {14},
      );
    });

    test('the upcoming flag counts on any row of the event', () {
      expect(
        starts([
          _calendarEvent(
            'Grand Prix',
            DateTime(2026, 9, 8),
            null,
            fideEventId: '7',
            isMajorUpcoming: true,
          ),
        ]),
        {8},
      );
    });

    test('ignores regular events, undated ones and starts in other months', () {
      expect(
        starts([
          _calendarEvent('Open', DateTime(2026, 9, 3), null),
          _calendarEvent('Undated', null, null, isMajorEvent: true),
          _calendarEvent(
            'Began in August',
            DateTime(2026, 8, 28),
            DateTime(2026, 9, 6),
            isMajorEvent: true,
          ),
        ]),
        isEmpty,
      );
    });

    test('without a FIDE id each dated title stands alone', () {
      expect(
        starts([
          _calendarEvent('Olympiad', DateTime(2026, 9, 20), null),
          _calendarEvent(
            'Olympiad',
            DateTime(2026, 9, 22),
            null,
            isMajorEvent: true,
          ),
        ]),
        {22},
      );
    });
  });

  test('a month merges broadcast and calendar-event days', () {
    final month = _month(
      2026,
      9,
      broadcasts: [_broadcast('b', DateTime(2026, 9, 2), DateTime(2026, 9, 3))],
      calendarEvents: [_calendarEvent('c', DateTime(2026, 9, 3), null)],
    );
    expect(month.eventDays, {2, 3});
  });

  group('SidebarMonthCalendar', () {
    late List<(int, int)> requested;
    late List<DateTime> tappedDays;
    late int fullCalendarOpens;

    final fixtures = <(int, int), CalendarMonthEvents>{
      (2026, 9): _month(
        2026,
        9,
        broadcasts: [
          _broadcast('open', DateTime(2026, 9, 4), DateTime(2026, 9, 6)),
        ],
        calendarEvents: [_calendarEvent('cup', DateTime(2026, 9, 18), null)],
      ),
      (2026, 10): _month(
        2026,
        10,
        broadcasts: [
          _broadcast('oct', DateTime(2026, 10, 2), DateTime(2026, 10, 2)),
        ],
      ),
    };

    Future<void> pump(WidgetTester tester) async {
      requested = [];
      tappedDays = [];
      fullCalendarOpens = 0;
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            availableYearsProvider.overrideWith(
              (ref) => const [2025, 2026, 2027],
            ),
            calendarMonthEventsProvider.overrideWith((ref, args) async {
              requested.add((args.year, args.month));
              return fixtures[(args.year, args.month)] ??
                  _month(args.year, args.month);
            }),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [AppColors.dark],
            ),
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 260,
                      child: ListView(
                        children: [
                          SidebarMonthCalendar(
                            today: DateTime(2026, 9, 23, 15, 30),
                            onDaySelected: tappedDays.add,
                            onOpenFullCalendar: () => fullCalendarOpens++,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder day(int year, int month, int d) =>
        find.byKey(ValueKey('sidebar_day_$year-$month-$d'));

    BoxDecoration decorationOf(WidgetTester tester, Finder cell) {
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: cell, matching: find.byType(DecoratedBox)).first,
      );
      return box.decoration as BoxDecoration;
    }

    String titleText(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('sidebar_calendar_title')))
        .data!;

    testWidgets('opens on the current month and loads only that month', (
      tester,
    ) async {
      await pump(tester);

      expect(titleText(tester), 'September 2026');
      expect(requested, [(2026, 9)]);
      // A full month of days and nothing from its neighbours.
      for (var d = 1; d <= 30; d++) {
        expect(day(2026, 9, d), findsOneWidget);
      }
      expect(day(2026, 8, 31), findsNothing);
      expect(day(2026, 10, 1), findsNothing);
    });

    testWidgets('completes the weeks with faint, inert neighbour dates', (
      tester,
    ) async {
      await pump(tester);

      // September 2026 opens on a Tuesday and needs five weeks; the sixth is
      // filled from October so the block never shows a dead row.
      final august31 = find.text('31');
      expect(august31, findsOneWidget);
      // A step under a quiet day, and still AA on the drawer.
      final spillInk = tester.widget<Text>(august31).style!.color!;
      expect(spillInk.a, closeTo(0.47, 0.001));
      expect(
        _contrast(spillInk, AppColors.dark.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(find.text('10'), findsNWidgets(2), reason: 'Sep 10 and Oct 10');

      await tester.tap(august31);
      await tester.pump();
      expect(tappedDays, isEmpty);
      expect(requested, [(2026, 9)]);
    });

    testWidgets('lifts event days onto a tonal cell and edges today', (
      tester,
    ) async {
      await pump(tester);

      final surface = AppColors.dark.surface;
      for (final d in [4, 5, 6, 18]) {
        expect(decorationOf(tester, day(2026, 9, d)).color, surface);
      }
      final quiet = decorationOf(tester, day(2026, 9, 10));
      expect(quiet.color!.a, 0);
      expect(quiet.border, isNull);

      final today = decorationOf(tester, day(2026, 9, 23));
      expect(today.border, isNotNull);
      expect(today.color!.a, 0, reason: 'no events on the 23rd');

      final eventDigit = tester.widget<Text>(
        find.descendant(of: day(2026, 9, 5), matching: find.byType(Text)),
      );
      final quietDigit = tester.widget<Text>(
        find.descendant(of: day(2026, 9, 10), matching: find.byType(Text)),
      );
      expect(eventDigit.style!.fontWeight, FontWeight.w600);
      expect(eventDigit.style!.color!.a, closeTo(1, 0.001));
      expect(quietDigit.style!.color!.a, closeTo(0.65, 0.001));

      expect(
        tester.getSemantics(day(2026, 9, 5)).label,
        allOf(contains('5 September'), contains('has events')),
      );
      expect(
        tester.getSemantics(day(2026, 9, 23)).label,
        allOf(contains('today'), contains('no events')),
      );
    });

    testWidgets('tapping a day hands back that date; Full calendar opens', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(day(2026, 9, 18));
      await tester.pump();
      expect(tappedDays, [DateTime(2026, 9, 18)]);

      await tester.tap(find.byKey(const ValueKey('sidebar_calendar_full')));
      await tester.pump();
      expect(fullCalendarOpens, 1);
    });

    testWidgets('month change slides with both months drawn mid-way', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byTooltip('Next month'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(titleText(tester), 'October 2026');
      expect(day(2026, 9, 30), findsOneWidget);
      expect(day(2026, 10, 1), findsOneWidget);
      // Nothing fades: the outgoing month keeps its marks while it leaves.
      expect(
        decorationOf(tester, day(2026, 9, 5)).color,
        AppColors.dark.surface,
      );

      await tester.pumpAndSettle();
      expect(day(2026, 9, 30), findsNothing);
      expect(requested, [(2026, 9), (2026, 10)]);
      expect(
        decorationOf(tester, day(2026, 10, 2)).color,
        AppColors.dark.surface,
      );

      // Back again is served from the cache the grid kept.
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(titleText(tester), 'September 2026');
    });

    testWidgets('stops at the years the full calendar offers', (tester) async {
      await pump(tester);

      final next = find.byTooltip('Next month');
      for (var i = 0; i < 15; i++) {
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      expect(titleText(tester), 'December 2027');
      final nextButton = tester.widget<IconButton>(
        find.ancestor(of: next, matching: find.byType(IconButton)).first,
      );
      expect(nextButton.onPressed, isNull);

      final previous = find.byTooltip('Previous month');
      for (var i = 0; i < 35; i++) {
        await tester.tap(previous);
        await tester.pumpAndSettle();
      }
      expect(titleText(tester), 'January 2025');
      final previousButton = tester.widget<IconButton>(
        find.ancestor(of: previous, matching: find.byType(IconButton)).first,
      );
      expect(previousButton.onPressed, isNull);
    });
  });

  group('SidebarMonthCalendar major events', () {
    final month = _month(
      2026,
      9,
      broadcasts: [
        _broadcast('open', DateTime(2026, 9, 4), DateTime(2026, 9, 6)),
      ],
      calendarEvents: [
        _calendarEvent(
          'Candidates *',
          DateTime(2026, 9, 1),
          null,
          fideEventId: '99',
          isMajorEvent: true,
        ),
        _calendarEvent(
          'FIDE Candidates',
          DateTime(2026, 9, 16),
          DateTime(2026, 9, 30),
          fideEventId: '99',
        ),
        // Starts on the last column of the first week: the badge must clear
        // the grid's right edge and top edge alike.
        _calendarEvent(
          'Continental',
          DateTime(2026, 9, 5),
          null,
          isMajorUpcoming: true,
        ),
      ],
    );

    Future<void> pump(
      WidgetTester tester, {
      required ThemeData theme,
      required AppColors colors,
      double width = 260,
      double textScale = 1,
    }) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            availableYearsProvider.overrideWith((ref) => const [2026]),
            calendarMonthEventsProvider.overrideWith((ref, args) async {
              return args.year == 2026 && args.month == 9
                  ? month
                  : _month(args.year, args.month);
            }),
          ],
          child: MaterialApp(
            theme: theme.copyWith(extensions: [colors]),
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: Scaffold(
                    backgroundColor: colors.background,
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width,
                        child: SingleChildScrollView(
                          child: SidebarMonthCalendar(
                            today: DateTime(2026, 9, 23, 15, 30),
                            onDaySelected: (_) {},
                            onOpenFullCalendar: () {},
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder day(int d) => find.byKey(ValueKey('sidebar_day_2026-9-$d'));

    testWidgets('a king leans on each start day, and only there', (
      tester,
    ) async {
      await pump(tester, theme: ThemeData.dark(), colors: AppColors.dark);

      expect(_kings(), findsNWidgets(2));
      expect(
        find.descendant(of: day(16), matching: _kings()),
        findsOneWidget,
      );
      expect(find.descendant(of: day(5), matching: _kings()), findsOneWidget);
      // The major row's guessed 1st is not a start; nor are running days.
      expect(find.descendant(of: day(1), matching: _kings()), findsNothing);
      expect(find.descendant(of: day(17), matching: _kings()), findsNothing);

      final king = tester.widget<CustomPaint>(
        find.descendant(of: day(16), matching: _kings()),
      );
      final painter = king.painter! as MajorKingPainter;
      expect(painter.ink, AppColors.dark.accentText);
      // Settled: leaning into the day, not upright.
      expect(painter.lean, lessThan(-0.2));

      expect(
        tester.getSemantics(day(16)).label,
        allOf(contains('16 September'), contains('major event starts')),
      );
      expect(
        tester.getSemantics(day(17)).label,
        isNot(contains('major event')),
      );
      // The badge is drawn, not written: the cell still holds one number.
      expect(
        find.descendant(of: day(16), matching: find.byType(Text)),
        findsOneWidget,
      );
    });

    testWidgets(
      'on the 360dp phone at 1.3x text the king stands on the corner, '
      'above the figures and inside the grid clip',
      (tester) async {
        // The view itself: the helpers size the grid and the figures from
        // MediaQuery, which follows the view, not the test surface.
        tester.view
          ..physicalSize = const Size(360, 800) * 3
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await pump(
          tester,
          theme: ThemeData.light(),
          colors: AppColors.light,
          width: 238,
          textScale: 1.3,
        );

        Rect badgeOf(int d) =>
            tester.getRect(find.descendant(of: day(d), matching: _kings()));

        for (final d in [5, 16]) {
          final cell = tester.getRect(
            find
                .descendant(of: day(d), matching: find.byType(DecoratedBox))
                .first,
          );
          final badge = badgeOf(d);
          // Rises past the top edge and hangs off the right one, with its
          // base in the band above the figures. (The pixel clearance is
          // pinned in sidebar_major_king_clearance_test.dart.)
          expect(badge.top, lessThan(cell.top));
          expect(badge.right, greaterThan(cell.right));
          expect(badge.bottom, lessThan(cell.top + cell.height * 0.3));
        }

        // The 5th is a Saturday in the first week: top row, last column.
        final clipBox = tester.renderObject<RenderClipRect>(
          find.ancestor(of: day(5), matching: find.byType(ClipRect)).first,
        );
        final clip = clipBox.clipper!
            .getClip(clipBox.size)
            .shift(clipBox.localToGlobal(Offset.zero));
        final cell5 = tester.getRect(
          find.descendant(of: day(5), matching: find.byType(DecoratedBox)).first,
        );
        expect(clip.top, lessThanOrEqualTo(badgeOf(5).top));
        expect(clip.right, greaterThanOrEqualTo(cell5.right + 2));
      },
    );

    for (final (name, theme, colors) in [
      ('light', ThemeData.light(), AppColors.light),
      ('dark', ThemeData.dark(), AppColors.dark),
    ]) {
      testWidgets('$name: day, weekday, today and king ink clear AA', (
        tester,
      ) async {
        await pump(tester, theme: theme, colors: colors);
        final paper = colors.background;

        Color digitInk(int d) => tester
            .widget<Text>(
              find.descendant(of: day(d), matching: find.byType(Text)),
            )
            .style!
            .color!;

        // A quiet day, an event day (on its lifted cell) and today.
        expect(_contrast(digitInk(10), paper), greaterThanOrEqualTo(4.5));
        // A neighbouring month's date: the faintest step, still AA, and a
        // clear step under a quiet day.
        final spill = tester.widget<Text>(find.text('31')).style!.color!;
        expect(_contrast(spill, paper), greaterThanOrEqualTo(4.5));
        expect(
          _contrast(digitInk(10), paper),
          greaterThan(_contrast(spill, paper) * 1.6),
        );
        expect(
          _contrast(digitInk(5), colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(_contrast(digitInk(23), paper), greaterThanOrEqualTo(4.5));

        final weekday = tester
            .widgetList<Text>(find.byType(Text))
            .firstWhere(
              (t) => t.data != null && RegExp(r'^[A-Z]$').hasMatch(t.data!),
            );
        expect(
          _contrast(weekday.style!.color!, paper),
          greaterThanOrEqualTo(4.5),
        );

        final todayEdge =
            (tester
                        .widget<DecoratedBox>(
                          find
                              .descendant(
                                of: day(23),
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration)
                .border!
                .top
                .color;
        expect(_contrast(todayEdge, paper), greaterThanOrEqualTo(3));

        final king =
            tester
                    .widget<CustomPaint>(
                      find.descendant(of: day(5), matching: _kings()),
                    )
                    .painter!
                as MajorKingPainter;
        expect(_contrast(king.ink, paper), greaterThanOrEqualTo(3));
        expect(_contrast(king.ink, colors.surface), greaterThanOrEqualTo(3));
      });
    }
  });
}
