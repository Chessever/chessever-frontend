import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/app_resume_signal_provider.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/game_list_live_first_provider.dart';
import 'package:chessever2/providers/live_game_ids_provider.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/favorites/favorites_tab_screen.dart';
import 'package:chessever2/screens/favorites/player_games/provider/favorites_combined_games_provider.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_games_tab.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_list_tab.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:chessever2/screens/favorites/widgets/games_list_refetch_line.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/services/discovery_dots/discovery_dots_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/date_time_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/home_top_bar.dart' show PageTitle;
import 'package:chessever2/widgets/live_first_capsule.dart';
import 'package:chessever2/widgets/quick_list_toggles.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search/search_clear_button.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../support/fake_live_game_ids.dart';

const _liveFirstOff = 'Show live games first';
const _classicalOff = 'Show classical games only';
const _boardView = 'Change board view';
const _search = 'Search games';
const _searchFavorites = 'Search favorites';
const _searchPlayers = 'Search players';

/// The search header's Cancel on the Games page, and on the Favorites and
/// Rankings pages: the row's last control, which puts the search away.
const _gamesCancelKey = ValueKey<String>('games_search_close');
const _listCancelKey = ValueKey<String>('favorites_search_close');
const _liveFirstKey = ValueKey<String>('favorites_live_first_fab');
const _filterKey = ValueKey<String>(E2eIds.favoritesGamesFilterButton);
const _searchKey = ValueKey<String>(E2eIds.favoritesGamesSearchField);

/// The full-page search header (built only while the search is open).
Finder get _searchHeader => find.byType(SearchModeHeader);

/// [finder] inside the search header.
Finder _inSearch(Finder finder) =>
    find.descendant(of: _searchHeader, matching: finder);

/// The title row's back button. The search header has none: Cancel, at
/// its row's end, puts the search away.
Finder get _back => find.byTooltip('Back');

/// The open search row, as X sets it: no chevron, the field from the
/// gutter, then [trailing] (the Games page's Filters) when the page has
/// any, and Cancel ([cancelKey]) last, its word ending on the gutter, all on
/// the field's line.
void _expectSearchRow(WidgetTester tester, Key cancelKey, {Finder? trailing}) {
  final gutter = SearchHeaderMetrics.gutter;
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  final cancelTap = _inSearch(find.byKey(cancelKey));
  expect(_inSearch(find.byType(PageBackButton)), findsNothing);
  expect(
    _inSearch(find.byIcon(Icons.arrow_back_ios_new_outlined)),
    findsNothing,
  );
  expect(cancelTap, findsOneWidget);
  final field = tester.getRect(_inSearch(find.byType(SearchFieldFill)));
  final cancel = tester.getRect(cancelTap);
  final word = tester.getRect(
    find.descendant(of: cancelTap, matching: find.text('Cancel')),
  );
  expect(field.left, closeTo(gutter, 0.01));
  if (trailing == null) {
    expect(field.right, closeTo(cancel.left, 0.01));
  } else {
    final controls = tester.getRect(trailing);
    expect(field.right, lessThanOrEqualTo(controls.left));
    expect(controls.right, closeTo(cancel.left, 0.01));
    expect(controls.center.dy, closeTo(field.center.dy, 0.01));
  }
  expect(word.right, closeTo(width - gutter, 0.01));
  expect(word.center.dy, closeTo(field.center.dy, 0.01));
}

/// What Live first reads with [count] games in play, off.
String _liveLabel(int count) =>
    LiveFirstCapsule.semanticsLabelFor(on: false, liveCount: count);

