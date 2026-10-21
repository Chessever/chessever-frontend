import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _LoadedAggregateNotifier extends SmartAggregateEventNotifier {
  _LoadedAggregateNotifier(super.ref, super.query) {
    state = const AsyncValue.data(SmartAggregateEvent.empty);
  }
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _Favorites extends FavoriteEventsNotifier {
  _Favorites(this._rows);

  final List<FavoriteEvent> _rows;

  @override
  Future<List<FavoriteEvent>> build() async => _rows;
}

class _SpaceShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

final _stamp = DateTime.utc(2026, 10, 17);

/// The Najdorf smart event a reader starred, as the app saves it.
final _najdorf = SmartEventRequest(
  source: SmartEventSource.forYou,
  tierLabel: 'Sicilian: Najdorf',
  titleSuffix: 'Games',
  minElo: 0,
  maxElo: 3200,
  caption: 'From your Sicilian: Najdorf opening filter',
  countSingular: 'event',
  countPlural: 'events',
  events: const [],
  eco: GameEcoFilter.forCode('B9'),
);

FavoriteEvent _starred(SmartEventRequest request) => FavoriteEvent(
  id: 'row',
  userId: 'reader',
  eventId: request.favoriteEventId,
  eventName: request.displayName,
  metadata: request.toFavoriteMetadata(),
  createdAt: _stamp,
  updatedAt: _stamp,
);

/// What onesignal-dispatch puts in a smart event push (`smart_event_games`).
Map<String, dynamic> _push(SmartEventRequest request) => {
  'type': 'smart_event_games',
  'smart_event_id': request.favoriteEventId,
  'smart_event_name': request.displayName,
  'smart_event_kind': 'opening:played',
  'games': 8,
  'min_elo': 0,
  'max_elo': 3200,
  'formats': <String>[],
  'eco_code': 'B9',
  'label': 'Sicilian: Najdorf',
  'game_id': 'top-game',
};

void main() {
  late GlobalKey<NavigatorState> navigatorKey;
  late List<String> namedRoutes;

  setUp(() {
    DeepLinkService.instance.detachNotificationRouter();
    DeepLinkService.instance.dispose();
    navigatorKey = GlobalKey<NavigatorState>();
    namedRoutes = <String>[];
  });

  tearDown(() {
    DeepLinkService.instance.detachNotificationRouter();
    DeepLinkService.instance.dispose();
  });

  /// The app as far as a notification tap needs it, with the real router.
  Future<void> tap(
    WidgetTester tester,
    Map<String, dynamic> data, {
    List<FavoriteEvent> favorites = const [],
  }) async {
    // Inside the test's zone, so the app-ready gate below opens in it too.
    DeepLinkService.instance.dispose();
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          boardSettingsProviderNew.overrideWith(_BoardSettings.new),
          favoriteEventsProvider.overrideWith(() => _Favorites(favorites)),
          spaceShortcutsProvider.overrideWith(_SpaceShortcuts.new),
          smartAggregateEventRepositoryProvider.overrideWith(
            (ref, query) => _LoadedAggregateNotifier(ref, query),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          navigatorKey: navigatorKey,
          navigatorObservers: [routeObserver],
          initialRoute: '/',
          onGenerateRoute: (settings) {
            namedRoutes.add(settings.name ?? '');
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (context) {
                ResponsiveHelper.init(context);
                return Consumer(
                  builder: (_, ref, __) {
                    captured = ref;
                    return const SizedBox.shrink();
                  },
                );
              },
            );
          },
        ),
      ),
    );
    DeepLinkService.instance.attachNotificationRouter(navigatorKey, captured);
    DeepLinkService.notifyAppReady();
    DeepLinkService.instance.ingestNotificationData(data);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
  }

  SmartEventScreen openedScreen(WidgetTester tester) =>
      tester.widget<SmartEventScreen>(find.byType(SmartEventScreen));

  Finder tab(String name) =>
      find.byWidgetPredicate((widget) => widget.runtimeType.toString() == name);

  void expectGamesTabShowing(WidgetTester tester) {
    final pages = tester.widget<PageView>(
      find.descendant(
        of: find.byType(SmartEventScreen),
        matching: find.byType(PageView),
      ),
    );
    expect(pages.controller?.page, smartEventGamesTab.toDouble());
    expect(tab('_GamesTab'), findsOneWidget);
    expect(tab('_AboutTab'), findsNothing);
  }

  testWidgets('a tap opens the starred smart event on its Games tab', (
    tester,
  ) async {
    await tap(tester, _push(_najdorf), favorites: [_starred(_najdorf)]);

    expect(namedRoutes, contains('/home_screen'));
    final screen = openedScreen(tester);
    expect(screen.request.favoriteEventId, _najdorf.favoriteEventId);
    expect(screen.request.criteriaKey, _najdorf.criteriaKey);
    expect(screen.request.displayName, _najdorf.displayName);
    expect(screen.initialTab, smartEventGamesTab);
    expectGamesTabShowing(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a smart event unstarred since the push still opens, on Games', (
    tester,
  ) async {
    await tap(tester, _push(_najdorf));

    final screen = openedScreen(tester);
    expect(screen.request.criteriaKey, _najdorf.criteriaKey);
    expect(screen.request.favoriteEventId, _najdorf.favoriteEventId);
    expectGamesTabShowing(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each push opens its own smart event, not another starred one', (
    tester,
  ) async {
    final gm = SmartEventRequest(
      source: SmartEventSource.forYou,
      tierLabel: 'GM',
      titleSuffix: 'Games',
      minElo: 2500,
      maxElo: 3200,
      caption: 'From your 2500+ filter',
      countSingular: 'event',
      countPlural: 'events',
      events: const [],
      formatsAndStates: const {'blitz', 'live'},
    );
    await tap(
      tester,
      {
        ..._push(gm),
        'min_elo': 2500,
        'formats': ['blitz', 'live'],
        'eco_code': null,
        'label': 'GM',
      },
      favorites: [_starred(_najdorf), _starred(gm)],
    );

    final screen = openedScreen(tester);
    expect(screen.request.criteriaKey, gm.criteriaKey);
    expect(screen.request.criteriaKey, isNot(_najdorf.criteriaKey));
    expectGamesTabShowing(tester);
  });

  // As onesignal-dispatch sends it ("blitz,live"), and as the notification
  // service's JSON-encoding would turn an array into text.
  for (final formats in ['blitz,live', '["blitz","live"]']) {
    testWidgets('an FCM push, every value a string ($formats), opens the same '
        'smart event', (tester) async {
      final gm = SmartEventRequest(
        source: SmartEventSource.forYou,
        tierLabel: 'GM',
        titleSuffix: 'Games',
        minElo: 2500,
        maxElo: 3200,
        caption: 'From your 2500+ filter',
        countSingular: 'event',
        countPlural: 'events',
        events: const [],
        formatsAndStates: const {'blitz', 'live'},
      );
      await tap(tester, {
        'type': 'smart_event_games',
        'smart_event_id': gm.favoriteEventId,
        'smart_event_kind': 'level:live',
        'games': '5',
        'min_elo': '2500',
        'max_elo': '3200',
        'formats': formats,
        'eco_code': 'null',
        'label': 'GM',
        'game_id': 'top-game',
        // Added by the notification service on the way to the phone.
        'url': '',
        'delivery_id': '5b1c9f0e-0d1a-4c7e-9a52-0f3c6d2e8a11',
        'campaign_id': '856a94b6-a8e3-4529-9abb-b344b431c8bd',
      });

      final screen = openedScreen(tester);
      expect(screen.request.criteriaKey, gm.criteriaKey);
      expect(screen.request.eco.isAll, isTrue);
      expectGamesTabShowing(tester);
    });
  }

  testWidgets('a push that names no smart event opens no smart event', (
    tester,
  ) async {
    await tap(tester, {'type': 'smart_event_games'});

    expect(find.byType(SmartEventScreen), findsNothing);
    expect(namedRoutes, contains('/home_screen'));
  });
}
