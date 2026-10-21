import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/collections/collection_bindings.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/favorites/widgets/event_favorite_card.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart'
    show liveBroadcastIdsProvider;
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/widget/for_you_tournament_card.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/event_card/event_next_round_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

GroupBroadcast _broadcast(String id, String name) => GroupBroadcast(
  id: id,
  createdAt: DateTime.utc(2025),
  name: name,
  search: const [],
  dateStart: DateTime.utc(2025, 1, 1),
  dateEnd: DateTime.utc(2025, 1, 9),
);

class _EventRepository implements GroupBroadcastRepository {
  _EventRepository(this.event, {this.failIdRead = false, this.current = false});

  final GroupBroadcast event;
  final bool failIdRead;
  final bool current;
  int idReads = 0;
  int slugReads = 0;
  int currentReads = 0;

  @override
  Future<List<GroupBroadcast>> getCurrentGroupBroadcastsByIds(
    List<String> ids,
  ) async {
    currentReads++;
    return current && ids.contains(event.id) ? [event] : const [];
  }

  @override
  Future<GroupBroadcast> getGroupBroadcastById(String id) async {
    expect(id, event.id);
    idReads++;
    if (failIdRead) throw StateError('Event metadata unavailable');
    return event;
  }

  @override
  Future<GroupBroadcast?> getGroupBroadcastBySlug(String slug) async {
    expect(slug, 'past-event');
    slugReads++;
    return event;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected repository call: ${invocation.memberName}');
}

class _NoFavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const [];
}

Future<void> _settle(WidgetTester tester) async {
  for (var n = 0; n < 6; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 160));
  }
}