void main() {
  group('Favorites header and floating buttons (Trello #1420)', () {
    testWidgets('Games ends the title row with its toolbar; back sits at '
        'the page\'s leading inset', (tester) async {
      final harness = await _pumpScreen(tester);

      final back = tester.getRect(_back);
      // The canonical back: a 48pt target at the leading inset, right under
      // the status bar's inset (+4).
      expect(back.left, closeTo(SearchHeaderMetrics.leadingInset, 0.01));
      expect(back.width, SearchHeaderMetrics.backTarget);
      expect(back.top, closeTo(4, 0.5));
      // The heart and title are centred on the screen, in the pushed
      // page's title voice, moved toward back only as far as the toolbar's
      // room asks (the test font draws every glyph a full em wide; the
      // app's own type centres it: see the last group).
      final title = tester.getRect(find.byType(PageTitle));
      final boardLeft = tester.getRect(find.byTooltip(_boardView)).left;
      expect(
        title.center.dx,
        closeTo(math.min(393 / 2, boardLeft - 4 - title.width / 2), 1),
      );
      expect(title.left, greaterThan(back.right));
      expect(
        tester.widget<Text>(_titleText()).style?.fontWeight,
        PageTitle.style(tester.element(_titleText())).fontWeight,
      );

      // Board view and Filters, in that order, on back's line. Classical
      // only lives in the filter popup (2026-11-20).
      final board = tester.getRect(find.byTooltip(_boardView));
      final filters = tester.getRect(find.byKey(_filterKey));
      for (final rect in [board, filters]) {
        expect(rect.center.dy, closeTo(back.center.dy, 1));
        expect(rect.width, greaterThanOrEqualTo(44));
      }
      expect(title.right, lessThanOrEqualTo(board.left));
      expect(board.right, lessThanOrEqualTo(filters.left));
      expect(find.byTooltip(_classicalOff), findsNothing);
      // The same board-view mark as Countrymen.
      expect(
        find.descendant(
          of: find.byTooltip(_boardView),
          matching: find.byType(BoardViewGlyph),
        ),
        findsOneWidget,
      );

      // Nothing is live, so Live first does not float; no field sits on the
      // page.
      expect(find.byKey(_liveFirstKey), findsNothing);
      expect(find.byKey(_searchKey), findsNothing);

      // The search floats in the thumb's reach.
      final search = tester.getRect(find.byTooltip(_search));
      expect(search.top, greaterThan(852 / 2));
      expect(search.right, greaterThan(393 / 2));
      expect(harness.created, hasLength(1));
    });

    testWidgets('the title row and tabs fold away with the list, the search '
        'slides with them, and a page change brings them back', (tester) async {
      await _pumpScreen(tester);
      final chrome = ScrollChromeScope.maybeOf(
        tester.element(find.byType(PageView)),
      )!;
      final searchTop = tester.getRect(find.byTooltip(_search)).top;

      chrome.hide(animate: false);
      await tester.pump();

      expect(tester.getSize(find.byType(CollapsingChrome)).height, 0);
      expect(find.byKey(const ValueKey('page_back_float')), findsNothing);
      chrome.show(animate: false);
      await tester.pump();
      expect(_back.hitTestable(), findsOneWidget);
      chrome.hide(animate: false);
      await tester.pump();
      // The status-bar inset is not part of the fold: the list now starts
      // right under it.
      expect(tester.getTopLeft(find.byType(PageView)).dy, greaterThan(0));
      expect(
        tester.getRect(find.byTooltip(_search)).top,
        greaterThan(searchTop),
      );

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await _settle(tester);
      expect(chrome.value, 1);
      expect(find.byType(SegmentedSwitcher), findsOneWidget);
    });

    testWidgets('opening on another page never mounts the Games controls', (
      tester,
    ) async {
      final harness = await _pumpScreen(
        tester,
        initialMode: FavoritesScreenMode.favorites,
      );

      expect(find.byTooltip(_boardView), findsNothing);
      expect(find.byKey(_filterKey), findsNothing);
      expect(find.byTooltip(_search), findsNothing);
      // The page floats its own list's search instead.
      expect(find.byTooltip(_searchFavorites), findsOneWidget);
      // Nothing watched the games list, so no games fetch started.
      expect(harness.created, isEmpty);
    });

    testWidgets('other pages keep the title in place and float their own '
        'search', (tester) async {
      final harness = await _pumpScreen(tester);
      Rect title() => tester.getRect(find.byType(PageTitle));
      final titleOnGames = title();
      final searchOnGames = tester.getRect(find.byTooltip(_search));

      harness.container.read(selectedFavoritesModeProvider.notifier).state =
          FavoritesScreenMode.players;
      await tester.pump();

      expect(find.byTooltip(_boardView), findsNothing);
      expect(find.byKey(_filterKey), findsNothing);
      expect(find.byTooltip(_search), findsNothing);
      // The same search button, at the same spot, searching this list.
      expect(
        tester.getRect(find.byTooltip(_searchPlayers)),
        rectMoreOrLessEquals(searchOnGames, epsilon: 0.5),
      );
      expect(
        find.byKey(const ValueKey(E2eIds.favoritesSearchFab)),
        findsOneWidget,
      );
      // The title never moves when the page changes.
      expect(title(), rectMoreOrLessEquals(titleOnGames, epsilon: 0.01));
    });

    testWidgets('the search opens in place: Filters start where they are '
        'and make room for Cancel, the field takes the title row from the '
        'gutter over the same Games list, and Cancel closes it', (
      tester,
    ) async {
      final harness = await _pumpScreen(tester);
      final back = tester.getRect(_back);
      final filters = tester.getRect(find.byKey(_filterKey));
      final list = tester.element(find.byType(FavoritesGamesTab));

      await tester.tap(find.byTooltip(_search));
      await tester.pump();
      // The tap frame: the search header's Filters start exactly where the
      // title row has them, Cancel's room still shut after them.
      expect(_inSearch(find.byKey(_filterKey)), findsOneWidget);
      expect(
        tester.getRect(_inSearch(find.byKey(_filterKey))),
        rectMoreOrLessEquals(filters, epsilon: 0.5),
      );
      await _settle(tester);

      final field = find.byKey(_searchKey);
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      // The title row and the tabs are out of reach; nothing floats.
      expect(_titleText().hitTestable(), findsNothing);
      expect(find.byType(SegmentedSwitcher).hitTestable(), findsNothing);
      expect(find.byTooltip(_search).hitTestable(), findsNothing);
      // The same Games list, never rebuilt from scratch.
      expect(tester.element(find.byType(FavoritesGamesTab)), same(list));
      // X's row: no chevron, the field from the gutter, Filters after it,
      // Cancel last. The page's own chevron takes no taps meanwhile.
      _expectSearchRow(
        tester,
        _gamesCancelKey,
        trailing: _inSearch(find.byKey(_filterKey)),
      );
      expect(_back.hitTestable(), findsNothing);
      // The board view gives way to the field with the title.
      expect(_inSearch(find.byTooltip(_boardView)), findsNothing);
      // Filters moved in along the row only, by Cancel's room.
      final searchFilters = tester.getRect(_inSearch(find.byKey(_filterKey)));
      expect(searchFilters.top, closeTo(filters.top, 0.5));
      expect(searchFilters.size, filters.size);
      expect(searchFilters.left, lessThan(filters.left));
      final fieldRect = tester.getRect(field);
      expect(fieldRect.center.dy, closeTo(searchFilters.center.dy, 1));
      expect(fieldRect.right, lessThanOrEqualTo(searchFilters.left));

      await tester.enterText(field, 'Carlsen');
      await tester.pump(const Duration(milliseconds: 450));
      expect(harness.notifier.searches, ['Carlsen']);

      await tester.tap(find.byKey(_gamesCancelKey));
      // The query goes with the tap, not after the morph.
      expect(harness.notifier.clears, 1);
      await _settle(tester);

      expect(find.byKey(_searchKey), findsNothing);
      expect(_titleText().hitTestable(), findsOneWidget);
      expect(find.byType(SegmentedSwitcher).hitTestable(), findsOneWidget);
      expect(find.byTooltip(_search).hitTestable(), findsOneWidget);
      expect(harness.notifier.clears, 1);
      expect(harness.created, hasLength(1));
      // The page's way back is where it was, and answers again.
      expect(tester.getRect(_back), rectMoreOrLessEquals(back, epsilon: 0.5));
      expect(_back.hitTestable(), findsOneWidget);
    });

    testWidgets('system back closes the search, not Favorites', (tester) async {
      final harness = await _pumpScreen(tester);
      await _openSearch(tester);
      await tester.enterText(find.byKey(_searchKey), 'Najdorf');
      await tester.pump(const Duration(milliseconds: 450));

      await tester.binding.handlePopRoute();
      await _settle(tester);

      expect(find.byType(FavoritesTabScreen), findsOneWidget);
      expect(find.byKey(_searchKey), findsNothing);
      expect(_titleText().hitTestable(), findsOneWidget);
      expect(harness.notifier.clears, 1);
      expect(
        harness.container.read(favoritesCombinedGamesProvider).searchQuery,
        isEmpty,
      );
    });

    testWidgets('Filters opens the dialog and Apply lands on the same '
        'notifier with its count', (tester) async {
      final harness = await _pumpScreen(tester);

      await tester.tap(find.byKey(_filterKey));
      await _settle(tester);
      final whiteWins = find.text('1-0');
      await tester.ensureVisible(whiteWins);
      await tester.tap(whiteWins);
      await tester.tap(find.text('Apply Filters'));
      await _settle(tester);

      expect(harness.created, hasLength(1));
      expect(
        harness.notifier.applied.single.result,
        GameResultFilter.whiteWins,
      );
      expect(
        find.descendant(of: find.byKey(_filterKey), matching: find.text('1')),
        findsOneWidget,
      );
    });

    testWidgets('Live first pressed with nothing in play says so and stays '
        'off', (tester) async {
      // Floated by a game that has since finished: the press finds none.
      final harness = await _pumpScreen(tester, anyLive: true);

      // No count known: it reads "Live now".
      expect(find.bySemanticsLabel('Show live games first'), findsOneWidget);
      await tester.tap(find.byKey(_liveFirstKey));
      await tester.pump();

      expect(find.text(kNoLiveGamesRightNowMessage), findsOneWidget);
      expect(kNoLiveGamesRightNowMessage, 'No live games right now');
      expect(
        harness.container.read(
          gameListLiveFirstProvider(GameListLiveFirstSurface.favorites),
        ),
        isFalse,
      );
      expect(_toggledState(tester, _liveFirstOff), isFalse);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('with nothing live, Live first shows only while it is on, '
        'so it can be turned off', (tester) async {
      // Left on from earlier, with no game in play now: it stays on screen,
      // reading "Live first", until it is turned off.
      final harness = await _pumpScreen(tester, liveFirst: true);

      expect(find.byKey(_liveFirstKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey('live_first_capsule_on')),
        findsOneWidget,
      );
      // The search still floats where the thumb rests.
      expect(find.byTooltip(_search), findsOneWidget);

      await tester.tap(find.byKey(_liveFirstKey));
      await _settle(tester);
      expect(
        harness.container.read(
          gameListLiveFirstProvider(GameListLiveFirstSurface.favorites),
        ),
        isFalse,
      );
      // Off with nothing live: nothing left for it to do.
      expect(find.byKey(_liveFirstKey), findsNothing);
    });
  });

  group('Favorites search on every tab (Trello #1420)', () {
    final carlsen = _standing('Carlsen, Magnus', 1503014, 2833);
    final nakamura = _standing('Nakamura, Hikaru', 2016192, 2802);

    testWidgets('the Favorites list floats its own search: the field narrows '
        'the followed players as typed, and closing brings them all back', (
      tester,
    ) async {
      final harness = await _pumpScreen(
        tester,
        initialMode: FavoritesScreenMode.favorites,
        favorites: [carlsen, nakamura],
        overrides: [playerPhotoProvider.overrideWith((ref, id) async => null)],
      );
      final back = tester.getRect(_back);
      expect(find.text('Carlsen, Magnus'), findsOneWidget);
      // No field on the list itself.
      expect(find.byType(TextField), findsNothing);
      final fab = find.byKey(const ValueKey(E2eIds.favoritesSearchFab));
      expect(fab, findsOneWidget);
      expect(find.byTooltip(_searchFavorites), findsOneWidget);

      await tester.tap(fab);
      await _settle(tester);

      final field = find.byKey(const ValueKey('favorites_list_search_field'));
      expect(field, findsOneWidget);
      // The same header with nothing of the Games toolbar: the field runs
      // from the gutter up to Cancel.
      _expectSearchRow(tester, _listCancelKey);
      expect(_inSearch(find.byType(SearchModeFilterButton)), findsNothing);
      expect(_back.hitTestable(), findsNothing);
      // Empty, the field draws no clear.
      final clear = _inSearch(find.byKey(const ValueKey('search_field_clear')));
      expect(
        tester.getSize(_inSearch(find.byType(SearchClearButton))).width,
        0,
      );
      expect(clear.hitTestable(), findsNothing);

      await tester.enterText(field, 'naka');
      await tester.pump();
      // As typed, no debounce: the list is on the device.
      expect(harness.container.read(favoritesListSearchQueryProvider), 'naka');
      expect(find.text('Nakamura, Hikaru'), findsOneWidget);
      expect(find.text('Carlsen, Magnus'), findsNothing);
      // The Games list was never read: no games fetch started.
      expect(harness.created, isEmpty);

      // With words, the circled x is in the field, and only empties it: the
      // search stays open, the cursor in the field, every player back.
      await _settle(tester);
      expect(
        tester.getSize(_inSearch(find.byType(SearchClearButton))),
        SearchClearButton.box,
      );
      expect(
        tester.getRect(clear).right,
        lessThanOrEqualTo(
          tester.getRect(_inSearch(find.byType(SearchFieldFill))).right,
        ),
      );
      await tester.tap(clear);
      await _settle(tester);
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      expect(harness.container.read(favoritesListSearchQueryProvider), isEmpty);
      expect(find.text('Carlsen, Magnus'), findsOneWidget);
      expect(find.text('Nakamura, Hikaru'), findsOneWidget);
      expect(clear.hitTestable(), findsNothing);

      await tester.enterText(field, 'naka');
      await tester.pump();
      expect(find.text('Carlsen, Magnus'), findsNothing);
      await tester.tap(find.byKey(_listCancelKey));
      await _settle(tester);
      expect(find.byType(TextField), findsNothing);
      expect(harness.container.read(favoritesListSearchQueryProvider), isEmpty);
      expect(find.text('Carlsen, Magnus'), findsOneWidget);
      expect(find.text('Nakamura, Hikaru'), findsOneWidget);
      expect(harness.created, isEmpty);
      expect(tester.getRect(_back), rectMoreOrLessEquals(back, epsilon: 0.5));
    });

    testWidgets('Rankings sends the settled query to the world ranking, says '
        'when nothing matches, and closing clears it', (tester) async {
      final world = _FakeWorldPlayers([carlsen, nakamura])
        ..all.addAll([carlsen, nakamura]);
      final harness = await _pumpScreen(
        tester,
        initialMode: FavoritesScreenMode.players,
        overrides: [
          worldPlayersSearchProvider.overrideWith((ref) => world),
          favoritePlayersProviderNew.overrideWith(_NoFollowedPlayers.new),
          playerPhotoProvider.overrideWith((ref, id) async => null),
        ],
      );
      expect(find.byType(TextField), findsNothing);
      // Active / All lead the ranking's one filter rail.
      expect(
        tester.getCenter(find.text('Active')).dy,
        closeTo(
          tester
              .getCenter(find.byKey(const ValueKey('ranking-category-overall')))
              .dy,
          0.5,
        ),
      );

      await tester.tap(find.byTooltip(_searchPlayers));
      await _settle(tester);
      final field = find.byKey(
        const ValueKey('favorites_players_search_field'),
      );
      await tester.enterText(field, 'zzz');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      expect(world.searches, ['zzz']);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('search_no_matches_title')))
            .data,
        SearchNoMatches.titleFor(query: 'zzz', subject: 'players'),
      );

      // Its one way back empties the field; the search stays open.
      await tester.tap(find.byKey(const ValueKey('search_no_matches_clear')));
      await tester.pump();
      expect(world.searches.last, '');
      expect(field, findsOneWidget);
      expect(find.text('Carlsen, Magnus'), findsOneWidget);

      await tester.enterText(field, 'carl');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.tap(find.byKey(_listCancelKey));
      await _settle(tester);
      expect(world.searches.last, '');
      expect(find.byType(TextField), findsNothing);
      expect(harness.created, isEmpty);
    });

    testWidgets('a search holds its tab: the pages do not swipe while it is '
        'open', (tester) async {
      await _pumpScreen(
        tester,
        initialMode: FavoritesScreenMode.favorites,
        favorites: [carlsen],
        overrides: [playerPhotoProvider.overrideWith((ref, id) async => null)],
      );
      await tester.tap(find.byTooltip(_searchFavorites));
      await _settle(tester);

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('favorites_list_search_field')),
        findsOneWidget,
      );
      expect(find.text('Carlsen, Magnus'), findsOneWidget);
    });
  });

  group('Favorites search keeps the Games list (continuity)', () {
    testWidgets('opening and closing the search keeps the list: no spinner, '
        'no remount, a quiet line while a query loads', (tester) async {
      final today = DateTime.now();
      final done = _game('done', status: GameStatus.whiteWins, gameDay: today);
      final live = _game(
        'live',
        status: GameStatus.ongoing,
        gameDay: today,
        lastMoveTime: today,
      );
      // The grid's cards: the same list in any view mode.
      final harness = await _pumpScreen(
        tester,
        games: [done, live],
        viewMode: GamesListViewMode.chessBoardGrid,
      );
      final notifier = harness.notifier;
      Finder cards() => find.byType(GridGameCardWrapperWidget);
      ScrollableState scrollable() => tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      final list = scrollable();
      expect(cards(), findsNWidgets(2));
      // Live first counts what is live on the list.
      expect(find.bySemanticsLabel(_liveLabel(1)), findsOneWidget);

      await _openSearch(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(scrollable(), same(list));
      expect(cards(), findsNWidgets(2));
      // Nothing floats while searching, so the list keeps no room for it.
      final listBottom = tester.getBottomLeft(cards().last).dy;

      final pending = Completer<List<GamesTourModel>>();
      notifier.nextSearch = pending;
      await tester.enterText(find.byKey(_searchKey), 'Carlsen');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 300));
      // The query is on its way: the list stays, a quiet line over it.
      expect(notifier.searches, ['Carlsen']);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(cards(), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('games_list_refetch_line')),
        findsOneWidget,
      );

      pending.complete([done]);
      await _settle(tester);
      expect(cards(), findsOneWidget);
      expect(scrollable(), same(list));
      expect(
        find.byKey(const ValueKey('games_list_refetch_line')),
        findsNothing,
      );
      expect(tester.getBottomLeft(cards().last).dy, lessThan(listBottom + 1));

      await tester.tap(find.byKey(_gamesCancelKey));
      await tester.pump();
      // The list it replaced is back in the same frame, as it was.
      expect(cards(), findsNWidgets(2));
      await _settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(scrollable(), same(list));
      expect(cards(), findsNWidgets(2));
      expect(find.bySemanticsLabel(_liveLabel(1)), findsOneWidget);

      // The live card's own timers run out once it is gone.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('opening and closing the search at the end of the list keeps '
        'every card where it was, with or without hits between', (
      tester,
    ) async {
      final today = DateTime.now();
      final games = [
        for (var i = 0; i < 10; i++)
          _game('g$i', status: GameStatus.whiteWins, gameDay: today),
      ];
      final harness = await _pumpScreen(
        tester,
        games: games,
        viewMode: GamesListViewMode.chessBoardGrid,
      );
      ScrollableState scrollable() => tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      final position = scrollable().position;
      position.jumpTo(position.maxScrollExtent);
      await _settle(tester);
      final end = position.pixels;
      expect(end, greaterThan(0));
      final last = find.byKey(const ValueKey('fav_grid_game_g9'));
      final placed = tester.getTopLeft(last).dy;
      final listContext = tester.element(find.byType(FavoritesGamesTab));
      final room = FavoritesGamesFabs.reach(listContext);
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

      await expectWithMorph(() => tester.tap(find.byTooltip(_search)));
      expect(find.byKey(_searchKey), findsOneWidget);
      // Open, the room is gone: the last card sits that much lower.
      expect(tester.getTopLeft(last).dy, closeTo(placed + room, 0.5));
      await expectWithMorph(() => tester.tap(find.byKey(_gamesCancelKey)));
      await _settle(tester);
      expect(position.pixels, closeTo(end, 0.01));
      expect(tester.getTopLeft(last).dy, closeTo(placed, 0.01));

      // Hits between: they start at their top, and the list comes back to
      // its end in the frame it comes back.
      await _openSearch(tester);
      harness.notifier.nextSearch = Completer<List<GamesTourModel>>()
        ..complete([games.first]);
      await tester.enterText(find.byKey(_searchKey), 'Carlsen');
      await tester.pump(const Duration(milliseconds: 450));
      await _settle(tester);
      expect(find.byType(GridGameCardWrapperWidget), findsOneWidget);
      expect(position.pixels, 0);
      await expectWithMorph(() => tester.tap(find.byKey(_gamesCancelKey)));
      await _settle(tester);
      expect(position.pixels, closeTo(end, 0.01));
      expect(scrollable().position, same(position));
    });

    testWidgets('a search from an empty list keeps it on screen while the '
        'query loads: never the full-page spinner', (tester) async {
      final harness = await _pumpScreen(tester);
      const refetchLine = ValueKey('games_list_refetch_line');
      expect(find.text('No games found'), findsOneWidget);

      await _openSearch(tester);
      final pending = Completer<List<GamesTourModel>>();
      harness.notifier.nextSearch = pending;
      await tester.enterText(find.byKey(_searchKey), 'Carlsen');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 300));
      expect(harness.notifier.searches, ['Carlsen']);
      expect(find.text('Loading games...'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No games found'), findsOneWidget);
      expect(find.byKey(refetchLine), findsOneWidget);

      pending.complete(const []);
      await _settle(tester);
      expect(find.text('No games found'), findsNothing);
      expect(find.byKey(refetchLine), findsNothing);
    });

    testWidgets('while searching, only the search header\'s Filters carries '
        'the test id', (tester) async {
      await _pumpScreen(tester);
      expect(find.byKey(_filterKey), findsOneWidget);

      await _openSearch(tester);
      expect(find.byKey(_filterKey), findsOneWidget);
      expect(_inSearch(find.byKey(_filterKey)), findsOneWidget);

      await tester.tap(find.byKey(_gamesCancelKey));
      await _settle(tester);
      expect(find.byKey(_filterKey), findsOneWidget);
      expect(_inSearch(find.byKey(_filterKey)), findsNothing);
    });

    testWidgets('a day folded on the list opens for the search and is folded '
        'again after it', (tester) async {
      final today = DateTime.now();
      final done = _game('done', status: GameStatus.whiteWins, gameDay: today);
      final harness = await _pumpScreen(
        tester,
        games: [done],
        viewMode: GamesListViewMode.chessBoardGrid,
      );
      Finder cards() => find.byType(GridGameCardWrapperWidget);

      await tester.tap(find.textContaining('Today'));
      await tester.pump();
      expect(cards(), findsNothing);

      await _openSearch(tester);
      harness.notifier.nextSearch = Completer<List<GamesTourModel>>()
        ..complete([done]);
      await tester.enterText(find.byKey(_searchKey), 'Carlsen');
      await tester.pump(const Duration(milliseconds: 450));
      await _settle(tester);
      // The hit is not hidden behind the plain list's fold.
      expect(cards(), findsOneWidget);

      await tester.tap(find.byKey(_gamesCancelKey));
      await _settle(tester);
      expect(cards(), findsNothing);
    });
  });

  group('Favorites Live first button with games', () {
    testWidgets('floats only while a game is in play, says how many, and '
        'turns on and off', (tester) async {
      final container = ProviderContainer(
        overrides: [
          ..._serverLive([], const [], serverLive: const {'live'}),
          favoritesCombinedGamesProvider.overrideWith(
            (ref) => _FakeFavoritesGames(
              FavoritesCombinedGamesState(
                hasMore: false,
                games: [
                  _game(
                    'done',
                    status: GameStatus.whiteWins,
                    gameDay: DateTime.now(),
                  ),
                  _game(
                    'live',
                    status: GameStatus.ongoing,
                    lastMoveTime: DateTime.now(),
                  ),
                ],
              ),
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
                  floatingActionButton: FavoritesGamesFabs(),
                );
              },
            ),
          ),
        ),
      );
      final provider = gameListLiveFirstProvider(
        GameListLiveFirstSurface.favorites,
      );

      expect(find.byKey(_liveFirstKey), findsOneWidget);
      expect(find.bySemanticsLabel(_liveLabel(1)), findsOneWidget);
      // Above the search, never over it.
      expect(
        tester.getRect(find.byKey(_liveFirstKey)).bottom,
        lessThan(tester.getRect(find.byTooltip(_search)).top),
      );

      await tester.tap(find.byKey(_liveFirstKey));
      await _settle(tester);
      expect(container.read(provider), isTrue);
      expect(find.text(kNoLiveGamesRightNowMessage), findsNothing);
      expect(
        find.byKey(const ValueKey('live_first_capsule_on')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<LiveFirstCapsule>(find.byType(LiveFirstCapsule))
            .liveCount,
        1,
      );

      await tester.tap(find.byKey(_liveFirstKey));
      await _settle(tester);
      expect(container.read(provider), isFalse);
      // Still a game in play, so it stays to be pressed again.
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
          favoritesCombinedGamesProvider.overrideWith(
            (ref) => _FakeFavoritesGames(
              FavoritesCombinedGamesState(hasMore: false),
            ),
          ),
          favoritesGamesAnyLiveProvider.overrideWith((ref) => true),
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
                  floatingActionButton: FavoritesGamesFabs(),
                );
              },
            ),
          ),
        ),
      );

      final top = tester.getRect(find.byKey(_liveFirstKey)).top;
      final reach = FavoritesGamesFabs.reach(
        tester.element(find.byKey(const ValueKey('list'))),
      );
      expect(852 - top, closeTo(reach, 0.01));
    });
  });

  group('groupFavoriteGamesByDay', () {
    final now = DateTime.utc(2026, 11, 17, 15);
    final today = DateTime.utc(2026, 11, 17);
    final yesterday = DateTime.utc(2026, 11, 16);
    final games = [
      _game('t-done', status: GameStatus.draw, gameDay: today),
      _game('y-done', status: GameStatus.blackWins, gameDay: yesterday),
      _game(
        't-live',
        status: GameStatus.ongoing,
        gameDay: today,
        lastMoveTime: now,
      ),
      _game('t-done-2', status: GameStatus.whiteWins, gameDay: today),
      _game('undated', status: GameStatus.draw),
    ];

    test('keeps the server order inside each day when off', () {
      final grouped = groupFavoriteGamesByDay(games, now: now);
      expect(grouped.keys, ['2026-11-17', '2026-11-16', '0000-00-00']);
      expect(_ids(grouped['2026-11-17']!), ['t-done', 't-live', 't-done-2']);
    });

    test('brings live games to the top of their day when on', () {
      final grouped = groupFavoriteGamesByDay(games, liveFirst: true, now: now);
      expect(grouped.keys, ['2026-11-17', '2026-11-16', '0000-00-00']);
      expect(_ids(grouped['2026-11-17']!), ['t-live', 't-done', 't-done-2']);
      expect(_ids(grouped['2026-11-16']!), ['y-done']);
      expect(_ids(grouped['0000-00-00']!), ['undated']);
    });
  });

  group('groupFavoriteGamesByDay with the server\'s live set', () {
    final now = DateTime.utc(2026, 11, 17, 15);
    final today = DateTime.utc(2026, 11, 17);
    final yesterday = DateTime.utc(2026, 11, 16);
    final games = [
      _game('t-done', status: GameStatus.draw, gameDay: today),
      // Filed under yesterday (the round began before midnight), in play.
      _game('y-live', status: GameStatus.ongoing, gameDay: yesterday),
      _game('y-done', status: GameStatus.blackWins, gameDay: yesterday),
      // Its row reads in play, but the server has no such game in play.
      _game(
        't-shell',
        status: GameStatus.ongoing,
        gameDay: today,
        lastMoveTime: now,
      ),
    ];

    test('every game in play leads today, whatever day it is filed under', () {
      final grouped = groupFavoriteGamesByDay(
        games,
        liveFirst: true,
        liveIds: const {'y-live'},
        now: now,
      );
      expect(grouped.keys, ['2026-11-17', '2026-11-16']);
      expect(_ids(grouped['2026-11-17']!), ['y-live', 't-done', 't-shell']);
      expect(_ids(grouped['2026-11-16']!), ['y-done']);
    });

    test('a day ahead of today keeps the live games on top', () {
      final tomorrow = DateTime.utc(2026, 11, 18);
      final grouped = groupFavoriteGamesByDay(
        [...games, _game('ahead', status: GameStatus.draw, gameDay: tomorrow)],
        liveFirst: true,
        liveIds: const {'y-live'},
        now: now,
      );
      expect(grouped.keys.first, '2026-11-18');
      expect(_ids(grouped['2026-11-18']!), ['y-live', 'ahead']);
    });

    test('off, the server\'s set changes nothing', () {
      final grouped = groupFavoriteGamesByDay(
        games,
        liveIds: const {'y-live'},
        now: now,
      );
      expect(_ids(grouped['2026-11-17']!), ['t-done', 't-shell']);
      expect(_ids(grouped['2026-11-16']!), ['y-live', 'y-done']);
    });
  });

  group('Favorites Live first counts what the server has in play', () {
    final today = DateTime.now();
    final done = _game('done', status: GameStatus.whiteWins, gameDay: today);
    final live = _game(
      'live',
      status: GameStatus.ongoing,
      gameDay: today,
      lastMoveTime: today,
    );

    testWidgets('games in play the loaded days miss are counted, and listed '
        'as it turns on', (tester) async {
      final harness = await _pumpScreen(
        tester,
        initialMode: FavoritesScreenMode.games,
        // The grid's cards: no swipe hint reading the device database.
        viewMode: GamesListViewMode.chessBoardGrid,
        games: [done, live],
        serverLive: const {'live', 'later-1', 'later-2'},
      );
      harness.notifier.rows['later-1'] = _game(
        'later-1',
        status: GameStatus.ongoing,
        gameDay: today,
        lastMoveTime: today,
      );

      expect(find.bySemanticsLabel(_liveLabel(3)), findsOneWidget);
      await tester.tap(find.byKey(_liveFirstKey));
      await _settle(tester);

      expect(harness.notifier.listed.first, {'live', 'later-1', 'later-2'});
      expect(
        harness.container.read(
          gameListLiveFirstProvider(GameListLiveFirstSurface.favorites),
        ),
        isTrue,
      );
      expect(find.byType(GridGameCardWrapperWidget), findsNWidgets(3));
      await _dropLiveCards(tester);
    });

    testWidgets('a game the list already shows as finished is not counted', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        initialMode: FavoritesScreenMode.games,
        // The grid's cards: no swipe hint reading the device database.
        viewMode: GamesListViewMode.chessBoardGrid,
        games: [done, live],
        serverLive: const {'live', 'done'},
      );
      expect(find.bySemanticsLabel(_liveLabel(1)), findsOneWidget);
      await _dropLiveCards(tester);
    });

    testWidgets('a row that reads in play is not counted when the server '
        'has nothing in play', (tester) async {
      await _pumpScreen(
        tester,
        initialMode: FavoritesScreenMode.games,
        // The grid's cards: no swipe hint reading the device database.
        viewMode: GamesListViewMode.chessBoardGrid,
        games: [done, live],
        serverLive: const {},
      );
      expect(find.byKey(_liveFirstKey), findsNothing);
      await _dropLiveCards(tester);
    });

    testWidgets(
      'announces Live first without a count while the server answers',
      (tester) async {
        await _pumpScreen(
          tester,
          initialMode: FavoritesScreenMode.games,
          // The grid's cards: no swipe hint reading the device database.
          viewMode: GamesListViewMode.chessBoardGrid,
          games: [done, live],
          serverAnswered: false,
        );
        expect(find.bySemanticsLabel('Show live games first'), findsOneWidget);
        await _dropLiveCards(tester);
      },
    );

    testWidgets('covered by a board the count waits, and asks again on the '
        'way back', (tester) async {
      final harness = await _pumpScreen(
        tester,
        initialMode: FavoritesScreenMode.games,
        // The grid's cards: no swipe hint reading the device database.
        viewMode: GamesListViewMode.chessBoardGrid,
        games: [done, live],
      );
      final poll = harness.poll;
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );

      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        ),
      );
      await tester.pumpAndSettle();
      expect(poll.visible, isFalse);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(poll.visible, isTrue);
      expect(poll.refreshes, 1);
      await _dropLiveCards(tester);
    });

    testWidgets('back from a board after a resume it missed, the poll asks '
        'by itself and the page does not ask again', (tester) async {
      final harness = await _pumpScreen(
        tester,
        initialMode: FavoritesScreenMode.games,
        // The grid's cards: no swipe hint reading the device database.
        viewMode: GamesListViewMode.chessBoardGrid,
        games: [done, live],
      );
      final poll = harness.poll;
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );

      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        ),
      );
      await tester.pumpAndSettle();
      // The real poll marks this missed while hidden, and asks for it as it
      // is shown again.
      harness.container.read(appResumedSignalProvider.notifier).state++;

      navigator.pop();
      await tester.pumpAndSettle();
      expect(poll.visible, isTrue);
      expect(poll.refreshes, 0);
      await _dropLiveCards(tester);
    });
  });

  group('Favorites Games list end', () {
    testWidgets('one slot of one height whether the next days load or not', (
      tester,
    ) async {
      final today = DateTime.now();
      final harness = await _pumpScreen(
        tester,
        initialMode: FavoritesScreenMode.games,
        viewMode: GamesListViewMode.chessBoardGrid,
        games: [
          for (var i = 0; i < 2; i++)
            _game('g$i', status: GameStatus.draw, gameDay: today),
        ],
      );
      final slot = find.byKey(
        const ValueKey('favorites_games_list_end_slot'),
        skipOffstage: false,
      );
      harness.notifier.state = harness.notifier.state.copyWith(hasMore: true);
      await tester.pump();
      final idle = tester.getSize(slot).height;

      harness.notifier.state = harness.notifier.state.copyWith(isLoading: true);
      await tester.pump();
      expect(
        find.descendant(
          of: slot,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(tester.getSize(slot).height, idle);

      harness.notifier.state = harness.notifier.state.copyWith(
        isLoading: false,
        hasMore: false,
      );
      await tester.pump();
      expect(find.text('No more games'), findsOneWidget);
      expect(tester.getSize(slot).height, idle);
      await _dropLiveCards(tester);
    });
  });

  testWidgets('the quiet line is drawn only while a list is being replaced', (
    tester,
  ) async {
    Future<void> pump(bool active) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(body: GamesListRefetchLine(active: active));
          },
        ),
      ),
    );
    const line = ValueKey('games_list_refetch_line');
    await pump(false);
    expect(find.byKey(line), findsNothing);
    await pump(true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(line), findsOneWidget);
    await pump(false);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(line), findsNothing);
  });

  // Last: the app's own type stays loaded for the rest of the file.
  group('Favorites title and search row in the app\'s type', () {
    setUpAll(() async {
      final inter = FontLoader('InterDisplay');
      for (final weight in const ['Regular', 'Medium', 'Bold']) {
        inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.otf'));
      }
      await inter.load();
    });

    testWidgets('sits centred on a 393pt phone on every page, toolbar or '
        'not', (tester) async {
      final harness = await _pumpScreen(tester);
      Rect title() => tester.getRect(find.byType(PageTitle));
      expect(title().center.dx, closeTo(393 / 2, 1));

      for (final mode in [
        FavoritesScreenMode.favorites,
        FavoritesScreenMode.players,
      ]) {
        harness.container.read(selectedFavoritesModeProvider.notifier).state =
            mode;
        await tester.pump();
        expect(title().center.dx, closeTo(393 / 2, 1), reason: '$mode');
      }
    });

    // In the app's type, not the stock test font: that draws every glyph a
    // full em wide, so Cancel's word would take half again the room a phone
    // gives it and the field's share would be measured short.
    testWidgets('the header and its search row fit a 320pt phone at the '
        'largest text size', (tester) async {
      await _pumpScreen(tester, size: const Size(320, 640), textScale: 1.5);

      expect(tester.takeException(), isNull);
      final filters = tester.getRect(find.byKey(_filterKey));
      expect(filters.right, lessThanOrEqualTo(320));
      final board = tester.getRect(find.byTooltip(_boardView));
      expect(tester.getRect(_titleText()).right, lessThanOrEqualTo(board.left));

      await _openSearch(tester);
      expect(tester.takeException(), isNull);
      // X's row holds on the narrowest phone too: Cancel last, its word on
      // the gutter.
      _expectSearchRow(
        tester,
        _gamesCancelKey,
        trailing: _inSearch(find.byKey(_filterKey)),
      );
      for (final target in [
        find.byKey(_gamesCancelKey),
        _inSearch(find.byKey(_filterKey)),
      ]) {
        final rect = tester.getRect(target);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
      }
      expect(
        tester.getSize(find.byKey(_searchKey)).width,
        greaterThanOrEqualTo(80),
      );
    });
  });
}

