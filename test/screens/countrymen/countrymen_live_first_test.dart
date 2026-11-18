import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/game_list_live_first_provider.dart';
import 'package:chessever2/screens/countrymen/countrymen_tab_screen.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_combined_games_provider.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_mode_provider.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_events_tab.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_games_tab.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/country_dropdown.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Records filters and searches instead of refetching from Supabase.
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

  @override
  Future<void> applyFilter(GameFilter filter) async {
    applied.add(filter);
    state = state.copyWith(filter: filter);
  }

  @override
  Future<void> searchGames(String query) async {
    searches.add(query);
    state = state.copyWith(searchQuery: query.trim());
  }

  @override
  Future<void> clearSearch() async {
    clears++;
    state = state.copyWith(searchQuery: '');
  }

  @override
  Future<void> refreshGames() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEvents extends StateNotifier<CountrymenEventsState>
    implements CountrymenEventsNotifier {
  _FakeEvents() : super(const CountrymenEventsState(hasMore: false));

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

final Country _norway = CountryService().findByCode('NO')!;
final Country _germany = CountryService().findByCode('DE')!;
final Country _unitedStates = CountryService().findByCode('US')!;

late _FakeGames _games;
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
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final persisted = pinned ?? _norway;
  final shown = temporary ?? persisted;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        countrymenCombinedGamesProvider.overrideWith(
          (ref) => _games = _FakeGames(),
        ),
        countrymenEventsProvider.overrideWith((ref) => _FakeEvents()),
        countryDropdownProvider.overrideWith(
          (ref) => _country = _FakeCountry(persisted),
        ),
        temporaryCountryProvider.overrideWith((ref) => temporary),
        effectiveCountryProvider.overrideWithValue(AsyncValue.data(shown)),
        selectedCountrymenModeProvider.overrideWith((ref) => mode),
        gamesListViewModeProvider.overrideWithValue(
          GamesListViewMode.gamesCard,
        ),
        if (anyLive != null)
          countrymenGamesAnyLiveProvider.overrideWith((ref) => anyLive),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
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

Finder get _liveFirst => find.byType(LiveFirstInkFab);
Finder get _classical => find.byType(ClassicalToggleButton);
Finder get _filters => _control('Filters');
Finder get _boardView => _control('Change board view');
Finder get _searchFab => find.byType(SearchInkFab);
Finder get _searchField => find.byType(CountrymenGamesSearchField);
Finder get _closeSearch => find.byTooltip('Close search');

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
    lastMoveTime: lastMoveTime,
  );
}

