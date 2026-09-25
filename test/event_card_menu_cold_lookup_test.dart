import 'dart:async';

import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// An event card's long-press never waits on the tour lookup: the menu opens
/// at once and the No Spoilers row is kept (settled when chosen), taps never
/// reach the backend, and a failing lookup cannot break later presses.

class _MemorySpaceShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

class _NoFavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const <FavoriteEvent>[];
}

final _stored = <String, bool>{};

class _MemoryNoSpoilers extends EventNoSpoilersController {
  _MemoryNoSpoilers(Ref ref, String tourId) : super(ref: ref, tourId: tourId);

  @override
  Future<void> load() async {
    state = EventNoSpoilersState(
      enabled: _stored[tourId] ?? false,
      isLoading: false,
    );
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _stored[tourId] = enabled;
    state = EventNoSpoilersState(enabled: enabled, isLoading: false);
  }
}

class _ControlledRepository implements GroupBroadcastRepository {
  int lookups = 0;
  Completer<List<String>>? pending;
  bool fail = false;

  @override
  Future<List<String>> getTourIdsForGroupBroadcast(String id) {
    lookups++;
    if (fail) return Future.error(StateError('offline'));
    final c = pending;
    if (c != null) return c.future;
    return Future.value(const ['tour-1']);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GroupEventCardModel _event() => GroupEventCardModel(
  id: 'group-1',
  title: 'Sinquefield Cup 2026',
  dates: 'Aug 1 - 9, 2026',
  maxAvgElo: 2760,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.completed,
  timeControl: '90+30',
  startDate: DateTime(2026, 8, 1),
  endDate: DateTime(2026, 8, 9),
);

Widget _host(_ControlledRepository repo) {
  return ProviderScope(
    overrides: [
      spaceShortcutsProvider.overrideWith(_MemorySpaceShortcuts.new),
      favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
      eventImageProvider.overrideWith(
        (ref, id) async => const EventImageData(),
      ),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) => _MemoryNoSpoilers(ref, tourId),
      ),
      groupBroadcastRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(390, 844), devicePixelRatio: 3),
        child: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: EventCard(
                    tourEventCardModel: _event(),
                    favoritePlayersSource: EventFavoritePlayersSource.cacheOnly,
                    heroTagSuffix: 'test',
                    onTap: () {},
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

void main() {
  setUp(_stored.clear);

  testWidgets('a slow lookup never holds the menu or drops No Spoilers', (
    tester,
  ) async {
    final repo = _ControlledRepository()..pending = Completer<List<String>>();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(EventCard));
    await tester.pumpAndSettle();

    // Open while the lookup is still in flight, row kept in its default form.
    expect(repo.lookups, 1);
    expect(find.text('Open event'), findsOneWidget);
    expect(find.text('Turn on No Spoilers'), findsOneWidget);

    await tester.tap(find.text('Turn on No Spoilers'));
    await tester.pumpAndSettle();
    expect(_stored['tour-1'], isNull);

    repo.pending!.complete(const ['tour-1']);
    await tester.pumpAndSettle();
    expect(_stored['tour-1'], isTrue);

    // The answer is kept: the next open reads the real state, no new lookup.
    await tester.longPress(find.byType(EventCard).first);
    await tester.pumpAndSettle();
    expect(find.text('Turn off No Spoilers'), findsOneWidget);
    expect(repo.lookups, 1);
    await tester.tapAt(const Offset(5, 830));
    await tester.pumpAndSettle();
  });

  testWidgets('a cold row says so when No Spoilers is already on', (
    tester,
  ) async {
    _stored['tour-1'] = true;
    final repo = _ControlledRepository()..pending = Completer<List<String>>();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(EventCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on No Spoilers'));
    await tester.pumpAndSettle();
    repo.pending!.complete(const ['tour-1']);
    // Bounded pumps: settling would run the snack's whole life out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_stored['tour-1'], isTrue);
    expect(find.text('No Spoilers is already on'), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('an ordinary tap never starts the lookup', (tester) async {
    final repo = _ControlledRepository();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(EventCard)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(repo.lookups, 0);
  });

  testWidgets('a failing lookup never breaks later presses', (tester) async {
    final repo = _ControlledRepository()..fail = true;
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(EventCard));
    await tester.pumpAndSettle();
    expect(find.text('Open event'), findsOneWidget);
    await tester.tap(find.text('Turn on No Spoilers'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("Couldn't turn on No Spoilers"), findsOneWidget);
    await _drain(tester);

    repo.fail = false;
    await tester.longPress(find.byType(EventCard).first);
    await tester.pumpAndSettle();
    // Asked again rather than stuck on the stored failure.
    expect(find.text('Turn on No Spoilers'), findsOneWidget);
    await tester.tap(find.text('Turn on No Spoilers'));
    await tester.pumpAndSettle();
    await _drain(tester);
  });
}
