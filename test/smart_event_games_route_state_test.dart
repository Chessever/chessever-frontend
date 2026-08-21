import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _LoadedAggregateNotifier extends SmartAggregateEventNotifier {
  _LoadedAggregateNotifier(super.ref, super.query) {
    state = const AsyncValue.data(SmartAggregateEvent.empty);
  }
}

class _TestBoardSettingsNotifier extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _TestFavoriteEventsNotifier extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const [];
}

SmartEventRequest _request() {
  return SmartEventRequest(
    source: SmartEventSource.forYou,
    tierLabel: 'All',
    titleSuffix: 'Games',
    minElo: 0,
    maxElo: 3200,
    caption: 'From your filters',
    countSingular: 'event',
    countPlural: 'events',
    events: [],
  );
}

void main() {
  testWidgets(
    'Games keeps the same list and provider across routes and sibling tabs',
    (tester) async {
      final request = _request();
      final createdNotifiers = <SmartAggregateEventNotifier>[];
      final container = ProviderContainer(
        overrides: [
          boardSettingsProviderNew.overrideWith(_TestBoardSettingsNotifier.new),
          favoriteEventsProvider.overrideWith(_TestFavoriteEventsNotifier.new),
          smartAggregateEventRepositoryProvider.overrideWith((ref, query) {
            final notifier = _LoadedAggregateNotifier(ref, query);
            createdNotifiers.add(notifier);
            return notifier;
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            navigatorObservers: [routeObserver],
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return SmartEventScreen(request: request);
              },
            ),
          ),
        ),
      );
      await tester.pump();

      final listKey = PageStorageKey<String>(
        'smart_event_games_${request.scopeId}',
      );
      final listFinder = find.byKey(listKey, skipOffstage: false);
      expect(listFinder, findsOneWidget);
      final listStateBefore = tester.state<ScrollableState>(
        find.descendant(
          of: listFinder,
          matching: find.byType(Scrollable, skipOffstage: false),
        ),
      );
      final scrollPositionBefore = listStateBefore.position;
      final scrollOffsetBefore = scrollPositionBefore.pixels;
      expect(createdNotifiers, hasLength(1));
      final notifierBefore = createdNotifiers.single;

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push<void>(
        MaterialPageRoute<void>(builder: (_) => const Scaffold()),
      );
      await tester.pumpAndSettle();

      expect(listFinder, findsOneWidget);
      expect(createdNotifiers, [same(notifierBefore)]);

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(listFinder, findsOneWidget);
      expect(
        tester.state<ScrollableState>(
          find.descendant(
            of: listFinder,
            matching: find.byType(Scrollable, skipOffstage: false),
          ),
        ),
        same(listStateBefore),
      );
      expect(listStateBefore.position, same(scrollPositionBefore));
      expect(listStateBefore.position.pixels, scrollOffsetBefore);
      expect(createdNotifiers, [same(notifierBefore)]);

      await tester.tap(find.text('Events'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(listFinder, findsOneWidget);
      expect(createdNotifiers, [same(notifierBefore)]);

      await tester.tap(find.text('Games'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(listFinder, findsOneWidget);
      expect(
        tester.state<ScrollableState>(
          find.descendant(
            of: listFinder,
            matching: find.byType(Scrollable, skipOffstage: false),
          ),
        ),
        same(listStateBefore),
      );
      expect(listStateBefore.position, same(scrollPositionBefore));
      expect(listStateBefore.position.pixels, scrollOffsetBefore);
      expect(createdNotifiers, [same(notifierBefore)]);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
