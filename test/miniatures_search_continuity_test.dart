import 'dart:async';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart'
    show playerPhotoProvider;
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_games_tab.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Miniatures' search is the Games tab, narrowed: the same rows stay on
/// screen while a search is read, nothing is remounted, and the search row
/// is X's (the field from the gutter, the tab's Filters, Cancel last), with
/// the page's chevron back where it was once Cancel closes it.

GamebaseMiniature _miniature(String id, String white, {int day = 28}) =>
    GamebaseMiniature(
      gameId: id,
      plyCount: 30,
      finalMoveNumber: 15,
      result: 'W',
      timeControl: 'CLASSICAL',
      isOnline: false,
      date: DateTime.utc(2026, 10, day),
      event: 'Club Open',
      eco: 'B90',
      whiteName: white,
      blackName: 'Opponent, $id',
      whiteElo: 2600,
      blackElo: 2500,
    );

/// Every game at once for the full list; a search waits for [hits].
class _Repo extends GamebaseRepository {
  _Repo() : super(Dio(), apiKey: 'test');

  final searches = <String?>[];
  Completer<List<GamebaseMiniature>>? hits;

  static final all = [
    _miniature('a', 'Carlsen, Magnus'),
    _miniature('b', 'Caruana, Fabiano'),
    _miniature('c', 'Nakamura, Hikaru', day: 27),
  ];

