import 'package:chessever2/chat/botvinnik_provider.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/tournament_detail_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_app_bar_widget.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_games_quick_actions.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_search_bar.dart';
import 'package:chessever2/screens/tour_detail/widgets/tournament_menu_button.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The event screen's search (Trello #1420, 2026-11-18 navigation overhaul):
/// no search row on top any more. Games and Standings float a search button
/// in the thumb's reach; it opens the tab under a full-page search, the field
/// in the header's place.

const _about = AboutTourModel(
  id: 'tour-1',
  slug: 'test-open',
  name: 'Test Open',
  description: '',
  imageUrl: '',
  players: [],
  timeControl: '90+30',
  date: '1 Jan 2026',
  location: '',
  websiteUrl: '',
  standingsUrl: '',
  tourUrl: '',
  groupBroadcastId: 'gb-1',
);

TourDetailViewModel _viewModel() => TourDetailViewModel(
  aboutTourModel: _about,
  liveTourIds: const [],
  tours: [
    TourModel(
      tour: Tour.virtual(
        id: 'tour-1',
        name: 'Test Open',
        slug: 'test-open',
        dates: [DateTime.utc(2026, 1, 1), DateTime.utc(2026, 1, 9)],
        players: const [],
      ),
      roundStatus: RoundStatus.ongoing,
    ),
  ],
);

List<Override> _overrides(
  TournamentDetailScreenMode mode, {
  Override? gamesScreen,
  Override? anyLive,
}) => [
  selectedBroadcastModelProvider.overrideWith(
    (ref) => GroupBroadcast(
      id: 'gb-1',
      createdAt: DateTime(2026),
      name: 'Test Open',
      search: const [],
    ),
  ),
  tourDetailScreenProviderOverride(_viewModel()),
  selectedTourModeProvider.overrideWith((ref) => mode),
  liveTourIdProvider.overrideWith(
    (ref) => Stream<List<String>>.value(const <String>[]),
  ),
  shouldStreamProvider.overrideWith((ref) => false),
  gamesAppBarTourIdProvider.overrideWith((ref) => null),
  botvinnikEnabledProvider.overrideWith(_DisabledChat.new),
  gamesListViewModeProvider.overrideWithValue(GamesListViewMode.gamesCard),
  engineSettingsProviderNew.overrideWith(_TestEngineSettings.new),
  eventNoSpoilersProvider.overrideWith(
    (ref, tourId) => _TestSpoilers(ref: ref, tourId: tourId),
  ),
  knockoutTournamentStateProvider.overrideWith(
    (ref, tourId) => const KnockoutTournamentState.empty(),
  ),
  gamesScreen ??
      gamesTourScreenProvider.overrideWith(
        (ref) => GamesTourScreenProvider.loading(ref: ref),
      ),
  ?anyLive,
];

Future<void> _pumpScreen(
  WidgetTester tester, {
  required TournamentDetailScreenMode mode,
  Size size = const Size(393, 852),
  double textScale = 1,
  List<Override>? overrides,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides ?? _overrides(mode),
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const TournamentDetailScreen();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // A long category name scrolls as a marquee whose pause timer outlives the
  // tree; let it run out.
  await tester.pump(const Duration(seconds: 3));
}

const _storageChannels = [
  MethodChannel('com.tekartik.sqflite'),
  MethodChannel('plugins.flutter.io/path_provider'),
];

void main() {
  // The tabs open the local database on their way in. Answer its platform
  // calls with a failure at once, so stores fall back to empty inside the
  // test clock instead of waiting on a plugin that is not there.
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in _storageChannels) {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'unavailable'),
      );
    }
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in _storageChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  final searchFab = find.byKey(const ValueKey('event_search_fab'));

  testWidgets('Games: no search row on top; the search floats in reach', (
    tester,
  ) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);

    expect(find.byType(EventSearchBar), findsNothing);
    expect(searchFab, findsOneWidget);
    // In the lower half, where the thumb rests.
    expect(tester.getCenter(searchFab).dy, greaterThan(852 / 2));
    // Nothing is live, so Live first has nothing to do and is not there.
    expect(find.bySemanticsLabel('Show live games first'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('the search button opens the tab under a full-page search', (
    tester,
  ) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);
    expect(find.byType(SegmentedSwitcher), findsOneWidget);

    await tester.tap(searchFab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The field takes the header's place, cursor in it; the tabs step
    // aside and Games stays on screen under it.
    expect(find.byType(EventSearchBar), findsOneWidget);
    expect(find.byType(SegmentedSwitcher), findsNothing);
    expect(find.byType(GamesAppBarWidget), findsNothing);
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(EventSearchBar),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    expect(searchFab, findsNothing);

    // The chevron closes it: the header and the tabs are back.
    await tester.tap(find.byKey(const ValueKey('event_search_close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(EventSearchBar), findsNothing);
    expect(find.byType(SegmentedSwitcher), findsOneWidget);
    expect(searchFab, findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('system back closes the search before the screen', (
    tester,
  ) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);
    await tester.tap(searchFab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(TournamentDetailScreen), findsOneWidget);
    expect(find.byType(EventSearchBar), findsNothing);
    expect(find.byType(SegmentedSwitcher), findsOneWidget);
    await _unmount(tester);
  });

  group('closing the Games search', () {
    final anyLive = StateProvider<bool>((ref) => true);
    List<Override> overrides() => _overrides(
      TournamentDetailScreenMode.games,
      gamesScreen: gamesTourScreenProvider.overrideWith(
        (ref) => _SearchedGames(ref: ref),
      ),
      anyLive: eventGamesAnyLiveProvider.overrideWith(
        (ref) => ref.watch(anyLive),
      ),
    );
    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(TournamentDetailScreen)),
        );
    _SearchedGames games(ProviderContainer container) =>
        container.read(gamesTourScreenProvider.notifier) as _SearchedGames;

    Future<void> openSearch(WidgetTester tester) async {
      await tester.tap(searchFab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> closeSearch(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('event_search_close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('keeps Live first on while the hits are still up', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        mode: TournamentDetailScreenMode.games,
        overrides: overrides(),
      );
      final container = containerOf(tester);
      await openSearch(tester);
      // Live first is on; the hits for "carl" hold no game in play.
      games(container).land(search: true);
      container.read(anyLive.notifier).state = false;
      await tester.pump();

      // Closed: the list of every game is still being rebuilt, the hits are
      // up. Nothing live among them is not the event having nothing live.
      await closeSearch(tester);
      expect(games(container).calls, ['clearSearch']);

      // Every game is back, a game among them in play: Live first stays.
      games(container).land(search: false);
      container.read(anyLive.notifier).state = true;
      await tester.pump();
      await tester.pump();
      expect(games(container).calls, ['clearSearch']);
      expect(
        tester.widget<LiveFirstInkFab>(find.byType(LiveFirstInkFab)).on,
        isTrue,
      );

      // With nothing live in the event it still turns itself off.
      container.read(anyLive.notifier).state = false;
      await tester.pump();
      await tester.pump();
      expect(games(container).calls, ['clearSearch', 'showAllGames']);
      await _unmount(tester);
    });

    testWidgets('Live first waits for every game before it can be pressed', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        mode: TournamentDetailScreenMode.games,
        overrides: overrides(),
      );
      final container = containerOf(tester);
      await openSearch(tester);
      // A hit for "carl" is in play.
      games(container).land(search: true);
      await tester.pump();

      // Closed with the hits still up: a press now would run "carl" again
      // behind the closed field, so Live first is not offered yet.
      await closeSearch(tester);
      expect(find.byType(LiveFirstInkFab), findsNothing);
      expect(searchFab, findsOneWidget);

      // Every game is back: Live first is offered, and its press only
      // switches the order.
      games(container).land(search: false);
      await tester.pump();
      await tester.tap(find.byType(LiveFirstInkFab));
      await tester.pump();
      await tester.pump();
      expect(games(container).calls, ['clearSearch', 'showAllGames']);
      await _unmount(tester);
    });

    testWidgets('a keystroke still pending does not search again', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        mode: TournamentDetailScreenMode.games,
        overrides: overrides(),
      );
      final container = containerOf(tester);
      await openSearch(tester);

      await tester.enterText(
        find.descendant(
          of: find.byType(EventSearchBar),
          matching: find.byType(EditableText),
        ),
        'carl',
      );
      // Closed inside the field's debounce: the query must not run behind
      // the closed field.
      await tester.tap(find.byKey(const ValueKey('event_search_close')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));

      expect(games(container).calls, ['clearSearch']);
      expect(find.byType(EventSearchBar), findsNothing);
      await _unmount(tester);
    });
  });

  testWidgets('Games header: bare glyphs on 44pt targets', (tester) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);

    final icons = tester.widgetList<AppBarIcons>(find.byType(AppBarIcons));
    expect(icons, hasLength(2));
    expect(icons.every((icon) => !icon.boxed), isTrue);
    final tiles = find.descendant(
      of: find.byType(AppBarIconSurface),
      matching: find.byWidgetPredicate(
        (widget) => widget is Container && widget.decoration != null,
      ),
    );
    expect(tiles, findsNothing);
    for (final surface in tester.widgetList<AppBarIconSurface>(
      find.byType(AppBarIconSurface),
    )) {
      final size = tester.getSize(find.byWidget(surface));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppBarIcons && widget.image == SvgAsset.chase_grid,
      ),
      findsOneWidget,
    );
    expect(find.byType(TournamentMenuButton), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('Standings: its own search button, no Live first', (
    tester,
  ) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);

    await tester.tap(find.text('Standings').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(EventSearchBar), findsNothing);
    expect(searchFab, findsOneWidget);
    expect(find.bySemanticsLabel('Show live games first'), findsNothing);
    await _unmount(tester);
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets('nothing overflows on a 320pt phone at ${textScale}x text', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        mode: TournamentDetailScreenMode.games,
        size: const Size(320, 568),
        textScale: textScale,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(searchFab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byType(EventSearchBar)).right,
        lessThanOrEqualTo(320),
      );
      await _unmount(tester);
    });
  }
}