/// Opens the Games page's full-page search from its floating button.
Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip(_search));
  await _settle(tester);
}

/// Lets springs and routes finish without waiting on a caret's blink, which
/// never settles while the search field has focus.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The page title's words ("Favorites" is also a tab's name).
Finder _titleText() => find.descendant(
  of: find.byType(PageTitle),
  matching: find.text('Favorites'),
);

bool? _toggledState(WidgetTester tester, String label) {
  final semantics = tester.widget<Semantics>(
    find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    ),
  );
  return semantics.properties.toggled;
}

/// Takes the screen down and lets the live cards' own timers run out.
Future<void> _dropLiveCards(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(minutes: 1));
}

List<String> _ids(List<GamesTourModel> games) => [
  for (final game in games) game.gameId,
];

class _Harness {
  _Harness(this.container, this.created, this.polls);

  final ProviderContainer container;
  final List<_FakeFavoritesGames> created;

  /// The live-game polls the page started, the newest last.
  final List<FakeLiveGameIds> polls;

  _FakeFavoritesGames get notifier => created.last;

  FakeLiveGameIds get poll => polls.last;
}

/// Who the Favorites list asks about in these tests.
final _scope = FavoritesLiveGamesScope(fideIds: const ['1503014']);

/// The boards a fixture marks in play: what the server says by default.
Set<String> _inPlay(Iterable<GamesTourModel> games) => {
  for (final game in games)
    if (game.gameStatus == GameStatus.ongoing) game.gameId,
};