  @override
  Future<GamebaseMiniaturesPage> getMiniatures({
    MiniatureGamesFilter filter = MiniatureGamesFilter.defaultFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    searches.add(filter.search);
    final items = filter.search == null
        ? all
        : await (hits = Completer<List<GamebaseMiniature>>()).future;
    return GamebaseMiniaturesPage(
      items: items,
      total: items.length,
      limit: limit,
      offset: offset,
    );
  }
}

class _IdlePlayers extends StateNotifier<MiniaturePlayersState>
    implements MiniaturePlayersNotifier {
  _IdlePlayers() : super(const MiniaturePlayersState(hasMore: false));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _EngineSettings extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoSpoilers extends EventNoSpoilersController {
  _NoSpoilers({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

/// Frames enough for the search's spring to land. The progress line runs
/// for as long as a read is out, so never pumpAndSettle here.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder get _cards => find.byType(GameCardWrapperWidget);

Finder get _cancel => find.byKey(const ValueKey('miniatures_search_close'));

Finder _inSearch(Finder finder) =>
    find.descendant(of: find.byType(SearchModeHeader), matching: finder);

/// The open search row, as X sets it: no chevron, the field from the
/// gutter, the tab's Filters after it, and Cancel last, its word ending on
/// the gutter, all on the field's line.
void _expectSearchRow(WidgetTester tester) {
  final gutter = SearchHeaderMetrics.gutter;
  expect(_inSearch(find.byType(PageBackButton)), findsNothing);
  expect(
    _inSearch(find.byIcon(Icons.arrow_back_ios_new_outlined)),
    findsNothing,
  );
  expect(_inSearch(_cancel), findsOneWidget);
  final field = tester.getRect(_inSearch(find.byType(SearchFieldFill)));
  final filters = tester.getRect(
    _inSearch(find.byKey(const ValueKey('miniatures_games_filters'))),
  );
  final cancel = tester.getRect(_cancel);
  final word = tester.getRect(
    find.descendant(of: _cancel, matching: find.text('Cancel')),
  );
  expect(field.left, closeTo(gutter, 0.01));
  expect(field.right, lessThanOrEqualTo(filters.left));
  expect(filters.right, closeTo(cancel.left, 0.01));
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  expect(word.right, closeTo(width - gutter, 0.01));
  expect(filters.center.dy, closeTo(field.center.dy, 0.01));
  expect(word.center.dy, closeTo(field.center.dy, 0.01));
}

/// The Miniatures screen over [repo], on the Games tab.
Future<ProviderContainer> _pump(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      gamebaseRepositoryProvider.overrideWithValue(repo),
      gamesListViewModeProvider.overrideWithValue(GamesListViewMode.gamesCard),
      miniaturePlayersPaginatedProvider.overrideWith((ref) => _IdlePlayers()),
      spaceShortcutExistsProvider.overrideWith((ref, key) => false),
      boardSettingsProviderNew.overrideWith(_BoardSettings.new),
      engineSettingsProviderNew.overrideWith(_EngineSettings.new),
      playerPhotoProvider.overrideWith((ref, fideId) async => null),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) => _NoSpoilers(ref: ref, tourId: tourId),
      ),
      gamebaseGameEventTitleProvider.overrideWith((ref, id) => null),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const MiniaturesScreen();
          },
        ),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('searching keeps the Games list on screen, reads quietly, and '
      'gives the list back as it was', (tester) async {
    final repo = _Repo();
    final container = await _pump(tester, repo);
    await _frames(tester);
    expect(_cards, findsNWidgets(3));
    final list = tester.state(find.byType(MiniaturesGamesTab));
    final back = tester.getCenter(find.byTooltip('Back'));
    // The Filters end the header in both states, counted the one way.
    expect(find.byTooltip('Filter games'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('miniatures_search_fab')));
    await _frames(tester);
    final field = find.byKey(const ValueKey('miniatures_games_search'));
    expect(field, findsOneWidget);
    // No chevron in the search row: Cancel, its last control, is the way
    // out, and the page's chevron takes no taps while it is open.
    _expectSearchRow(tester);
    expect(find.byTooltip('Back').hitTestable(), findsNothing);
    // Opening changed nothing under the header.
    expect(_cards, findsNWidgets(3));

    await tester.enterText(field, 'carlsen');
    await tester.pump(const Duration(milliseconds: 400));
    await _frames(tester);
    expect(repo.searches.last, 'carlsen');
    // While the search is read the rows on screen stay, under a quiet
    // line: no skeleton in their place.
    expect(_cards, findsNWidgets(3));
    expect(find.byType(SkeletonWidget), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    repo.hits!.complete([_Repo.all.first]);
    await _frames(tester);
    expect(_cards, findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.state(find.byType(MiniaturesGamesTab)), same(list));

    // Closing gives the full list back, the same list, with no skeleton.
    await tester.tap(_cancel);
    await tester.pump();
    expect(find.byType(SkeletonWidget), findsNothing);
    await _frames(tester);
    expect(field, findsNothing);
    expect(_cards, findsNWidgets(3));
    expect(tester.state(find.byType(MiniaturesGamesTab)), same(list));
    expect(tester.getCenter(find.byTooltip('Back')), back);
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    container.dispose();
  });

  testWidgets('a search that finds nothing says so where the first row '
      'was, and Clear search empties the field and gives every game back', (
    tester,
  ) async {
    final repo = _Repo();
    final container = await _pump(tester, repo);
    await _frames(tester);
    expect(_cards, findsNWidgets(3));

    await tester.tap(find.byKey(const ValueKey('miniatures_search_fab')));
    await _frames(tester);
    final field = find.byKey(const ValueKey('miniatures_games_search'));
    await tester.enterText(field, 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await _frames(tester);
    repo.hits!.complete(const []);
    await _frames(tester);

    expect(_cards, findsNothing);
    expect(find.text('No matches for "zzz"'), findsOneWidget);
    expect(find.text('No miniatures found'), findsNothing);
    final clear = find.byKey(const ValueKey('search_no_matches_clear'));
    expect(find.text('Clear search'), findsOneWidget);

    await tester.tap(clear);
    await _frames(tester);
    // Still searching, with an empty field over every game.
    expect(field, findsOneWidget);
    expect(
      find.descendant(of: field, matching: find.text('zzz')),
      findsNothing,
    );
    expect(container.read(miniaturesFilterProvider).search, isNull);
    expect(_cards, findsNWidgets(3));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    container.dispose();
  });
}
