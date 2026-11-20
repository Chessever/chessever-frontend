import 'dart:async';

import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/app_resume_signal_provider.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/game_list_live_first_provider.dart';
import 'package:chessever2/providers/live_game_ids_provider.dart';
import 'package:chessever2/screens/countrymen/countrymen_tab_screen.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_combined_games_provider.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_mode_provider.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_events_tab.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_games_tab.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_players_tab.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/services/discovery_dots/discovery_dots_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/date_time_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/country_dropdown.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/live_first_capsule.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../support/fake_live_game_ids.dart';

/// Records filters and searches instead of refetching from Supabase, and
/// answers a search the way the real notifier does: the list on screen stays
/// until the hits land ([nextSearch], at once by default), and closing the
/// search puts the plain list back as it was.
class _FakeGames extends StateNotifier<CountrymenCombinedGamesState>
    implements CountrymenCombinedGamesNotifier {
  _FakeGames({List<GamesTourModel> games = const []})
    : super(
        CountrymenCombinedGamesState(
          games: games,
          isLoading: false,
          hasMore: false,
        ),
      );

  final List<GameFilter> applied = [];
  final List<String> searches = [];
  int clears = 0;

  /// The answer to the next search; null answers at once with no games.
  Completer<List<GamesTourModel>>? nextSearch;

  CountrymenCombinedGamesState? _beforeSearch;
  String _query = '';

  @override
  Future<void> applyFilter(GameFilter filter) async {
    applied.add(filter);
    state = state.copyWith(filter: filter);
  }

  @override
  Future<void> searchGames(String query) async {
    final trimmed = query.trim();
    searches.add(query);
    if (_query.isEmpty) _beforeSearch = state;
    _query = trimmed;
    final answer = nextSearch;
    nextSearch = null;
    state = state.copyWith(isLoading: true, isReplacing: true);
    final hits = answer == null
        ? const <GamesTourModel>[]
        : await answer.future;
    if (!mounted || _query != trimmed) return;
    state = state.copyWith(isLoading: false, games: hits, searchQuery: trimmed);
  }

  /// Counts searches actually ended, as the real one only acts on one.
  @override
  Future<void> clearSearch() async {
    if (_query.isEmpty && !state.isSearching) return;
    clears++;
    _query = '';
    final before = _beforeSearch;
    _beforeSearch = null;
    state = before != null && before.filter == state.filter
        ? before
        : state.copyWith(searchQuery: '', isLoading: false);
  }

  @override
  Future<void> refreshGames({bool keepList = true}) async {}

  /// Every set Live first asked to have listed.
  final List<Set<String>> listed = [];

  /// The games [ensureListed] adds, by id, as the real one fetches them.
  final Map<String, GamesTourModel> rows = {};

  @override
  Future<void> ensureListed(Iterable<String> ids) async {
    listed.add(ids.toSet());
    final missing = [
      for (final id in ids)
        if (!state.games.any((game) => game.gameId == id) && rows[id] != null)
          rows[id]!,
    ];
    if (missing.isEmpty) return;
    state = state.copyWith(games: [...missing, ...state.games]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Whose games the Countrymen list asks about in these tests.
final _scope = CountrymenLiveGamesScope(countryCode: 'NOR');

/// The live-game polls the page started, the newest last.
final List<FakeLiveGameIds> _polls = [];

/// The boards a fixture marks in play: what the server says by default.
Set<String> _inPlay(Iterable<GamesTourModel> games) => {
  for (final game in games)
    if (game.gameStatus == GameStatus.ongoing) game.gameId,
};

/// The server's games in play for the list ([serverLive], or the fixture's
/// boards in play), or no answer yet when [answered] is false.
List<Override> _serverLive(
  List<GamesTourModel> games, {
  Set<String>? serverLive,
  bool answered = true,
}) => [
  countrymenGamesLiveScopeProvider.overrideWith((ref) => _scope),
  countrymenLiveGameIdsProvider.overrideWith((ref, scope) {
    final poll = FakeLiveGameIds(
      answered ? serverLive ?? _inPlay(games) : null,
    );
    _polls.add(poll);
    return poll;
  }),
];

class _FakeEvents extends StateNotifier<CountrymenEventsState>
    implements CountrymenEventsNotifier {
  _FakeEvents() : super(const CountrymenEventsState(hasMore: false));

  /// Every query the page sent, '' for a cleared one.
  final List<String> searches = [];

  @override
  Future<void> search(String query) async {
    searches.add(query.trim());
    state = CountrymenEventsState(hasMore: false, searchQuery: query.trim());
  }

  @override
  Future<void> clearSearch() async {
    if (!state.isSearching) return;
    await search('');
  }

  @override
  Future<void> loadMore() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The picker reads country names through the notifier; this one never
/// touches the local database, and records pins instead of saving them.
class _FakeCountry extends StateNotifier<AsyncValue<Country>>
    implements SelectedCountryNotifier {
  _FakeCountry(Country country) : super(AsyncValue.data(country));

  final List<String> pinned = [];

  @override
  String getCountryName(String countryCode) =>
      CountryService().findByCode(countryCode)?.name ?? countryCode;

  @override
  void selectCountry(String countryCode) {
    pinned.add(countryCode);
    state = AsyncValue.data(CountryService().findByCode(countryCode)!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The cards' engine settings, without the device database or Supabase.
class _NoEngine extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async =>
      const EngineSettings(showEngineAnalysis: false, showEngineGauge: false);
}

/// The cards' spoiler setting, without the device database.
class _NoSpoilers extends EventNoSpoilersController {
  _NoSpoilers({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(isLoading: false);
  }
}

class _NoDiscoveryDots implements DiscoveryDotsSource {
  @override
  Future<String> initialize() async => '';

  @override
  Future<String> fetch() async => '';

  @override
  Stream<String> get updates => const Stream<String>.empty();
}

final Country _norway = CountryService().findByCode('NO')!;
final Country _germany = CountryService().findByCode('DE')!;
final Country _unitedStates = CountryService().findByCode('US')!;

late _FakeGames _games;
late _FakeEvents _events;

/// The search words of every country ranking page asked for.
final List<String> _rankingQueries = [];
late _FakeCountry _country;
late ProviderContainer _container;

Future<void> _pumpScreen(
  WidgetTester tester, {
  CountrymenScreenMode mode = CountrymenScreenMode.games,
  Size size = const Size(393, 852),
  double textScale = 1.0,
  Country? temporary,
  Country? pinned,
  bool? anyLive,
  List<GamesTourModel> games = const [],
  GamesListViewMode viewMode = GamesListViewMode.gamesCard,
  Set<String>? serverLive,
  bool serverAnswered = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final persisted = pinned ?? _norway;
  final shown = temporary ?? persisted;
  _polls.clear();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._serverLive(games, serverLive: serverLive, answered: serverAnswered),
        countrymenCombinedGamesProvider.overrideWith(
          (ref) => _games = _FakeGames(games: games),
        ),
        countrymenEventsProvider.overrideWith((ref) => _events = _FakeEvents()),
        // The real ranking, served without Supabase.
        countryRankingsFetcherProvider.overrideWithValue(({
          required countryCode,
          required filters,
          required searchQuery,
          required limit,
          required offset,
        }) async {
          _rankingQueries.add(searchQuery);
          return const [];
        }),
        countryDropdownProvider.overrideWith(
          (ref) => _country = _FakeCountry(persisted),
        ),
        temporaryCountryProvider.overrideWith((ref) => temporary),
        effectiveCountryProvider.overrideWithValue(AsyncValue.data(shown)),
        selectedCountrymenModeProvider.overrideWith((ref) => mode),
        gamesListViewModeProvider.overrideWithValue(viewMode),
        if (anyLive != null)
          countrymenGamesAnyLiveProvider.overrideWith((ref) => anyLive),
        // What the cards read, without Supabase or the device database.
        if (games.isNotEmpty) ...[
          discoveryDotsSourceProvider.overrideWithValue(_NoDiscoveryDots()),
          engineSettingsProviderNew.overrideWith(_NoEngine.new),
          eventNoSpoilersProvider.overrideWith(
            (ref, tourId) => _NoSpoilers(ref: ref, tourId: tourId),
          ),
          // One reading of the clock: no ticking timer left behind.
          dateTimeProvider.overrideWith((ref) => Stream.value(DateTime.now())),
        ],
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        navigatorObservers: [routeObserver],
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            _container = ProviderScope.containerOf(context);
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: const CountrymenTabScreen(),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _control(String label) => find.byWidgetPredicate(
  (widget) => widget is QuickToggleIconButton && widget.label == label,
);

/// The full-page search header (built only while the search is open).
Finder get _searchHeader => find.byType(SearchModeHeader);

/// [finder] inside the search header.
Finder _inSearch(Finder finder) =>
    find.descendant(of: _searchHeader, matching: finder);

Finder get _liveFirst => find.byType(LiveFirstCapsule);
Finder get _classical => find.byType(ClassicalToggleButton);
Finder get _filters => find.byType(SearchModeFilterButton);
Finder get _boardView => _control('Change board view');
Finder get _searchFab => find.byType(SearchInkFab);
Finder get _searchField => _inSearch(find.byType(TextField));
Finder get _closeSearch => find.byTooltip('Close search');
Finder get _back => find.byType(PageBackButton);

/// What Live first reads with [count] games in play, off.
String _liveLabel(int count) =>
    LiveFirstCapsule.semanticsLabelFor(on: false, liveCount: count);

/// Lets springs and routes finish without waiting on a caret's blink, which
/// never settles while the search field has focus.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens the Games page's full-page search from its floating button.
Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(_searchFab);
  await _settle(tester);
}

bool _liveFirstOn() => _container.read(
  gameListLiveFirstProvider(GameListLiveFirstSurface.countrymen),
);

const _pinGermany = 'Pin Germany as default';

Future<void> _openCountryMenu(WidgetTester tester) async {
  await tester.tap(find.byType(CountryDropdown));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The app's own type, so a name takes the width it takes on a phone; the
/// stock test font draws every glyph a full em wide.
Future<void> _loadInter() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final inter = FontLoader('InterDisplay');
  for (final weight in const ['Regular', 'Medium', 'Bold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.otf'));
  }
  await inter.load();
}

RenderParagraph _nameParagraph(WidgetTester tester, String name) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(CountryDropdown),
        matching: find.text(name),
      ),
    );

/// [name] is drawn whole in the picker: no ellipsis, nothing cut.
void _expectWholeName(WidgetTester tester, String name) {
  final paragraph = _nameParagraph(tester, name);
  expect(paragraph.didExceedMaxLines, isFalse, reason: name);
  expect(
    paragraph.size.width,
    greaterThanOrEqualTo(
      paragraph.getMaxIntrinsicWidth(double.infinity) - 0.01,
    ),
    reason: name,
  );
}

GamesTourModel _game(
  String id, {
  required DateTime lastMoveTime,
  bool ongoing = false,
}) {
  PlayerCard card(String name) => PlayerCard(
    name: name,
    federation: 'NOR',
    title: '',
    rating: 2500,
    countryCode: 'NO',
    team: null,
  );
  return GamesTourModel(
    gameId: id,
    whitePlayer: card('White $id'),
    blackPlayer: card('Black $id'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: ongoing ? GameStatus.ongoing : GameStatus.draw,
    tourId: 'tour',
    roundId: 'round',
    // A game in play has a move; a 0-move shell never is.
    lastMove: ongoing ? 'e2e4' : null,
    lastMoveTime: lastMoveTime,
  );
}

void main() {
  group('Countrymen Games header and floating buttons (Trello #1420)', () {
    testWidgets('the app bar ends with the toolbar beside the picker; back '
        'sits where the search header puts its chevron', (tester) async {
      await _pumpScreen(tester);

      final back = tester.getRect(_back);
      // The canonical back: a 48pt target at the leading inset, right under
      // the status bar's inset (+4).
      expect(back.left, closeTo(SearchHeaderMetrics.leadingInset, 0.01));
      expect(back.width, SearchHeaderMetrics.backTarget);
      expect(back.top, closeTo(4, 0.5));

      final picker = tester.getRect(find.byType(CountryDropdown));
      final board = tester.getRect(_boardView);
      final filters = tester.getRect(_filters);
      for (final rect in [picker, board, filters]) {
        expect(rect.center.dy, closeTo(back.center.dy, 1));
      }
      expect(back.right, lessThanOrEqualTo(picker.left));
      expect(picker.right, lessThanOrEqualTo(board.left));
      expect(board.right, lessThanOrEqualTo(filters.left));
      // Classical only lives in the filter popup (2026-11-20).
      expect(_classical, findsNothing);
      expect(filters.right, lessThanOrEqualTo(393));
      // The same board-view mark as Favorites.
      expect(
        find.descendant(of: _boardView, matching: find.byType(BoardViewGlyph)),
        findsOneWidget,
      );

      // Nothing is live, so Live first does not float; no field sits on the
      // page.
      expect(_liveFirst, findsNothing);
      expect(find.byType(TextField), findsNothing);

      // The search floats in the thumb's reach.
      final search = tester.getRect(_searchFab);
      expect(search.top, greaterThan(852 / 2));
      expect(search.right, greaterThan(393 / 2));
    });

    testWidgets('the header folds away with the list, the search slides with '
        'it, and a page change brings it back', (tester) async {
      await _pumpScreen(tester);
      final chrome = ScrollChromeScope.maybeOf(
        tester.element(find.byType(PageView)),
      )!;
      final searchTop = tester.getRect(_searchFab).top;

      chrome.hide(animate: false);
      await tester.pump();

      expect(tester.getSize(find.byType(CollapsingChrome)).height, 0);
      expect(tester.getTopLeft(find.byType(PageView)).dy, greaterThan(0));
      expect(tester.getRect(_searchFab).top, greaterThan(searchTop));

      await tester.drag(find.byType(PageView), const Offset(300, 0));
      await _settle(tester);
      expect(chrome.value, 1);
      expect(find.byType(SegmentedSwitcher), findsOneWidget);
    });

    testWidgets('the search opens in place: the chevron and Filters stay '
        'put, the field takes the country\'s place over the same '
        'Games list, and back closes it', (tester) async {
      await _pumpScreen(tester);
      final back = tester.getRect(_back);
      final filters = tester.getRect(_filters);
      final list = tester.element(find.byType(CountrymenGamesTab));

      await _openSearch(tester);

      final field = _searchField;
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      // The app bar and the tabs are out of reach; nothing floats.
      expect(find.byType(CountryDropdown).hitTestable(), findsNothing);
      expect(find.byType(SegmentedSwitcher).hitTestable(), findsNothing);
      expect(_searchFab.hitTestable(), findsNothing);
      // The same Games list, never rebuilt from scratch.
      expect(tester.element(find.byType(CountrymenGamesTab)), same(list));
      // The chevron and Filters did not move; the board view gave way to
      // the field.
      final close = tester.getRect(_closeSearch);
      expect(close, rectMoreOrLessEquals(back, epsilon: 0.5));
      expect(
        tester.getRect(_inSearch(_filters)),
        rectMoreOrLessEquals(filters, epsilon: 0.5),
      );
      expect(_inSearch(_boardView), findsNothing);
      final fieldRect = tester.getRect(field);
      expect(fieldRect.center.dy, closeTo(close.center.dy, 1));
      expect(close.right, lessThanOrEqualTo(fieldRect.left));
      expect(fieldRect.right, lessThanOrEqualTo(filters.left));

      await tester.enterText(field, 'Carlsen');
      await tester.pump(const Duration(milliseconds: 450));
      expect(_games.searches, ['Carlsen']);

      await tester.tap(_closeSearch);
      // The query goes with the tap, not after the morph.
      expect(_games.clears, 1);
      await _settle(tester);

      expect(_searchHeader, findsNothing);
      expect(find.byType(CountryDropdown).hitTestable(), findsOneWidget);
      expect(find.byType(SegmentedSwitcher).hitTestable(), findsOneWidget);
      expect(_searchFab.hitTestable(), findsOneWidget);
      expect(_games.clears, 1);
    });

    testWidgets('system back closes the search, not Countrymen', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await _openSearch(tester);
      await tester.enterText(_searchField, 'Najdorf');
      await tester.pump(const Duration(milliseconds: 450));

      await tester.binding.handlePopRoute();
      await _settle(tester);

      expect(find.byType(CountrymenTabScreen), findsOneWidget);
      expect(_searchHeader, findsNothing);
      expect(find.byType(CountryDropdown).hitTestable(), findsOneWidget);
      expect(_games.clears, 1);
    });

    testWidgets('Filters opens the games filter, in the app bar as in the '
        'search', (tester) async {
      await _pumpScreen(tester);

      await tester.tap(_filters);
      await _settle(tester);
      expect(find.text('Apply Filters'), findsOneWidget);
    });

    testWidgets('Live first pressed with nothing in play says so and stays '
        'off', (tester) async {
      // Floated by a game that has since finished: the press finds none.
      await _pumpScreen(tester, anyLive: true);

      // No count known: it reads "Live now".
      expect(find.bySemanticsLabel('Show live games first'), findsOneWidget);
      await tester.tap(_liveFirst);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(kNoLiveGamesRightNowMessage), findsOneWidget);
      expect(kNoLiveGamesRightNowMessage, 'No live games right now');
      expect(_liveFirstOn(), isFalse);
      expect(tester.widget<LiveFirstCapsule>(_liveFirst).on, isFalse);
    });

    testWidgets('Live first floats only while a game is in play, above the '
        'search, says how many, and turns on and off', (tester) async {
      final container = ProviderContainer(
        overrides: [
          ..._serverLive(const [], serverLive: const {'live'}),
          countrymenCombinedGamesProvider.overrideWith(
            (ref) => _FakeGames(
              games: [
                _game('done', lastMoveTime: DateTime.now()),
                _game('live', lastMoveTime: DateTime.now(), ongoing: true),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return const Scaffold(
                  floatingActionButton: CountrymenGamesFabs(),
                );
              },
            ),
          ),
        ),
      );
      final provider = gameListLiveFirstProvider(
        GameListLiveFirstSurface.countrymen,
      );

      expect(
        tester.getRect(_liveFirst).bottom,
        lessThan(tester.getRect(_searchFab).top),
      );
      expect(find.bySemanticsLabel(_liveLabel(1)), findsOneWidget);
      expect(tester.widget<LiveFirstCapsule>(_liveFirst).liveCount, 1);
      await tester.tap(_liveFirst);
      await _settle(tester);
      expect(container.read(provider), isTrue);
      expect(find.text(kNoLiveGamesRightNowMessage), findsNothing);
      expect(tester.widget<LiveFirstCapsule>(_liveFirst).on, isTrue);
      expect(
        find.byKey(const ValueKey('live_first_capsule_on')),
        findsOneWidget,
      );

      await tester.tap(_liveFirst);
      await _settle(tester);
      expect(container.read(provider), isFalse);
      expect(_liveFirst, findsOneWidget);
      expect(find.bySemanticsLabel(_liveLabel(1)), findsOneWidget);
    });

    testWidgets('the list keeps clear of the whole button stack over the '
        'home indicator', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          countrymenCombinedGamesProvider.overrideWith((ref) => _FakeGames()),
          countrymenGamesAnyLiveProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return const Scaffold(
                  // Where the Games list sits: the Scaffold's body.
                  body: SizedBox.expand(key: ValueKey('list')),
                  floatingActionButton: CountrymenGamesFabs(),
                );
              },
            ),
          ),
        ),
      );

      final top = tester.getRect(_liveFirst).top;
      final reach = CountrymenGamesFabs.reach(
        tester.element(find.byKey(const ValueKey('list'))),
      );
      expect(852 - top, closeTo(reach, 0.01));
    });

    testWidgets('Events mode carries none of the Games controls, and floats '
        'its own search', (tester) async {
      await _pumpScreen(tester, mode: CountrymenScreenMode.events);

      for (final control in [_liveFirst, _filters, _boardView]) {
        expect(control, findsNothing);
      }
      expect(_searchFab, findsOneWidget);
      expect(find.byTooltip('Search events'), findsOneWidget);
      expect(find.byType(CountryDropdown), findsOneWidget);

      // The picker hugs its flag and name instead of stretching across the
      // row it has to itself here.
      final picker = tester.getRect(find.byType(CountryDropdown));
      expect(picker.width, lessThan(393 / 2));
    });

    for (final (label, size, scale, pinInMenu) in [
      ('320 wide', const Size(320, 568), 1.0, true),
      ('320 wide, large text', const Size(320, 568), 1.5, true),
      ('375 wide', const Size(375, 667), 1.0, true),
      ('393 wide, large text', const Size(393, 852), 1.5, true),
      ('540 wide', const Size(540, 900), 1.0, false),
    ]) {
      testWidgets('fits a $label screen with a temporary country', (
        tester,
      ) async {
        await _pumpScreen(
          tester,
          size: size,
          textScale: scale,
          temporary: _germany,
        );

        expect(tester.takeException(), isNull);
        expect(_boardView, findsOneWidget);
        final board = tester.getRect(_boardView);
        expect(tester.getRect(_filters).right, lessThanOrEqualTo(size.width));

        if (!pinInMenu) {
          // Room beside the name: the Pin stays in the row.
          final pin = tester.getRect(find.bySemanticsLabel(_pinGermany));
          expect(pin.right, lessThanOrEqualTo(board.left));
          return;
        }
        // No room for a Pin beside the name and the toolbar: the country
        // menu leads with it.
        expect(find.bySemanticsLabel(_pinGermany), findsNothing);
        await _openCountryMenu(tester);
        expect(tester.takeException(), isNull);
        final pin = tester.getRect(find.text(_pinGermany));
        expect(pin.left, greaterThanOrEqualTo(0));
        expect(pin.right, lessThanOrEqualTo(size.width));
        expect(pin.top, greaterThanOrEqualTo(0));
        expect(pin.bottom, lessThanOrEqualTo(size.height));
      });
    }

    testWidgets('the search row fits a 320pt phone at the largest text size', (
      tester,
    ) async {
      await _pumpScreen(tester, size: const Size(320, 568), textScale: 1.5);
      await _openSearch(tester);

      expect(tester.takeException(), isNull);
      for (final target in [
        _closeSearch,
        _inSearch(_filters),
      ]) {
        final rect = tester.getRect(target);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
      }
      expect(tester.getSize(_searchField).width, greaterThanOrEqualTo(80));
    });
  });

  group('Countrymen search keeps the Games list (continuity)', () {
    Finder cards() => find.byType(GridGameCardWrapperWidget);
    ScrollableState scrollable(WidgetTester tester) =>
        tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          ),
        );
    const refetchLine = ValueKey('games_list_refetch_line');

    testWidgets('opening and closing the search keeps the list: no spinner, '
        'no remount, a quiet line while a query loads, and Live first counts '
        'the games in play', (tester) async {
      final now = DateTime.now();
      final done = _game('done', lastMoveTime: now);
      final live = _game('live', lastMoveTime: now, ongoing: true);
      // The grid's cards: the same list in any view mode.
      await _pumpScreen(
        tester,
        games: [done, live],
        viewMode: GamesListViewMode.chessBoardGrid,
      );
      final list = scrollable(tester);
      expect(cards(), findsNWidgets(2));
      // Live first, in words: how many are live on the list.
      expect(find.bySemanticsLabel(_liveLabel(1)), findsOneWidget);
      expect(tester.widget<LiveFirstCapsule>(_liveFirst).liveCount, 1);

      await _openSearch(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(scrollable(tester), same(list));
      expect(cards(), findsNWidgets(2));

      final pending = Completer<List<GamesTourModel>>();
      _games.nextSearch = pending;
      await tester.enterText(_searchField, 'Carlsen');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 300));
      // The query is on its way: the list stays, a quiet line over it.
      expect(_games.searches, ['Carlsen']);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(cards(), findsNWidgets(2));
      expect(find.byKey(refetchLine), findsOneWidget);

      pending.complete([done]);
      await _settle(tester);
      expect(cards(), findsOneWidget);
      expect(scrollable(tester), same(list));
      expect(find.byKey(refetchLine), findsNothing);

      await tester.tap(_closeSearch);
      await tester.pump();
      // The query goes with the tap, once, and the list it replaced is back
      // in the same frame, as it was.
      expect(_games.clears, 1);
      expect(cards(), findsNWidgets(2));
      await _settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(scrollable(tester), same(list));
      expect(cards(), findsNWidgets(2));
      expect(find.bySemanticsLabel(_liveLabel(1)), findsOneWidget);
      expect(_games.clears, 1);

      // The live card's own timers run out once it is gone.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('the hits start at their top, and closing puts the list back '
        'where it was left, in the frame the list comes back', (tester) async {
      final now = DateTime.now();
      final games = [
        for (var i = 0; i < 24; i++) _game('g$i', lastMoveTime: now),
      ];
      await _pumpScreen(
        tester,
        games: games,
        viewMode: GamesListViewMode.chessBoardGrid,
      );
      final position = scrollable(tester).position;
      position.jumpTo(320);
      await tester.pump();
      // Where a card sits in the list (the header above it springs between
      // its two heights, so the list's own top is the reference).
      final card = find.byKey(const ValueKey('cmen_grid_game_g4'));
      double inList() =>
          tester.getTopLeft(card).dy -
          tester.getTopLeft(find.byType(CustomScrollView)).dy;
      final placed = inList();

      await _openSearch(tester);
      // Opening moves nothing.
      expect(position.pixels, closeTo(320, 0.5));
      _games.nextSearch = Completer<List<GamesTourModel>>()
        ..complete([games.first]);
      await tester.enterText(_searchField, 'Carlsen');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      expect(cards(), findsOneWidget);
      expect(position.pixels, 0);

      await tester.tap(_closeSearch);
      await tester.pump();
      // One frame: the whole list, laid out at the reader's place (not at
      // the hits' top first, then moved).
      expect(position.pixels, closeTo(320, 0.5));
      expect(inList(), closeTo(placed, 0.5));
      await _settle(tester);
      expect(position.pixels, closeTo(320, 0.5));
      expect(scrollable(tester).position, same(position));
    });

    testWidgets('opening and closing the search at the end of the list keeps '
        'every card where it was, with or without hits between', (
      tester,
    ) async {
      final now = DateTime.now();
      final games = [
        for (var i = 0; i < 10; i++) _game('g$i', lastMoveTime: now),
      ];
      await _pumpScreen(
        tester,
        games: games,
        viewMode: GamesListViewMode.chessBoardGrid,
      );
      final position = scrollable(tester).position;
      position.jumpTo(position.maxScrollExtent);
      await _settle(tester);
      final end = position.pixels;
      expect(end, greaterThan(0));
      final last = find.byKey(const ValueKey('cmen_grid_game_g9'));
      final placed = tester.getTopLeft(last).dy;
      final listContext = tester.element(find.byType(CountrymenGamesTab));
      final room = CountrymenGamesFabs.reach(listContext);
      final timeline = SearchModeScope.maybeOf(listContext)!.timeline;

      // Every frame of the morph: the header springs, and the list's end
      // gives up the floating buttons' room on the morph's own timeline
      // (SearchModeListEnd). At the very end of the list every card moves
      // exactly as far as that room, with the morph: no jump on the tap, no
      // jump as hits land, no bounce off the list's end.
      Future<void> expectWithMorph(Future<void> Function() action) async {
        await action();
        for (var i = 0; i < 14; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(
            tester.getTopLeft(last).dy,
            closeTo(placed + room * timeline.value, 0.5),
          );
        }
      }

      await expectWithMorph(() => tester.tap(_searchFab));
      expect(_searchField, findsOneWidget);
      // Open, the room is gone: the last card sits that much lower.
      expect(tester.getTopLeft(last).dy, closeTo(placed + room, 0.5));
      await expectWithMorph(() => tester.tap(_closeSearch));
      await _settle(tester);
      expect(position.pixels, closeTo(end, 0.01));
      expect(tester.getTopLeft(last).dy, closeTo(placed, 0.01));

      // Hits between: they start at their top, and the list comes back to
      // its end in the frame it comes back.
      await _openSearch(tester);
      _games.nextSearch = Completer<List<GamesTourModel>>()
        ..complete([games.first]);
      await tester.enterText(_searchField, 'Carlsen');
      await tester.pump(const Duration(milliseconds: 450));
      await _settle(tester);
      expect(cards(), findsOneWidget);
      expect(position.pixels, 0);
      await expectWithMorph(() => tester.tap(_closeSearch));
      await _settle(tester);
      expect(position.pixels, closeTo(end, 0.01));
      expect(scrollable(tester).position, same(position));
    });

    testWidgets('a search from an empty list keeps it on screen while the '
        'query loads: never the full-page spinner', (tester) async {
      await _pumpScreen(tester);
      expect(find.text('No games found'), findsOneWidget);

      await _openSearch(tester);
      final pending = Completer<List<GamesTourModel>>();
      _games.nextSearch = pending;
      await tester.enterText(_searchField, 'Carlsen');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_games.searches, ['Carlsen']);
      expect(find.text('Loading games...'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No games found'), findsOneWidget);
      expect(find.byKey(refetchLine), findsOneWidget);

      pending.complete(const []);
      await _settle(tester);
      // The one no-matches line every Games list shows, echoing the words.
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('search_no_matches_title')))
            .data,
        SearchNoMatches.titleFor(query: 'Carlsen'),
      );
      expect(find.byKey(refetchLine), findsNothing);

      // Its way back empties the field; the search stays open.
      await tester.tap(find.byKey(const ValueKey('search_no_matches_clear')));
      await tester.pump();
      expect(_searchField, findsOneWidget);
      expect(tester.widget<TextField>(_searchField).controller!.text, isEmpty);
      expect(_games.clears, 1);
    });

    testWidgets('a day folded on the list opens for the search and is folded '
        'again after it', (tester) async {
      final done = _game('done', lastMoveTime: DateTime.now());
      await _pumpScreen(
        tester,
        games: [done],
        viewMode: GamesListViewMode.chessBoardGrid,
      );

      await tester.tap(find.textContaining('Today'));
      await tester.pump();
      expect(cards(), findsNothing);

      await _openSearch(tester);
      _games.nextSearch = Completer<List<GamesTourModel>>()..complete([done]);
      await tester.enterText(_searchField, 'Carlsen');
      await tester.pump(const Duration(milliseconds: 450));
      await _settle(tester);
      // The hit is not hidden behind the plain list's fold.
      expect(cards(), findsOneWidget);

      await tester.tap(_closeSearch);
      await _settle(tester);
      expect(cards(), findsNothing);
    });

    testWidgets('with nothing live, Live first shows only while it is on, '
        'so it can be turned off', (tester) async {
      await _pumpScreen(tester);
      expect(_liveFirst, findsNothing);

      _container
              .read(
                gameListLiveFirstProvider(
                  GameListLiveFirstSurface.countrymen,
                ).notifier,
              )
              .state =
          true;
      await tester.pump();
      expect(_liveFirst, findsOneWidget);
      expect(
        find.byKey(const ValueKey('live_first_capsule_on')),
        findsOneWidget,
      );

      await tester.tap(_liveFirst);
      await _settle(tester);
      expect(_liveFirstOn(), isFalse);
      expect(_liveFirst, findsNothing);
    });
  });

  group('Countrymen search on every tab (Trello #1420)', () {
    testWidgets('Events searches its own list from the same button and '
        'header, and closing clears it', (tester) async {
      await _pumpScreen(tester, mode: CountrymenScreenMode.events);
      final back = tester.getRect(_back);
      // No field on the list itself.
      expect(find.byType(TextField), findsNothing);

      await _openSearch(tester);
      expect(_searchField, findsOneWidget);
      expect(
        tester.getRect(_closeSearch),
        rectMoreOrLessEquals(back, epsilon: 0.5),
      );
      // Nothing of the Games toolbar beside the field.
      expect(_inSearch(_filters), findsNothing);

      await tester.enterText(_searchField, 'Norway Chess');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      expect(_events.searches, ['Norway Chess']);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('search_no_matches_title')))
            .data,
        SearchNoMatches.titleFor(query: 'Norway Chess', subject: 'events'),
      );

      await tester.tap(_closeSearch);
      await _settle(tester);
      expect(_events.searches.last, '');
      expect(_searchField, findsNothing);
      // The Games list was never searched.
      expect(_games.searches, isEmpty);
      expect(_games.clears, 0);
    });

    testWidgets('Rankings sends the query to the country ranking', (
      tester,
    ) async {
      _rankingQueries.clear();
      await _pumpScreen(tester, mode: CountrymenScreenMode.players);
      expect(find.byTooltip('Search players'), findsOneWidget);
      // The first page, unsearched.
      expect(_rankingQueries, ['']);

      await _openSearch(tester);
      await tester.enterText(_searchField, 'Carlsen');
      await tester.pump(const Duration(milliseconds: 450));
      await _settle(tester);
      expect(_rankingQueries.last, 'Carlsen');

      await tester.tap(_closeSearch);
      await _settle(tester);
      expect(_rankingQueries.last, '');
      expect(_games.searches, isEmpty);
    });
  });

  group('Countrymen app bar semantics', () {
    testWidgets('every control offers a tap to assistive tech', (tester) async {
      final semantics = tester.ensureSemantics();
      // Wide enough for the Pin beside the name and the toolbar.
      await _pumpScreen(
        tester,
        size: const Size(540, 900),
        temporary: _germany,
      );

      void expectTappable(List<String> labels, {Finder? within}) {
        for (final label in labels) {
          final byLabel = find.bySemanticsLabel(label);
          final data = tester
              .getSemantics(
                within == null
                    ? byLabel
                    : find.descendant(of: within, matching: byLabel),
              )
              .getSemanticsData();
          expect(data.hasAction(SemanticsAction.tap), isTrue, reason: label);
        }
      }

      // Back is the canonical PageBackButton: an IconButton, whose tooltip
      // is its accessible name.
      expect(
        tester
            .getSemantics(
              find
                  .descendant(
                    of: find.byType(PageBackButton),
                    matching: find.byTooltip('Back'),
                  )
                  .first,
            )
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      expectTappable([
        BoardViewToggleButton.label,
        'Filters',
        _pinGermany,
        'Search games',
      ]);

      await _openSearch(tester);
      expectTappable(['Filters'], within: _searchHeader);
      // An IconButton's tooltip is its accessible name.
      expect(
        tester
            .getSemantics(_closeSearch)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      semantics.dispose();
    });
  });

  group('Countrymen country name beside the board view', () {
    setUpAll(_loadInter);

    for (final (label, temporary, pinned) in [
      ('a temporary Germany', _germany, null),
      ('a temporary United States', _unitedStates, null),
      ('a pinned United States', null, _unitedStates),
    ]) {
      testWidgets('shows $label whole on a 393pt phone', (tester) async {
        await _pumpScreen(tester, temporary: temporary, pinned: pinned);

        expect(tester.takeException(), isNull);
        _expectWholeName(tester, (temporary ?? pinned)!.name);
      });
    }

    testWidgets('keeps at least 40pt for the name on a 320pt phone', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        size: const Size(320, 568),
        temporary: _germany,
      );

      expect(tester.takeException(), isNull);
      final name = _nameParagraph(tester, 'Germany');
      expect(name.constraints.maxWidth, greaterThanOrEqualTo(40));
      _expectWholeName(tester, 'Germany');
    });

    testWidgets('the country menu leads with Pin, and it pins the country', (
      tester,
    ) async {
      // Too narrow for the Pin beside the name and the board view.
      await _pumpScreen(
        tester,
        size: const Size(320, 568),
        temporary: _germany,
      );
      expect(find.bySemanticsLabel(_pinGermany), findsNothing);

      await _openCountryMenu(tester);
      // First in the menu, above its search field.
      expect(
        tester.getRect(find.text(_pinGermany)).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(TextFormField)).top),
      );
      await tester.tap(find.text(_pinGermany));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_country.pinned, ['DE']);
      expect(_container.read(temporaryCountryProvider), isNull);
      // The menu closed behind the pick.
      expect(find.text(_pinGermany), findsNothing);
      expect(find.text('Germany pinned as default'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    for (final (label, mode, size) in [
      ('a wide Games row', CountrymenScreenMode.games, const Size(540, 900)),
      ('Events mode', CountrymenScreenMode.events, const Size(393, 852)),
      (
        'Events mode on 320pt',
        CountrymenScreenMode.events,
        const Size(320, 568),
      ),
    ]) {
      testWidgets('$label keeps the Pin in the row, out of the menu', (
        tester,
      ) async {
        await _pumpScreen(tester, mode: mode, size: size, temporary: _germany);

        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel(_pinGermany), findsOneWidget);
        expect(
          tester
              .widget<CountryDropdown>(find.byType(CountryDropdown))
              .onPinAsDefault,
          isNull,
        );
      });
    }
  });

  group('groupCountrymenGamesByDay', () {
    // Local noon-ish times, seconds apart, so the local day and the UTC day
    // agree for every game of a bucket in any time zone.
    final now = DateTime(2026, 11, 17, 11, 0, 10);
    final today = DateTime(2026, 11, 17, 11);
    final yesterday = DateTime(2026, 11, 16, 11);

    final games = [
      _game('a', lastMoveTime: today),
      _game(
        'b',
        lastMoveTime: today.add(const Duration(seconds: 1)),
        ongoing: true,
      ),
      _game('c', lastMoveTime: today.add(const Duration(seconds: 2))),
      _game(
        'd',
        lastMoveTime: today.add(const Duration(seconds: 3)),
        ongoing: true,
      ),
      // Marked ongoing but its last move was yesterday: not live.
      _game('e', lastMoveTime: yesterday, ongoing: true),
      _game('f', lastMoveTime: yesterday.add(const Duration(seconds: 1))),
    ];

    List<List<String>> ids(Map<String, List<GamesTourModel>> grouped) => [
      for (final day in grouped.values) [for (final g in day) g.gameId],
    ];

    test('keeps the provider order when Live first is off', () {
      final grouped = groupCountrymenGamesByDay(games, now: now);
      expect(ids(grouped), [
        ['a', 'b', 'c', 'd'],
        ['e', 'f'],
      ]);
    });

    test('puts each day\'s live games first when Live first is on', () {
      final grouped = groupCountrymenGamesByDay(
        games,
        liveFirst: true,
        now: now,
      );
      expect(ids(grouped), [
        ['b', 'd', 'a', 'c'],
        ['e', 'f'],
      ]);
      // Days stay newest first.
      expect(grouped.keys.first.compareTo(grouped.keys.last), greaterThan(0));
    });

    test('with the server\'s set, every game in play leads today', () {
      final grouped = groupCountrymenGamesByDay(
        games,
        liveFirst: true,
        // 'e' is in play after midnight; 'b' has finished by the server.
        liveIds: const {'d', 'e'},
        now: now,
      );
      expect(ids(grouped), [
        ['d', 'e', 'a', 'b', 'c'],
        ['f'],
      ]);
    });
  });

  group('Countrymen Live first counts what the server has in play', () {
    testWidgets('games in play the loaded days miss are counted, and listed '
        'as it turns on', (tester) async {
      final now = DateTime.now();
      await _pumpScreen(
        tester,
        viewMode: GamesListViewMode.chessBoardGrid,
        games: [
          _game('done', lastMoveTime: now),
          _game('live', lastMoveTime: now, ongoing: true),
        ],
        serverLive: const {'live', 'later'},
      );
      _games.rows['later'] = _game('later', lastMoveTime: now, ongoing: true);

      expect(find.bySemanticsLabel(_liveLabel(2)), findsOneWidget);
      await tester.tap(_liveFirst);
      await _settle(tester);

      expect(_liveFirstOn(), isTrue);
      expect(_games.listed.first, {'live', 'later'});
      expect(find.byType(GridGameCardWrapperWidget), findsNWidgets(3));
      await _dropLiveCards(tester);
    });

    testWidgets('a row that reads in play is not counted when the server '
        'has nothing in play', (tester) async {
      await _pumpScreen(
        tester,
        viewMode: GamesListViewMode.chessBoardGrid,
        games: [_game('live', lastMoveTime: DateTime.now(), ongoing: true)],
        serverLive: const {},
      );
      expect(_liveFirst, findsNothing);
      await _dropLiveCards(tester);
    });

    testWidgets(
      'announces Live first without a count while the server answers',
      (tester) async {
        await _pumpScreen(
          tester,
          viewMode: GamesListViewMode.chessBoardGrid,
          games: [_game('live', lastMoveTime: DateTime.now(), ongoing: true)],
          serverAnswered: false,
        );
        expect(find.bySemanticsLabel('Show live games first'), findsOneWidget);
        await _dropLiveCards(tester);
      },
    );

    testWidgets('covered by a board the count waits, and asks again on the '
        'way back', (tester) async {
      await _pumpScreen(
        tester,
        viewMode: GamesListViewMode.chessBoardGrid,
        games: [_game('live', lastMoveTime: DateTime.now(), ongoing: true)],
      );
      final poll = _polls.last;
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );

      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        ),
      );
      await _settle(tester);
      expect(poll.visible, isFalse);

      navigator.pop();
      await _settle(tester);
      expect(poll.visible, isTrue);
      expect(poll.refreshes, 1);
      await _dropLiveCards(tester);
    });

    testWidgets('back from a board after a resume it missed, the poll asks '
        'by itself and the page does not ask again', (tester) async {
      await _pumpScreen(
        tester,
        viewMode: GamesListViewMode.chessBoardGrid,
        games: [_game('live', lastMoveTime: DateTime.now(), ongoing: true)],
      );
      final poll = _polls.last;
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );

      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        ),
      );
      await _settle(tester);
      // The real poll marks this missed while hidden, and asks for it as it
      // is shown again.
      _container.read(appResumedSignalProvider.notifier).state++;

      navigator.pop();
      await _settle(tester);
      expect(poll.visible, isTrue);
      expect(poll.refreshes, 0);
      await _dropLiveCards(tester);
    });
  });
}

/// Takes the screen down and lets the live cards' own timers run out.
Future<void> _dropLiveCards(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(minutes: 1));
}