/// The server's games in play for the list ([serverLive], or the fixture's
/// boards in play), or no answer yet when [answered] is false. Each poll
/// the page starts is recorded in [polls].
List<Override> _serverLive(
  List<FakeLiveGameIds> polls,
  List<GamesTourModel> games, {
  Set<String>? serverLive,
  bool answered = true,
}) => [
  favoritesGamesLiveScopeProvider.overrideWith((ref) => _scope),
  favoritesLiveGameIdsProvider.overrideWith((ref, scope) {
    final poll = FakeLiveGameIds(
      answered ? serverLive ?? _inPlay(games) : null,
    );
    polls.add(poll);
    return poll;
  }),
];

Future<_Harness> _pumpScreen(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double textScale = 1,
  FavoritesScreenMode? initialMode,
  bool liveFirst = false,
  bool? anyLive,
  List<GamesTourModel> games = const [],
  GamesListViewMode viewMode = GamesListViewMode.gamesCard,
  List<PlayerStandingModel> favorites = const [],
  List<Override> overrides = const [],
  Set<String>? serverLive,
  bool serverAnswered = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final created = <_FakeFavoritesGames>[];
  final polls = <FakeLiveGameIds>[];
  final container = ProviderContainer(
    overrides: [
      ..._serverLive(
        polls,
        games,
        serverLive: serverLive,
        answered: serverAnswered,
      ),
      discoveryDotsSourceProvider.overrideWithValue(_NoDiscoveryDots()),
      favoritePlayersNotifierProvider.overrideWith(
        () => _NoFavoritePlayers(favorites),
      ),
      gamesListViewModeProvider.overrideWithValue(viewMode),
      engineSettingsProviderNew.overrideWith(_NoEngine.new),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) => _NoSpoilers(ref: ref, tourId: tourId),
      ),
      // One reading of the clock: no ticking timer left behind.
      dateTimeProvider.overrideWith((ref) => Stream.value(DateTime.now())),
      favoritesCombinedGamesProvider.overrideWith((ref) {
        final notifier = _FakeFavoritesGames(
          FavoritesCombinedGamesState(hasMore: false, games: games),
        );
        created.add(notifier);
        return notifier;
      }),
      if (anyLive != null)
        favoritesGamesAnyLiveProvider.overrideWith((ref) => anyLive),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  if (liveFirst) {
    container
            .read(
              gameListLiveFirstProvider(
                GameListLiveFirstSurface.favorites,
              ).notifier,
            )
            .state =
        true;
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        navigatorObservers: [routeObserver],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return FavoritesTabScreen(initialMode: initialMode);
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(container, created, polls);
}

/// Records filters and searches instead of querying Supabase, and answers a
/// search the way the real notifier does: the list on screen stays until the
/// hits land ([nextSearch], at once by default), and closing the search puts
/// the plain list back as it was.
class _FakeFavoritesGames extends StateNotifier<FavoritesCombinedGamesState>
    implements FavoritesCombinedGamesNotifier {
  _FakeFavoritesGames(super.state);

  final List<GameFilter> applied = [];
  final List<String> searches = [];
  int clears = 0;

  /// The answer to the next search; null answers at once with no games.
  Completer<List<GamesTourModel>>? nextSearch;

  FavoritesCombinedGamesState? _beforeSearch;
  String _query = '';

  @override
  Future<void> applyFilter(GameFilter newFilter) async {
    applied.add(newFilter);
    state = state.copyWith(filter: newFilter);
  }

  @override
  Future<void> searchGames(String query) async {
    final trimmed = query.trim();
    searches.add(trimmed);
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

  @override
  Future<void> clearSearch() async {
    if (_query.isEmpty && !state.isSearching) return;
    clears++;
    _query = '';
    final before = _beforeSearch;
    _beforeSearch = null;
    state = before ?? state.copyWith(searchQuery: '', isLoading: false);
  }

  @override
  Future<void> refreshGames() async {}

  @override
  Future<void> loadMoreGames() async {}

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

class _NoFavoritePlayers extends FavoritePlayersNotifier {
  _NoFavoritePlayers([this.players = const []]);

  final List<PlayerStandingModel> players;

  @override
  Future<FavoritePlayersState> build() async =>
      FavoritePlayersState(players: players);
}

/// The world ranking with no Supabase: it records the searches the page
/// sends it, and answers [searchQuery] with no player.
class _FakeWorldPlayers extends StateNotifier<WorldPlayersSearchState>
    implements WorldPlayersSearchNotifier {
  _FakeWorldPlayers(List<PlayerStandingModel> players)
    : super(WorldPlayersSearchState(players: players, hasMore: false));

  final List<PlayerStandingModel> all = [];
  final List<String> searches = [];

  @override
  Future<void> search(String query) async {
    final trimmed = query.trim();
    searches.add(trimmed);
    state = WorldPlayersSearchState(
      players: trimmed.isEmpty ? all : const [],
      hasMore: false,
      searchQuery: trimmed,
    );
  }

  @override
  Future<void> clearSearch() => search('');

  @override
  Future<void> loadMore() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoFollowedPlayers extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const [];
}

PlayerStandingModel _standing(String name, int fideId, int rating) =>
    PlayerStandingModel(
      countryCode: 'NO',
      title: 'GM',
      name: name,
      score: rating,
      scoreChange: 0,
      matchScore: null,
      fideId: fideId,
    );

class _NoDiscoveryDots implements DiscoveryDotsSource {
  @override
  Future<String> initialize() async => '';

  @override
  Future<String> fetch() async => '';

  @override
  Stream<String> get updates => const Stream<String>.empty();
}

GamesTourModel _game(
  String id, {
  required GameStatus status,
  DateTime? gameDay,
  DateTime? lastMoveTime,
}) {
  return GamesTourModel(
    gameId: id,
    whitePlayer: _player('White'),
    blackPlayer: _player('Black'),
    whiteTimeDisplay: '10:00',
    blackTimeDisplay: '10:00',
    whiteClockCentiseconds: 60000,
    blackClockCentiseconds: 60000,
    whiteClockSeconds: 600,
    blackClockSeconds: 600,
    gameStatus: status,
    roundId: 'round-1',
    tourId: 'tour-1',
    gameDay: gameDay,
    lastMoveTime: lastMoveTime,
    lastMove: lastMoveTime == null ? null : 'e4',
  );
}

PlayerCard _player(String name) {
  return PlayerCard(
    name: name,
    federation: 'USA',
    title: '',
    rating: 2500,
    countryCode: 'USA',
    team: null,
  );
}
