import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/calendar/provider/calendar_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  for (final theme in <(String, ThemeData)>[
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    testWidgets(
      'Calendar stays usable on a narrow ${theme.$1} screen with large text',
      (tester) async {
        final harness = await _pumpCalendar(
          tester,
          theme: theme.$2,
          size: const Size(320, 700),
          textScaler: const TextScaler.linear(2),
        );

        expect(find.byType(GlassFullScreenPage), findsOneWidget);
        expect(find.byType(CustomScrollView), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('calendar-floating-controls')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        for (final key in <String>[
          'calendar-year-picker',
          'calendar-time-control-picker',
          'calendar-filter-months',
          'calendar-filter-upcoming',
          'calendar-filter-favorites',
        ]) {
          final size = tester.getSize(find.byKey(ValueKey<String>(key)));
          expect(size.height, greaterThanOrEqualTo(48), reason: key);
        }

        expect(
          harness.container.read(calendarFilterModeProvider),
          CalendarFilterMode.all,
        );
      },
    );
  }

  testWidgets('search and quick filters update the existing providers', (
    tester,
  ) async {
    final harness = await _pumpCalendar(tester);

    await tester.tap(find.byKey(e2eKey(E2eIds.calendarSearchField)));
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(EditableText), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'Candidates');
    await tester.pump();
    expect(harness.container.read(calendarSearchQueryProvider), 'Candidates');

    final upcoming = find.byKey(
      const ValueKey<String>('calendar-filter-upcoming'),
    );
    await tester.ensureVisible(upcoming);
    await tester.tap(upcoming);
    await tester.pump();
    expect(
      harness.container.read(calendarFilterModeProvider),
      CalendarFilterMode.upcoming,
    );

    await tester.tap(upcoming);
    await tester.pump();
    expect(
      harness.container.read(calendarFilterModeProvider),
      CalendarFilterMode.all,
    );
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('month cards preserve month selection and named routing', (
    tester,
  ) async {
    final harness = await _pumpCalendar(tester);
    final month = DateTime.now().month;
    final monthName = _monthNames[month - 1];

    await tester.tap(find.text(monthName).first);
    await tester.pumpAndSettle();

    expect(harness.container.read(selectedMonthProvider), month);
    expect(find.text('Month detail'), findsOneWidget);
  });

  testWidgets('repository failures keep a readable retry path', (tester) async {
    final groupRepository = _CalendarGroupRepository(throwsOnLoad: true);
    await _pumpCalendar(tester, groupRepository: groupRepository);

    expect(find.text('Calendar unavailable'), findsOneWidget);
    expect(find.text('Retry calendar'), findsOneWidget);
    expect(groupRepository.yearRequests, 1);

    await tester.tap(find.text('Retry calendar'));
    await tester.pump();
    await _pumpUntil(tester, find.text('Calendar unavailable'));
    expect(groupRepository.yearRequests, 2);
  });
}

class _CalendarHarness {
  const _CalendarHarness(this.container);

  final ProviderContainer container;
}

Future<_CalendarHarness> _pumpCalendar(
  WidgetTester tester, {
  ThemeData? theme,
  Size size = const Size(393, 852),
  TextScaler textScaler = TextScaler.noScaling,
  _CalendarGroupRepository? groupRepository,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final groups = groupRepository ?? _CalendarGroupRepository();
  final container = ProviderContainer(
    overrides: <Override>[
      groupBroadcastRepositoryProvider.overrideWithValue(groups),
      calendarEventRepositoryProvider.overrideWithValue(
        _CalendarEventRepository(),
      ),
      liveGroupBroadcastIdsProvider.overrideWith(
        (_) => Stream<List<String>>.value(const <String>[]),
      ),
      favoriteEventsProvider.overrideWith(_EmptyFavoriteEventsNotifier.new),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: LiquidGlassWidgets.wrap(
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          routes: <String, WidgetBuilder>{
            '/calendar_detail_screen':
                (_) =>
                    const Scaffold(body: Center(child: Text('Month detail'))),
          },
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: textScaler, disableAnimations: true),
                child: const CalendarScreen(),
              );
            },
          ),
        ),
      ),
    ),
  );
  await _pumpUntil(
    tester,
    groupRepository?.throwsOnLoad == true
        ? find.text('Calendar unavailable')
        : find.byKey(const ValueKey<String>('calendar-data-state')),
  );
  await tester.pump(const Duration(milliseconds: 600));
  return _CalendarHarness(container);
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

class _CalendarGroupRepository implements GroupBroadcastRepository {
  _CalendarGroupRepository({this.throwsOnLoad = false});

  final bool throwsOnLoad;
  int yearRequests = 0;

  @override
  Future<List<GroupBroadcast>> getGroupBroadcastsForYear({
    required int year,
    int limit = 500,
    String orderBy = 'date_start',
    bool ascending = true,
  }) async {
    yearRequests += 1;
    if (throwsOnLoad) throw StateError('calendar unavailable');
    return const <GroupBroadcast>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CalendarEventRepository implements CalendarEventRepository {
  @override
  Future<List<CalendarEvent>> getCalendarEventsForYear({
    required int year,
    int limit = 500,
    String orderBy = 'start_date',
    bool ascending = true,
  }) async => const <CalendarEvent>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyFavoriteEventsNotifier extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const <FavoriteEvent>[];
}

const _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