/// The Games screen model with Live first on, recording what the screen asks
/// of it. [clearSearch] only records: the list of every game it rebuilds
/// arrives later, through [land].
class _SearchedGames extends GamesTourScreenProvider {
  _SearchedGames({required super.ref}) : super.loading() {
    land(search: false);
  }

  final calls = <String>[];

  void land({
    required bool search,
    GameDisplayMode mode = GameDisplayMode.hideFinishedGames,
  }) => state = AsyncValue.data(
    GamesScreenModel(
      gamesTourModels: const [],
      pinnedGamedIs: const [],
      isSearchMode: search,
      searchQuery: search ? 'carl' : null,
      gameDisplayMode: mode,
    ),
  );

  @override
  void clearSearch() => calls.add('clearSearch');

  @override
  Future<void> showAllGames() async {
    calls.add('showAllGames');
    land(search: false, mode: GameDisplayMode.all);
  }

  @override
  Future<void> hideFinishedGames() async => calls.add('hideFinishedGames');

  @override
  Future<void> searchGamesEnhanced(String query) async =>
      calls.add('search:$query');
}

class _DisabledChat extends BotvinnikEnabledNotifier {
  @override
  Future<bool> build() async => false;
}

class _TestEngineSettings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async =>
      const EngineSettings(showEngineAnalysis: false, showEngineGauge: false);
}

class _TestSpoilers extends EventNoSpoilersController {
  _TestSpoilers({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(isLoading: false);
  }
}
