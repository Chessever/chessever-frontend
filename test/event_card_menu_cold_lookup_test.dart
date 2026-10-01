import 'dart:async';

import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/favorites/player_games/view_model/player_games_state.dart';
import 'package:chessever2/screens/favorites/player_games/widgets/tournament_group_header.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/event_card/event_next_round_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// An event card's long-press never waits on the tour lookup: the menu opens
/// at once and the No Spoilers row is kept (settled when chosen), taps never
/// reach the backend, and a failing lookup cannot break later presses.

class _MemorySpaceShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];

  @override
  Future<bool> add(SpaceShortcut draft) async {
    final list = state.requireValue;
    if (!draft.canAddToMySpace || list.any((s) => s.key == draft.key)) {
      return false;
    }
    state = AsyncData([draft, ...list]);
    return true;
  }

  @override
  Future<SpaceShortcut?> remove(String id) async {
    final list = state.requireValue;
    final removed = list.where((s) => s.id == id).firstOrNull;
    state = AsyncData([
      for (final s in list)
        if (s.id != id) s,
    ]);
    return removed;
  }

  @override
  Future<void> restore(SpaceShortcut item) async {
    state = AsyncData([item, ...state.requireValue]);
  }
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

GroupEventCardModel _event({
  TourEventCategory category = TourEventCategory.completed,
  EventSource source = EventSource.lichessBroadcast,
  String id = 'group-1',
}) => GroupEventCardModel(
  id: id,
  title: 'Sinquefield Cup 2026',
  dates: 'Aug 1 - 9, 2026',
  maxAvgElo: 2760,
  timeUntilStart: '',
  tourEventCategory: category,
  eventSource: source,
  timeControl: '90+30',
  startDate: DateTime(2026, 8, 1),
  endDate: DateTime(2026, 8, 9),
);

Widget _host(
  _ControlledRepository repo, {
  GroupEventCardModel? event,
  SpaceShortcut? spaceDraft,
  Widget? card,
}) {
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
      eventNextRoundProvider.overrideWith((ref, id) async => null),
      liveGroupBroadcastIdsProvider.overrideWith((ref) => Stream.value([])),
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
                  child:
                      card ??
                      EventCard(
                        tourEventCardModel: event ?? _event(),
                        spaceDraft: spaceDraft,
                        favoritePlayersSource:
                            EventFavoritePlayersSource.cacheOnly,
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

  testWidgets('favorite player tournament headers offer add and remove', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _ControlledRepository(),
        card: TournamentGroupHeader(
          tournamentGroup: TournamentGamesGroup(
            tourId: 'tour-1',
            tourName: 'Favorite player event',
            tourSlug: 'favorite-player-event',
            games: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final header = find.byType(TournamentGroupHeader);
    final container = ProviderScope.containerOf(tester.element(header));
    await tester.longPress(header);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to My Space'));
    await tester.pumpAndSettle();
    final saved = container.read(spaceShortcutsProvider).requireValue.single;
    expect(saved.targetId, 'tour-1');
    expect(saved.params['tourId'], 'tour-1');

    await tester.longPress(header);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from My Space'));
    await tester.pumpAndSettle();
    expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);
    await _drain(tester);
  });

  for (final category in TourEventCategory.values) {
    testWidgets('${category.name} event can be added, removed and restored', (
      tester,
    ) async {
      final event = _event(category: category);
      await tester.pumpWidget(_host(_ControlledRepository(), event: event));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(EventCard)),
      );

      await tester.longPress(find.byType(EventCard));
      await tester.pumpAndSettle();
      expect(find.text('Add to My Space'), findsOneWidget);
      await tester.tap(find.text('Add to My Space'));
      await tester.pumpAndSettle();
      final saved = container.read(spaceShortcutsProvider).requireValue.single;
      expect(saved.kind, SpaceShortcutKind.event);
      expect(saved.targetId, event.id);
      await _drain(tester);

      await tester.longPress(find.byType(EventCard).first);
      await tester.pumpAndSettle();
      expect(find.text('Remove from My Space'), findsOneWidget);
      await tester.tap(find.text('Remove from My Space'));
      // The snack's progress line animates for its whole lifetime; settling
      // here would dismiss Undo before the test can press it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        container.read(spaceShortcutsProvider).requireValue.single.key,
        saved.key,
      );
      await _drain(tester);
    });
  }

  for (final source in [
    EventSource.communityEvent,
    EventSource.lichessBroadcast,
  ]) {
    testWidgets(
      'non-broadcast event keeps its My Space action: ${source.name}',
      (tester) async {
        final databaseEvent = source == EventSource.lichessBroadcast;
        final event = _event(
          source: source,
          id: databaseEvent ? 'gamebase::Archive event' : 'cal_event_community',
        );
        final repo = _ControlledRepository();
        await tester.pumpWidget(_host(repo, event: event));
        await tester.pumpAndSettle();
        await tester.longPress(find.byType(EventCard));
        await tester.pumpAndSettle();
        expect(find.text('Add to My Space'), findsOneWidget);
        expect(find.text('Share'), findsNothing);
        expect(find.text('Copy PGN'), findsNothing);
        expect(repo.lookups, 0);
        await tester.tap(find.text('Add to My Space'));
        await tester.pumpAndSettle();

        await tester.longPress(find.byType(EventCard).first);
        await tester.pumpAndSettle();
        expect(find.text('Remove from My Space'), findsOneWidget);
        await tester.tap(find.text('Remove from My Space'));
        await tester.pumpAndSettle();
        await _drain(tester);
      },
    );
  }

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
