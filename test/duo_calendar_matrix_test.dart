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
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'fixtures/duo_window_matrix.dart';

void main() {
  for (final window in duoWindowCases) {
    for (final light in [false, true]) {
      testWidgets('Calendar month grid cold starts in ${window.name}, '
          '${light ? 'light' : 'dark'}', (tester) async {
        await _pump(tester, window, light: light);
        expect(find.byType(GridView), findsOneWidget);
        expect(tester.takeException(), isNull);
        final grid = tester.widget<GridView>(find.byType(GridView));
        expect(grid.childrenDelegate.estimatedChildCount, 12);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  for (final transition in duoWindowTransitions) {
    testWidgets('Calendar retains query, year, and route: '
        '${transition.from.name} to ${transition.to.name}', (tester) async {
      await _pump(tester, transition.from);
      final state = tester.state(find.byType(CalendarScreen));
      final field = tester.widget<TextField>(find.byType(TextField));
      final controller = field.controller!;
      await tester.enterText(find.byType(TextField), 'championship');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 600));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CalendarScreen)),
      );
      final year = container.read(selectedYearProvider);
      expect(container.read(calendarSearchQueryProvider), 'championship');

      applyDuoWindow(tester, transition.to, mirrorInsets: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.state(find.byType(CalendarScreen)), same(state));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller,
        same(controller),
      );
      expect(controller.text, 'championship');
      expect(container.read(calendarSearchQueryProvider), 'championship');
      expect(container.read(selectedYearProvider), year);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  DuoWindowCase window, {
  bool light = false,
}) async {
  tester.view.devicePixelRatio = 3;
  applyDuoWindow(tester, window);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        calendarEventRepositoryProvider.overrideWithValue(
          _CalendarRepository(),
        ),
        groupBroadcastRepositoryProvider.overrideWithValue(_GroupRepository()),
        favoriteEventsProvider.overrideWith(_NoFavorites.new),
        liveGroupBroadcastIdsProvider.overrideWith(
          (ref) => Stream.value(const <String>[]),
        ),
      ],
      child: MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.3)),
          child: AdaptiveWindowScope(child: child!),
        ),
        home: const CalendarScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

class _CalendarRepository implements CalendarEventRepository {
  @override
  Future<List<CalendarEvent>> getCalendarEventsForYear({
    required int year,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GroupRepository implements GroupBroadcastRepository {
  @override
  Future<List<GroupBroadcast>> getGroupBroadcastsForYear({
    required int year,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoFavorites extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const [];
}