void main() {
  group('Countrymen Games header and floating buttons (Trello #1420)', () {
    testWidgets('the app bar keeps only the board view beside the picker; '
        'the search and the list controls leave the top', (tester) async {
      await _pumpScreen(tester);

      final picker = tester.getRect(find.byType(CountryDropdown));
      final board = tester.getRect(_boardView);
      expect(board.center.dy, closeTo(picker.center.dy, 1));
      expect(picker.right, lessThanOrEqualTo(board.left));
      expect(board.right, lessThanOrEqualTo(393));
      // The same board-view mark as Favorites.
      expect(
        find.descendant(of: _boardView, matching: find.byType(BoardViewGlyph)),
        findsOneWidget,
      );

      // Nothing is live, so Live first does not float; Classical and Filters
      // wait in the search; no field sits on the page.
      for (final control in [_liveFirst, _classical, _filters]) {
        expect(control, findsNothing);
      }
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

    testWidgets('the search opens in place: back, the field, Classical and '
        'Filters over the same Games list, and back closes it', (tester) async {
      await _pumpScreen(tester);
      await _openSearch(tester);

      final field = find.descendant(
        of: _searchField,
        matching: find.byType(TextField),
      );
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      // The header is the search row alone: no picker, no tabs, nothing
      // floating.
      expect(find.byType(CountryDropdown), findsNothing);
      expect(find.byType(SegmentedSwitcher), findsNothing);
      expect(_searchFab, findsNothing);
      expect(find.byType(CountrymenGamesTab), findsOneWidget);
      // One row, left to right: back, field, Classical, Filters.
      final close = tester.getRect(_closeSearch);
      final fieldRect = tester.getRect(field);
      final classical = tester.getRect(_classical);
      final filters = tester.getRect(_filters);
      for (final rect in [fieldRect, classical, filters]) {
        expect(rect.center.dy, closeTo(close.center.dy, 1));
      }
      expect(close.right, lessThanOrEqualTo(fieldRect.left));
      expect(fieldRect.right, lessThanOrEqualTo(classical.left));
      expect(classical.right, lessThanOrEqualTo(filters.left));

      await tester.enterText(field, 'Carlsen');
      await tester.pump(const Duration(milliseconds: 450));
      expect(_games.searches, ['Carlsen']);

      await tester.tap(_closeSearch);
      await _settle(tester);

      expect(_searchField, findsNothing);
      expect(find.byType(CountryDropdown), findsOneWidget);
      expect(find.byType(SegmentedSwitcher), findsOneWidget);
      expect(_searchFab, findsOneWidget);
      expect(_games.clears, 1);
    });

    testWidgets('system back closes the search, not Countrymen', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await _openSearch(tester);

      await tester.binding.handlePopRoute();
      await _settle(tester);

      expect(find.byType(CountrymenTabScreen), findsOneWidget);
      expect(_searchField, findsNothing);
      expect(find.byType(CountryDropdown), findsOneWidget);
      expect(_games.clears, 1);
    });

    testWidgets('Classical in the search toggles the server-side '
        'time-control filter', (tester) async {
      await _pumpScreen(tester);
      await _openSearch(tester);

      await tester.tap(_classical);
      await tester.pump();
      expect(_games.applied.last.timeControl, GameTimeControlFilter.classical);
      expect(tester.widget<ClassicalToggleButton>(_classical).pressed, isTrue);
      // The time control is an active filter, so the Filters glyph counts it.
      final filters = tester.widget<QuickToggleIconButton>(_filters);
      expect(filters.selected, isTrue);
      expect(filters.badgeCount, 1);

      await tester.tap(_classical);
      await tester.pump();
      expect(_games.applied.last.timeControl, GameTimeControlFilter.all);
      expect(tester.widget<ClassicalToggleButton>(_classical).pressed, isFalse);
      expect(_games.applied, hasLength(2));
    });

    testWidgets('Classical stays applied once the search closes, counted on '
        'the floating search', (tester) async {
      await _pumpScreen(tester);
      expect(tester.widget<SearchInkFab>(_searchFab).badgeCount, 0);

      await _openSearch(tester);
      await tester.tap(_classical);
      await tester.pump();
      await tester.tap(_closeSearch);
      await _settle(tester);

      // Only the query goes with the search; the filter keeps its sign.
      expect(
        _container.read(countrymenCombinedGamesProvider).filter.timeControl,
        GameTimeControlFilter.classical,
      );
      expect(tester.widget<SearchInkFab>(_searchFab).badgeCount, 1);
      expect(
        find.descendant(of: _searchFab, matching: find.text('1')),
        findsOneWidget,
      );

      await _openSearch(tester);
      await tester.tap(_classical);
      await tester.pump();
      await tester.tap(_closeSearch);
      await _settle(tester);
      expect(tester.widget<SearchInkFab>(_searchFab).badgeCount, 0);
    });

    testWidgets('Filters in the search opens the games filter', (tester) async {
      await _pumpScreen(tester);
      await _openSearch(tester);

      await tester.tap(_filters);
      await _settle(tester);

      expect(find.text('Apply Filters'), findsOneWidget);
    });

    testWidgets('Live first pressed with nothing in play says so and stays '
        'off', (tester) async {
      // Floated by a game that has since finished: the press finds none.
      await _pumpScreen(tester, anyLive: true);

      await tester.tap(_liveFirst);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(kNoLiveGamesRightNowMessage), findsOneWidget);
      expect(kNoLiveGamesRightNowMessage, 'No live games right now');
      expect(_liveFirstOn(), isFalse);
      expect(tester.widget<LiveFirstInkFab>(_liveFirst).on, isFalse);
    });

    testWidgets('Live first floats only while a game is in play, above the '
        'search, and turns on and off', (tester) async {
      final container = ProviderContainer(
        overrides: [
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
      var searches = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  floatingActionButton: CountrymenGamesFabs(
                    onSearch: () => searches++,
                  ),
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
      await tester.tap(_liveFirst);
      await tester.pump();
      expect(container.read(provider), isTrue);
      expect(find.text(kNoLiveGamesRightNowMessage), findsNothing);
      expect(tester.widget<LiveFirstInkFab>(_liveFirst).on, isTrue);

      await tester.tap(_liveFirst);
      await tester.pump();
      expect(container.read(provider), isFalse);
      expect(_liveFirst, findsOneWidget);

      await tester.tap(_searchFab);
      expect(searches, 1);
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
                return Scaffold(
                  // Where the Games list sits: the Scaffold's body.
                  body: const SizedBox.expand(key: ValueKey('list')),
                  floatingActionButton: CountrymenGamesFabs(onSearch: () {}),
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

    testWidgets('Events mode carries none of the Games controls', (
      tester,
    ) async {
      await _pumpScreen(tester, mode: CountrymenScreenMode.events);

      for (final control in [
        _liveFirst,
        _classical,
        _filters,
        _boardView,
        _searchFab,
      ]) {
        expect(control, findsNothing);
      }
      expect(find.byType(CountryDropdown), findsOneWidget);

      // The picker hugs its flag and name instead of stretching across the
      // row it has to itself here.
      final picker = tester.getRect(find.byType(CountryDropdown));
      expect(picker.width, lessThan(393 / 2));
    });

    for (final (label, size, scale, pinInMenu) in [
      ('320 wide', const Size(320, 568), 1.0, true),
      ('320 wide, large text', const Size(320, 568), 1.5, true),
      ('375 wide', const Size(375, 667), 1.0, false),
      ('393 wide, large text', const Size(393, 852), 1.5, false),
    ]) {
      testWidgets('fits a $label phone with a temporary country', (
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
        expect(board.right, lessThanOrEqualTo(size.width));

        if (!pinInMenu) {
          // Room beside the name: the Pin stays in the row.
          final pin = tester.getRect(find.bySemanticsLabel(_pinGermany));
          expect(pin.right, lessThanOrEqualTo(board.left));
          return;
        }
        // No room for a Pin beside the name: the country menu leads with it.
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
      for (final target in [_closeSearch, _classical, _filters]) {
        final rect = tester.getRect(target);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
      }
      expect(tester.getSize(_searchField).width, greaterThanOrEqualTo(80));
    });
  });

  group('Countrymen app bar semantics', () {
    testWidgets('every control offers a tap to assistive tech', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpScreen(tester, temporary: _germany);

      void expectTappable(List<String> labels) {
        for (final label in labels) {
          final data = tester
              .getSemantics(find.bySemanticsLabel(label))
              .getSemanticsData();
          expect(data.hasAction(SemanticsAction.tap), isTrue, reason: label);
        }
      }

      expectTappable([
        'Back',
        BoardViewToggleButton.label,
        _pinGermany,
        'Search games',
      ]);

      await _openSearch(tester);
      expectTappable(['Show classical games only', 'Filters']);
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
      ('a 393pt Games row', CountrymenScreenMode.games, const Size(393, 852)),
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
  });
}