Future<ProviderContainer> _pumpEntry(
  WidgetTester tester, {
  required _EventRepository repository,
  required Widget Function(BuildContext, WidgetRef) entry,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      premiumAccessProvider.overrideWithValue(false),
      liveBroadcastIdsProvider.overrideWith((_) => const []),
      liveGroupBroadcastIdsProvider.overrideWith(
        (_) => Stream.value(const <String>[]),
      ),
      selectedBroadcastModelProvider.overrideWith(
        (_) => _broadcast('previous', 'Previous event'),
      ),
      selectedTourModeProvider.overrideWith(
        (_) => TournamentDetailScreenMode.players,
      ),
      groupBroadcastRepositoryProvider.overrideWithValue(repository),
      favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
      eventFavoritePlayersProvider.overrideWith(
        (_, _) async => const EventFavoritePlayers.empty(),
      ),
      eventImageProvider.overrideWith((_, _) async => const EventImageData()),
      eventNextRoundProvider.overrideWith((_, _) async => null),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        routes: {
          '/tournament_detail_screen': (_) =>
              const Scaffold(body: Text('Opened tournament')),
        },
        home: Consumer(
          builder: (context, ref, _) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: entry(context, ref),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await _settle(tester);
  return container;
}

Future<void> _denyAndExpectUnchanged(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await _settle(tester);
  expect(find.text('Sign in to get Premium'), findsOneWidget);
  expect(container.read(selectedBroadcastModelProvider)?.id, 'previous');
  expect(
    container.read(selectedTourModeProvider),
    TournamentDetailScreenMode.players,
  );
  expect(find.text('Opened tournament'), findsNothing);

  Navigator.of(tester.element(find.text('Sign in to get Premium'))).pop();
  await _settle(tester);
  expect(container.read(selectedBroadcastModelProvider)?.id, 'previous');
  expect(
    container.read(selectedTourModeProvider),
    TournamentDetailScreenMode.players,
  );
  expect(find.text('Opened tournament'), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      publishableKey: 'fixture-publishable-key',
    );
  });

  testWidgets('favorite resolves canonical past dates before opening', (
    tester,
  ) async {
    final repository = _EventRepository(_broadcast('past', 'Past event'));
    final container = await _pumpEntry(
      tester,
      repository: repository,
      entry: (_, _) => const EventFavoriteCard(
        eventData: {'id': 'past', 'title': 'Saved event'},
      ),
    );

    await tester.tap(find.text('Saved event'));
    await _denyAndExpectUnchanged(tester, container);
    expect(repository.idReads, 1);
  });

  testWidgets('warm For You past event asks before replacing selection', (
    tester,
  ) async {
    final repository = _EventRepository(_broadcast('past', 'Past event'));
    final container = await _pumpEntry(
      tester,
      repository: repository,
      entry: (_, _) => const ForYouTournamentCard(
        tourId: 'past-tour',
        groupKey: 'past',
        tourName: 'Fallback name',
        hasLiveGames: false,
        gameCount: 1,
        isFirst: true,
      ),
    );
    expect(repository.idReads, 1);

    await tester.tap(find.text('Past event'));
    await _denyAndExpectUnchanged(tester, container);
    expect(repository.idReads, 1);
  });

  testWidgets('favorite keeps its fallback when event metadata fails', (
    tester,
  ) async {
    final repository = _EventRepository(
      _broadcast('past', 'Past event'),
      failIdRead: true,
    );
    final container = await _pumpEntry(
      tester,
      repository: repository,
      entry: (_, _) => const EventFavoriteCard(
        eventData: {'id': 'past', 'title': 'Saved event'},
      ),
    );

    await tester.tap(find.text('Saved event'));
    await _settle(tester);
    expect(find.text('Opened tournament'), findsOneWidget);
    expect(container.read(selectedBroadcastModelProvider)?.name, 'Saved event');
    expect(repository.idReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Current membership opens favorite despite very old dates', (
    tester,
  ) async {
    final repository = _EventRepository(
      _broadcast('current', 'Current event'),
      current: true,
    );
    final container = await _pumpEntry(
      tester,
      repository: repository,
      entry: (_, _) => const EventFavoriteCard(
        eventData: {'id': 'current', 'title': 'Saved current event'},
      ),
    );

    await tester.tap(find.text('Saved current event'));
    await _settle(tester);
    expect(find.text('Sign in to get Premium'), findsNothing);
    expect(find.text('Opened tournament'), findsOneWidget);
    expect(container.read(selectedBroadcastModelProvider)?.id, 'current');
    expect(repository.currentReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Current membership opens For You despite very old dates', (
    tester,
  ) async {
    final repository = _EventRepository(
      _broadcast('current', 'Current event'),
      current: true,
    );
    final container = await _pumpEntry(
      tester,
      repository: repository,
      entry: (_, _) => const ForYouTournamentCard(
        tourId: 'current-tour',
        groupKey: 'current',
        tourName: 'Fallback name',
        hasLiveGames: false,
        gameCount: 1,
        isFirst: true,
      ),
    );

    await tester.tap(find.text('Current event'));
    await _settle(tester);
    expect(find.text('Sign in to get Premium'), findsNothing);
    expect(find.text('Opened tournament'), findsOneWidget);
    expect(container.read(selectedBroadcastModelProvider)?.id, 'current');
    expect(
      container.read(selectedTourModeProvider),
      TournamentDetailScreenMode.games,
    );
    expect(repository.currentReads, 1);
    expect(repository.idReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'For You keeps instant fallback navigation after metadata error',
    (tester) async {
      final repository = _EventRepository(
        _broadcast('past', 'Past event'),
        failIdRead: true,
      );
      final container = await _pumpEntry(
        tester,
        repository: repository,
        entry: (_, _) => const ForYouTournamentCard(
          tourId: 'past-tour',
          groupKey: 'past',
          tourName: 'fallback-event',
          hasLiveGames: false,
          gameCount: 1,
          isFirst: true,
        ),
      );

      await tester.tap(find.text('Fallback Event'));
      await _settle(tester);
      expect(find.text('Opened tournament'), findsOneWidget);
      expect(
        container.read(selectedBroadcastModelProvider)?.name,
        'Fallback Event',
      );
      expect(repository.idReads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('For You live games bypass stale past event dates', (
    tester,
  ) async {
    final repository = _EventRepository(_broadcast('past', 'Live event'));
    final container = await _pumpEntry(
      tester,
      repository: repository,
      entry: (_, _) => const ForYouTournamentCard(
        tourId: 'live-tour',
        groupKey: 'past',
        tourName: 'Fallback name',
        hasLiveGames: true,
        gameCount: 1,
        isFirst: true,
      ),
    );

    await tester.tap(find.text('Live event'));
    await _settle(tester);
    expect(find.text('Sign in to get Premium'), findsNothing);
    expect(find.text('Opened tournament'), findsOneWidget);
    expect(container.read(selectedBroadcastModelProvider)?.id, 'past');
    expect(
      container.read(selectedTourModeProvider),
      TournamentDetailScreenMode.games,
    );
    expect(repository.idReads, 1);
    expect(tester.takeException(), isNull);
  });

  for (final database in [false, true]) {
    testWidgets(
      'collection ${database ? 'database' : 'slug'} event dismissal stays put without an error snack',
      (tester) async {
        final repository = _EventRepository(_broadcast('past', 'Past event'));
        var completed = false;
        final container = await _pumpEntry(
          tester,
          repository: repository,
          entry: (context, ref) => TextButton(
            onPressed: () async {
              await openCollectionEvent(
                context,
                ref,
                CollectionEventRef(
                  linkId: 'bound-event',
                  title: 'Past event',
                  dateStart: DateTime.utc(2025, 1, 1),
                  dateEnd: DateTime.utc(2025, 1, 9),
                  open: database
                      ? const CollectionEventOpen.database(
                          eventName: 'Past event',
                        )
                      : const CollectionEventOpen.broadcastSlug('past-event'),
                ),
              );
              completed = true;
            },
            child: const Text('Open bound event'),
          ),
        );

        await tester.tap(find.text('Open bound event'));
        await _denyAndExpectUnchanged(tester, container);
        expect(completed, isTrue);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text("Couldn't open this event"), findsNothing);
        expect(repository.slugReads, database ? 0 : 1);
        expect(repository.idReads, 0);
      },
    );
  }
}
