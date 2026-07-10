import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/calendar/calendar_detail_screen.dart';
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
  for (final configuration in <_Configuration>[
    _Configuration(
      label: 'narrow light with large text',
      theme: AppTheme.lightTheme,
      size: Size(320, 700),
      textScaler: TextScaler.linear(2),
    ),
    _Configuration(
      label: 'tablet dark',
      theme: AppTheme.darkTheme,
      size: Size(1024, 900),
      textScaler: TextScaler.noScaling,
    ),
  ]) {
    testWidgets('month results remain usable on ${configuration.label}', (
      tester,
    ) async {
      final harness = await _pumpDetail(
        tester,
        theme: configuration.theme,
        size: configuration.size,
        textScaler: configuration.textScaler,
      );

      expect(find.byType(GlassFullScreenPage), findsOneWidget);
      expect(find.byKey(e2eKey(E2eIds.calendarDetailRoot)), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('calendar-detail-floating-controls')),
        findsOneWidget,
      );
      expect(find.text('July 2026'), findsOneWidget);
      expect(find.text('No tournaments found'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final controls = tester.getSize(
        find.byKey(const ValueKey<String>('calendar-detail-floating-controls')),
      );
      expect(controls.height, greaterThanOrEqualTo(48));
      expect(harness.container.read(selectedMonthProvider), 7);
      expect(harness.container.read(selectedYearProvider), 2026);
    });
  }

  testWidgets('persisted search opens expanded and updates the shared query', (
    tester,
  ) async {
    final harness = await _pumpDetail(tester, initialSearch: 'Candidates');

    expect(find.byType(EditableText), findsOneWidget);
    expect(find.text('Candidates'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'Open');
    await tester.pump();
    expect(harness.container.read(calendarSearchQueryProvider), 'Open');
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 600));
  });
}

class _Configuration {
  const _Configuration({
    required this.label,
    required this.theme,
    required this.size,
    required this.textScaler,
  });

  final String label;
  final ThemeData theme;
  final Size size;
  final TextScaler textScaler;
}

class _Harness {
  const _Harness(this.container);

  final ProviderContainer container;
}

Future<_Harness> _pumpDetail(
  WidgetTester tester, {
  ThemeData? theme,
  Size size = const Size(393, 852),
  TextScaler textScaler = TextScaler.noScaling,
  String initialSearch = '',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: <Override>[
      groupBroadcastRepositoryProvider.overrideWithValue(
        _EmptyGroupRepository(),
      ),
      calendarEventRepositoryProvider.overrideWithValue(
        _EmptyCalendarRepository(),
      ),
      liveGroupBroadcastIdsProvider.overrideWith(
        (_) => Stream<List<String>>.value(const <String>[]),
      ),
      favoriteEventsProvider.overrideWith(_EmptyFavoriteEventsNotifier.new),
    ],
  );
  addTearDown(container.dispose);
  container.read(selectedMonthProvider.notifier).state = 7;
  container.read(selectedYearProvider.notifier).state = 2026;
  container.read(calendarSearchQueryProvider.notifier).state = initialSearch;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: LiquidGlassWidgets.wrap(
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: textScaler, disableAnimations: true),
                child: const CalendarDetailsScreen(),
              );
            },
          ),
        ),
      ),
    ),
  );

  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find
        .byKey(const ValueKey<String>('calendar-detail-data'))
        .evaluate()
        .isNotEmpty) {
      break;
    }
  }
  expect(
    find.byKey(const ValueKey<String>('calendar-detail-data')),
    findsOneWidget,
  );
  await tester.pump(const Duration(milliseconds: 600));
  return _Harness(container);
}

class _EmptyGroupRepository implements GroupBroadcastRepository {
  @override
  Future<List<GroupBroadcast>> getCurrentMonthGroupBroadcasts({
    required int selectedMonth,
    required int selectedYear,
    int limit = 50,
    int? offset,
    String orderBy = 'date_end',
    bool ascending = false,
  }) async => const <GroupBroadcast>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyCalendarRepository implements CalendarEventRepository {
  @override
  Future<List<CalendarEvent>> getCalendarEventsForMonth({
    required int selectedMonth,
    required int selectedYear,
    int limit = 100,
    int? offset,
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
