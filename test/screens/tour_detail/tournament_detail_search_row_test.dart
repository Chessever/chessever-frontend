import 'package:chessever2/chat/botvinnik_provider.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/live_game_ids_provider.dart';
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
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_flattened_layout.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_list_presentation_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/views/games_tour_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/search_list_resume.dart';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/tournament_detail_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_app_bar_widget.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_games_list_end.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_games_quick_actions.dart';
import 'package:chessever2/screens/tour_detail/widgets/tournament_menu_button.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/live_first_capsule.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../support/fake_live_game_ids.dart';

/// The event screen's search (Trello #1420, 2026-11-18 navigation overhaul):
/// no search row on top any more. Games and Standings float a search button
/// in the thumb's reach; it opens the tab under a full-page search, the field
/// in the header's place, on the shared search mode (`SearchModeHost`): the
/// tab under it is the tab itself, kept on screen through the search.

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

/// Runs the search's morph (one spring, about a third of a second) to rest,
/// a frame at a time.
Future<void> _frames(WidgetTester tester, [int count = 40]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
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

  final searchHeader = find.byType(SearchModeHeader);
  Finder field() =>
      find.descendant(of: searchHeader, matching: find.byType(EditableText));

  testWidgets('Games keeps Back in the header, never over the games', (
    tester,
  ) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);
    final chrome = tester
        .widget<CollapsingChrome>(find.byType(CollapsingChrome).first)
        .controller;
    final back = find.byTooltip('Back');
    expect(back.hitTestable(), findsOneWidget);
    chrome.hide(animate: false);
    await tester.pump();
    expect(find.byKey(const ValueKey('page_back_float')), findsNothing);
    expect(back.hitTestable(), findsNothing);
    chrome.show(animate: false);
    await tester.pump();
    expect(back.hitTestable(), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('Games: no search row on top; the search floats in reach', (
    tester,
  ) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);

    expect(searchHeader, findsNothing);
    expect(searchFab, findsOneWidget);
    // In the lower half, where the thumb rests.
    expect(tester.getCenter(searchFab).dy, greaterThan(852 / 2));
    // Nothing is live, so Live first has nothing to do and is not there.
    expect(find.bySemanticsLabel('Show live games first'), findsNothing);
    expect(find.byType(LiveFirstCapsule), findsNothing);
    await _unmount(tester);
  });

  testWidgets('the search button opens the tab under a full-page search', (
    tester,
  ) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);
    expect(find.byType(SegmentedSwitcher).hitTestable(), findsOneWidget);

    await tester.tap(searchFab);
    await tester.pump();
    await _frames(tester);

    // The field takes the header's place, cursor in it; the tabs step
    // aside (kept, out of reach) and Games stays on screen under it.
    expect(searchHeader, findsOneWidget);
    expect(find.byType(SegmentedSwitcher).hitTestable(), findsNothing);
    expect(find.byType(GamesAppBarWidget).hitTestable(), findsNothing);
    final editable = tester.widget<EditableText>(field());
    expect(editable.focusNode.hasFocus, isTrue);
    // The button's glass became the field: it stays, out of reach.
    expect(searchFab, findsOneWidget);
    expect(searchFab.hitTestable(), findsNothing);

    // The chevron closes it: the header and the tabs are back.
    await tester.tap(find.byKey(const ValueKey('event_search_close')));
    await tester.pump();
    await _frames(tester);
    expect(searchHeader, findsNothing);
    expect(find.byType(SegmentedSwitcher).hitTestable(), findsOneWidget);
    expect(searchFab.hitTestable(), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('the chevron holds its place as the search opens', (
    tester,
  ) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);
    Rect chevron() => tester.getRect(
      find.byIcon(Icons.arrow_back_ios_new_outlined).hitTestable(),
    );
    final before = chevron();

    await tester.tap(searchFab);
    await tester.pump();
    await _frames(tester);

    // Same glyph, size, x and y in the page's header and in its search.
    expect(chevron(), before);
    expect(
      tester.getCenter(find.byKey(const ValueKey('event_search_close'))),
      before.center,
    );
    await _unmount(tester);
  });

  testWidgets('system back closes the search before the screen', (
    tester,
  ) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);
    await tester.tap(searchFab);
    await tester.pump();
    await _frames(tester);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await _frames(tester);

    expect(find.byType(TournamentDetailScreen), findsOneWidget);
    expect(searchHeader, findsNothing);
    expect(find.byType(SegmentedSwitcher).hitTestable(), findsOneWidget);
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
      await _frames(tester);
    }

    Future<void> closeSearch(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('event_search_close')));
      await tester.pump();
      await _frames(tester);
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
        tester.widget<LiveFirstCapsule>(find.byType(LiveFirstCapsule)).on,
        isTrue,
      );

      // With nothing live in the event it stays on, and in view: it only
      // reorders (every game stays listed), so the reader can still see it
      // and turn it off.
      container.read(anyLive.notifier).state = false;
      await tester.pump();
      await tester.pump();
      expect(games(container).calls, ['clearSearch']);
      expect(
        tester.widget<LiveFirstCapsule>(find.byType(LiveFirstCapsule)).on,
        isTrue,
      );
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
      expect(find.byType(LiveFirstCapsule), findsNothing);
      expect(searchFab.hitTestable(), findsOneWidget);

      // Every game is back: Live first is offered, and its press only
      // switches the order.
      games(container).land(search: false);
      await tester.pump();
      await tester.tap(find.byType(LiveFirstCapsule));
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

      await tester.enterText(field(), 'carl');
      // Closed inside the field's debounce: the query must not run behind
      // the closed field.
      await tester.tap(find.byKey(const ValueKey('event_search_close')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));

      await _frames(tester);
      expect(games(container).calls, ['clearSearch']);
      expect(searchHeader, findsNothing);
      await _unmount(tester);
    });
  });

  group('a search with no hits', () {
    List<Override> overrides() => _overrides(
      TournamentDetailScreenMode.games,
      gamesScreen: gamesTourScreenProvider.overrideWith(
        (ref) => _SearchedGames(ref: ref),
      ),
      anyLive: eventGamesAnyLiveProvider.overrideWith((ref) => false),
    )..add(gamesTourGroupedProvider.overrideWith((ref) => _noGames()));

    testWidgets('says so in the shared line, with a way back to every game', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        mode: TournamentDetailScreenMode.games,
        overrides: overrides(),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TournamentDetailScreen)),
      );
      final games =
          container.read(gamesTourScreenProvider.notifier) as _SearchedGames;
      await tester.tap(searchFab);
      await tester.pump();
      await _frames(tester);
      await tester.enterText(field(), 'carl');
      await tester.pump(const Duration(milliseconds: 250));
      expect(games.calls, ['search:carl']);

      // Nothing matches "carl".
      games.land(search: true);
      await tester.pump();
      final title = find.byKey(const ValueKey('search_no_matches_title'));
      expect(find.byType(SearchNoMatches), findsOneWidget);
      expect(tester.widget<Text>(title).data, 'No matches for "carl"');
      // Whole from its first frame: nothing fades it in.
      Finder inTab(Finder matching) => find.ancestor(
        of: title,
        matching: find.descendant(
          of: find.byType(GamesTourScreen),
          matching: matching,
        ),
      );
      expect(inTab(find.byType(FadeTransition)), findsNothing);
      expect(
        inTab(
          find.byWidgetPredicate(
            (widget) => widget is Opacity && widget.opacity < 1,
          ),
        ),
        findsNothing,
      );

      // "Clear search" empties the field: the search stays open and every
      // game comes back under it.
      await tester.tap(find.byKey(const ValueKey('search_no_matches_clear')));
      await tester.pump();
      expect(tester.widget<EditableText>(field()).controller.text, isEmpty);
      expect(games.calls, ['search:carl', 'clearSearch']);
      expect(searchHeader, findsOneWidget);
      await _unmount(tester);
    });
  });

  group('the Games list through a search', () {
    // The list itself: every game is the board list the Games tab paints,
    // forty round sections (folded, so no card needs a live feed), and the
    // event's own grouped games say which boards are in play.
    final grouped = StateProvider<GroupedGamesData>(
      (ref) => _grouped(live: const ['live-1', 'live-2']),
    );
    List<Override> overrides({GameDisplayMode mode = GameDisplayMode.all}) =>
        _overrides(
          TournamentDetailScreenMode.games,
          gamesScreen: gamesTourScreenProvider.overrideWith(
            (ref) => _ListedGames(ref: ref, mode: mode),
          ),
        )..addAll([
          gamesTourGroupedProvider.overrideWith((ref) => ref.watch(grouped)),
          gamesTourListPresentationProvider.overrideWithValue(
            _roundSections(40),
          ),
          // The server's games in play (`get_live_game_ids`) for the
          // event's tour: the boards in play among the grouped games.
          eventLiveGameIdsProvider.overrideWith(
            (ref, scope) => FakeLiveGameIds({
              for (final game in ref.watch(grouped).allGames)
                if (game.gameStatus == GameStatus.ongoing) game.gameId,
            }),
          ),
        ]);
    _ListedGames games(WidgetTester tester) =>
        ProviderScope.containerOf(
              tester.element(find.byType(TournamentDetailScreen)),
            ).read(gamesTourScreenProvider.notifier)
            as _ListedGames;

    const everyGameKey = ValueKey('games_list_gamesCard_search_false');
    const hitsKey = ValueKey('games_list_gamesCard_search_true');
    final spinner = find.byWidgetPredicate(
      (widget) =>
          widget is TourLoadingWidget || widget is CircularProgressIndicator,
    );
    final quietLine = find.byKey(const ValueKey('games_list_refetch_line'));

    ScrollablePositionedList listIn(WidgetTester tester, Key key) =>
        tester.widget<ScrollablePositionedList>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(ScrollablePositionedList),
          ),
        );
    ListResumePoint? placeIn(WidgetTester tester, Key key) =>
        ListResumePoint.capture(listIn(tester, key).itemPositionsNotifier!);

    /// Scrolls the list well down, then back up a little so the header and
    /// the floating buttons (which scroll away with it) are in reach.
    Future<void> readDown(WidgetTester tester) async {
      await tester.drag(find.byKey(everyGameKey), const Offset(0, -1400));
      await _frames(tester, 60);
      await tester.drag(find.byKey(everyGameKey), const Offset(0, 300));
      await _frames(tester, 60);
    }

    /// Scrolls the list to its very end.
    Future<void> toEnd(WidgetTester tester) async {
      await tester.drag(find.byKey(everyGameKey), const Offset(0, -20000));
      await _frames(tester, 60);
    }

    testWidgets('the list ends clear of the floating buttons, and that room '
        'gives way with the search', (tester) async {
      await _pumpScreen(
        tester,
        mode: TournamentDetailScreenMode.games,
        overrides: overrides(),
      );
      // The header coming back can push it just past the viewport's edge
      // (the reader keeps their place): measured on or off screen.
      final end = find.byType(EventGamesListEnd, skipOffstage: false);
      double room() => tester.getSize(end).height;

      await tester.tap(searchFab);
      await tester.pump();
      await _frames(tester);
      // Read to the very end while the search is open.
      await toEnd(tester);
      expect(end, findsOneWidget);
      final context = tester.element(end);
      final base = EventGamesListEnd.margin;
      final buttons = EventGamesListEnd.buttonsReach(context);
      // Searching, the buttons have stepped away: only the list's margin.
      expect(room(), moreOrLessEquals(base));

      // Closing, the room grows back with the morph, never in one jump.
      await tester.tap(find.byKey(const ValueKey('event_search_close')));
      await tester.pump();
      var last = room();
      var between = false;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final now = room();
        expect(now, greaterThanOrEqualTo(last - 0.01));
        if (now > base + 1 && now < base + buttons - 1) between = true;
        last = now;
      }
      expect(between, isTrue);
      expect(room(), moreOrLessEquals(base + buttons));

      // At rest, read to the very end: the last row ends above the search
      // and Live first stacked over it.
      await toEnd(tester);
      final lastRow = tester.getRect(
        find
            .descendant(
              of: find.byKey(everyGameKey),
              matching: find.byType(RoundHeader),
            )
            .last,
      );
      expect(lastRow.bottom, lessThanOrEqualTo(852 - buttons));
      await _unmount(tester);
    });

    testWidgets('opening and closing keeps this very list, where it was, with '
        'no spinner', (tester) async {
      await _pumpScreen(
        tester,
        mode: TournamentDetailScreenMode.games,
        overrides: overrides(),
      );
      final tab = tester.state(find.byType(GamesTourScreen));
      final list = tester.element(find.byKey(everyGameKey));
      expect(find.byType(RoundHeader), findsWidgets);
      await readDown(tester);
      final place = placeIn(tester, everyGameKey);
      expect(place, isNotNull);
      expect(place!.index, greaterThan(5));

      Future<void> watch() async {
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(spinner, findsNothing);
          expect(tester.state(find.byType(GamesTourScreen)), same(tab));
          expect(tester.element(find.byKey(everyGameKey)), same(list));
        }
      }

      await tester.tap(searchFab);
      await tester.pump();
      await watch();
      expect(searchHeader, findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('event_search_close')));
      await tester.pump();
      await watch();
      expect(searchHeader, findsNothing);
      expect(games(tester).calls, ['clearSearch']);
      // Nothing was searched: the reader is still where they were.
      expect(placeIn(tester, everyGameKey)!.index, place.index);
      await _unmount(tester);
    });

    testWidgets('a query in flight keeps the list and shows a quiet line', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        mode: TournamentDetailScreenMode.games,
        overrides: overrides(),
      );
      final list = tester.element(find.byKey(everyGameKey));
      await tester.tap(searchFab);
      await tester.pump();
      await _frames(tester);
      expect(quietLine, findsNothing);

      await tester.enterText(field(), 'carl');
      await tester.pump(const Duration(milliseconds: 250));
      expect(games(tester).calls, ['search:carl']);
      await _frames(tester, 20);
      // Still searching: the list stays as it was, nothing wipes it.
      expect(quietLine, findsOneWidget);
      expect(spinner, findsNothing);
      expect(tester.element(find.byKey(everyGameKey)), same(list));

      // Closed: the line goes with the search.
      await tester.tap(find.byKey(const ValueKey('event_search_close')));
      await tester.pump();
      await _frames(tester);
      expect(quietLine, findsNothing);
      expect(games(tester).calls, ['search:carl', 'clearSearch']);
      await _unmount(tester);
    });

    testWidgets('the hits read from their top; closing puts the reader back '
        'where they were in every game', (tester) async {
      await _pumpScreen(
        tester,
        mode: TournamentDetailScreenMode.games,
        overrides: overrides(),
      );
      await readDown(tester);
      final place = placeIn(tester, everyGameKey)!;
      expect(place.index, greaterThan(5));

      await tester.tap(searchFab);
      await tester.pump();
      await _frames(tester);
      await tester.enterText(field(), 'carl');
      await tester.pump(const Duration(milliseconds: 250));
      games(tester).land('carl');
      await tester.pump();
      await tester.pump();

      // The hits: their own list, from its top, with no spinner on the way.
      expect(find.byKey(everyGameKey), findsNothing);
      expect(listIn(tester, hitsKey).initialScrollIndex, 0);
      expect(placeIn(tester, hitsKey), isNull);
      expect(spinner, findsNothing);

      await tester.tap(find.byKey(const ValueKey('event_search_close')));
      await tester.pump();
      // Every game is back in the frame the search closes, where it was.
      expect(find.byKey(hitsKey), findsNothing);
      expect(listIn(tester, everyGameKey).initialScrollIndex, place.index);
      await _frames(tester);
      expect(placeIn(tester, everyGameKey)!.index, place.index);
      expect(spinner, findsNothing);
      await _unmount(tester);
    });

    testWidgets('Live first says how many games are live', (tester) async {
      await _pumpScreen(
        tester,
        mode: TournamentDetailScreenMode.games,
        overrides: overrides(),
      );
      expect(find.byType(LiveFirstCapsule), findsOneWidget);
      expect(
        find.byKey(const ValueKey('live_first_capsule_off')),
        findsOneWidget,
      );
      // Two boards in play; the one listed in two sections counts once.
      expect(find.text('See 2 live'), findsNothing);
      expect(
        find.bySemanticsLabel('Show the 2 live games first'),
        findsOneWidget,
      );
      // It steps back with the search and comes back with the list.
      await tester.tap(searchFab);
      await tester.pump();
      await _frames(tester);
      expect(find.byType(LiveFirstCapsule).hitTestable(), findsNothing);
      await tester.tap(find.byKey(const ValueKey('event_search_close')));
      await tester.pump();
      await _frames(tester);
      expect(find.byType(LiveFirstCapsule).hitTestable(), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('Live first, turned on, takes the Games list to its top', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        mode: TournamentDetailScreenMode.games,
        overrides: overrides(),
      );
      await readDown(tester);
      expect(placeIn(tester, everyGameKey)!.index, greaterThan(5));

      await tester.tap(find.byType(LiveFirstCapsule));
      await tester.pump();
      expect(games(tester).calls, ['hideFinishedGames']);
      await _frames(tester, 60);
      // The live games lead now, and the list shows them.
      expect(placeIn(tester, everyGameKey), isNull);
      expect(
        find.byKey(const ValueKey('live_first_capsule_on')),
        findsOneWidget,
      );
      await _unmount(tester);
    });

    testWidgets('Live first, on, says so and turns off on a tap', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        mode: TournamentDetailScreenMode.games,
        overrides: overrides(mode: GameDisplayMode.hideFinishedGames),
      );
      expect(
        find.byKey(const ValueKey('live_first_capsule_on')),
        findsOneWidget,
      );
      // It only moves the live games up, every finished one stays listed:
      // never "Live only", and a second tap restores the usual order.
      expect(
        tester.widget<LiveFirstCapsule>(find.byType(LiveFirstCapsule)).mode,
        LiveFirstMode.reorder,
      );
      final semantics = tester.getSemantics(find.byType(LiveFirstCapsule));
      expect(semantics.label, 'Live games shown first');
      expect(semantics.hint, 'Double tap to restore the usual order');

      await tester.tap(find.byType(LiveFirstCapsule));
      await tester.pump();
      expect(games(tester).calls, ['showAllGames']);
      await _unmount(tester);
    });

    testWidgets('the search button holds its corner as Live first comes and '
        'goes', (tester) async {
      await _pumpScreen(
        tester,
        mode: TournamentDetailScreenMode.games,
        overrides: overrides(),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TournamentDetailScreen)),
      );
      expect(find.byType(LiveFirstCapsule), findsOneWidget);
      final withCapsule = tester.getRect(searchFab);

      // The last game ends: the capsule goes, the button stays put.
      container.read(grouped.notifier).state = _grouped(live: const []);
      await tester.pump();
      await _frames(tester);
      expect(find.byType(LiveFirstCapsule), findsNothing);
      expect(tester.getRect(searchFab), withCapsule);

      // A game starts: the capsule comes back above it, the button stays.
      container.read(grouped.notifier).state = _grouped(live: const ['live-1']);
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getRect(searchFab), withCapsule);
      }
      expect(find.bySemanticsLabel('Show the live game first'), findsOneWidget);
      // Its right edge lines up with the button's.
      expect(
        tester.getRect(find.byType(LiveFirstCapsule)).right,
        closeTo(withCapsule.right, 0.5),
      );
      await _unmount(tester);
    });
  });

  testWidgets('Games header: bare glyphs on 44pt targets', (tester) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);

    // The board view is every Games list's own toggle: a bare glyph on a
    // 44pt target, in the icon ink, as on Favorites and Countrymen.
    final toggle = find.byType(BoardViewToggleButton);
    expect(toggle, findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppBarIcons && widget.image == SvgAsset.chase_grid,
      ),
      findsNothing,
    );
    final icons = tester.widgetList<AppBarIcons>(find.byType(AppBarIcons));
    expect(icons.every((icon) => !icon.boxed), isTrue);
    final tiles = find.descendant(
      of: find.byType(AppBarIconSurface),
      matching: find.byWidgetPredicate(
        (widget) => widget is Container && widget.decoration != null,
      ),
    );
    expect(tiles, findsNothing);
    for (final target in [
      toggle,
      ...tester
          .widgetList<AppBarIconSurface>(find.byType(AppBarIconSurface))
          .map(find.byWidget),
    ]) {
      final size = tester.getSize(target);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    expect(find.byType(TournamentMenuButton), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('the board view toggle plays one haptic, the switcher\'s', (
    tester,
  ) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.tap(find.byType(BoardViewToggleButton));
    await tester.pump();
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    await _unmount(tester);
  });

  testWidgets('a tab moves its page on the spring and lands on it', (
    tester,
  ) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);
    final pages = find.byWidgetPredicate(
      (widget) => widget is PageView && widget.controller != null,
    );
    final controller = tester.widget<PageView>(pages.first).controller!;
    final from = controller.page!;

    await tester.tap(find.text('Standings').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    // Under way: between the two pages, not jumped.
    expect(controller.page, greaterThan(from));
    expect(controller.page, lessThan(from + 1));
    await _frames(tester, 40);
    expect(controller.page, from + 1);
    await _unmount(tester);
  });

  testWidgets('with reduced motion a tab jumps straight to its page', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);
    final pages = find.byWidgetPredicate(
      (widget) => widget is PageView && widget.controller != null,
    );
    final controller = tester.widget<PageView>(pages.first).controller!;
    final from = controller.page!;

    await tester.tap(find.text('Standings').first);
    await tester.pump();
    expect(controller.page, from + 1);
    await tester.pump(const Duration(milliseconds: 500));
    await _unmount(tester);
  });

  testWidgets('Standings: its own search button, no Live first', (
    tester,
  ) async {
    await _pumpScreen(tester, mode: TournamentDetailScreenMode.games);

    await tester.tap(find.text('Standings').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(searchHeader, findsNothing);
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
      await _frames(tester);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(searchHeader).right, lessThanOrEqualTo(320));
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

/// Every game, as the Games tab lists them, recording what the screen asks
/// of it. A search only starts (the hits land through [land]), as a slow
/// query does; closing puts every game back at once, as the real list does.
class _ListedGames extends GamesTourScreenProvider {
  _ListedGames({required super.ref, required GameDisplayMode mode})
    : super.loading() {
    state = AsyncValue.data(_everyGame(mode));
  }

  static GamesScreenModel _everyGame(GameDisplayMode mode) => GamesScreenModel(
    gamesTourModels: [
      _listedGame('live-1', live: true),
      _listedGame('live-2', live: true),
      _listedGame('done-1', live: false),
    ],
    pinnedGamedIs: const [],
    gameDisplayMode: mode,
  );

  final calls = <String>[];

  GameDisplayMode get _mode =>
      state.valueOrNull?.gameDisplayMode ?? GameDisplayMode.all;

  void _pending(bool value) =>
      ref.read(gamesTourSearchPendingProvider.notifier).state = value;

  /// The hits for [query] land.
  void land(String query) {
    _pending(false);
    state = AsyncValue.data(
      GamesScreenModel(
        gamesTourModels: [_listedGame('live-1', live: true)],
        pinnedGamedIs: const [],
        isSearchMode: true,
        searchQuery: query,
        gameDisplayMode: _mode,
      ),
    );
  }

  @override
  void clearSearch() {
    calls.add('clearSearch');
    _pending(false);
    if (state.valueOrNull?.isSearchMode ?? false) {
      state = AsyncValue.data(_everyGame(_mode));
    }
  }

  @override
  Future<void> searchGamesEnhanced(String query) async {
    calls.add('search:$query');
    _pending(true);
  }

  @override
  Future<void> showAllGames() async {
    calls.add('showAllGames');
    state = AsyncValue.data(_everyGame(GameDisplayMode.all));
  }

  @override
  Future<void> hideFinishedGames() async {
    calls.add('hideFinishedGames');
    state = AsyncValue.data(_everyGame(GameDisplayMode.hideFinishedGames));
  }
}

GamesTourModel _listedGame(String id, {required bool live}) {
  PlayerCard player(String name) => PlayerCard(
    name: name,
    federation: 'NOR',
    title: 'GM',
    rating: 2750,
    countryCode: 'NOR',
    team: null,
  );
  return GamesTourModel(
    gameId: id,
    whitePlayer: player('$id white'),
    blackPlayer: player('$id black'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: live ? GameStatus.ongoing : GameStatus.whiteWins,
    roundId: 'round-1',
    tourId: 'tour-1',
    lastMoveTime: DateTime.now().toUtc(),
  );
}

/// The event's games by round, [live] in play. The first live board is
/// listed in two sections, as a board can be, and counts once.
GroupedGamesData _grouped({required List<String> live}) {
  final games = [
    for (final id in live) _listedGame(id, live: true),
    _listedGame('done-1', live: false),
  ];
  return GroupedGamesData(
    filteredRounds: const [],
    gamesByRound: {
      'round-1': games,
      if (live.isNotEmpty) 'round-2': [games.first],
    },
    isKnockoutTournament: false,
    isMultiStageKnockout: false,
    isLoading: false,
    rounds: const [],
    allGames: games,
    providerGameCount: games.length,
    liveScopes: [
      EventLiveGamesScope(const ['tour-1']),
    ],
  );
}

/// An event with no games at all: what a search with no hits is shown over.
GroupedGamesData _noGames() => GroupedGamesData(
  filteredRounds: const [],
  gamesByRound: const {},
  isKnockoutTournament: false,
  isMultiStageKnockout: false,
  isLoading: false,
  rounds: const [],
  allGames: const [],
  providerGameCount: 0,
);

/// The board list as painted: [count] round sections, folded.
GamesTourListPresentation _roundSections(int count) {
  final rounds = [
    for (var i = 1; i <= count; i++)
      GamesAppBarModel(
        id: 'round-$i',
        name: 'Round $i',
        startsAt: null,
        roundStatus: RoundStatus.completed,
      ),
  ];
  return GamesTourListPresentation(
    displayRounds: rounds,
    gamesByRound: const {},
    layout: GamesTourFlattenedLayout(
      entries: [
        for (final round in rounds)
          GamesTourRoundHeaderEntry(round: round, roundGames: const []),
      ],
      orderedGames: const [],
      matchGroupsByRound: const {},
      roundHeaderIndices: {
        for (var i = 0; i < rounds.length; i++) rounds[i].id: i,
      },
      gameItemIndices: const {},
    ),
  );
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
