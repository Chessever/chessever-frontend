import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/for_you/discovery/providers/reports_provider.dart';
import 'package:chessever2/screens/for_you/discovery/reports_screen.dart';
import 'package:chessever2/screens/for_you/discovery/reports_share.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Reports searched in place: the same list under the field, the report
/// types still in reach, folded days opened for the hits and folded again
/// after.

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

class _Reports implements DiscoveryRepository {
  final types = <ReportGameType?>[];

  @override
  Future<AnalyzedGamesPage> fetchAnalyzedGamesPage({
    int pageSize = 30,
    AnalyzedGamesCursor? after,
    DateTime? since,
    DateTime? until,
    ReportGameType? gameType,
  }) async {
    types.add(gameType);
    return AnalyzedGamesPage(items: _page);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected call');
}

const _fen = 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';

GamesTourModel _report(
  String id, {
  required String white,
  required String black,
  required DateTime at,
}) {
  PlayerCard player(String name) => PlayerCard(
    name: name,
    federation: 'NOR',
    title: 'GM',
    rating: 2750,
    countryCode: 'NO',
    team: null,
  );
  return GamesTourModel(
    gameId: id,
    whitePlayer: player(white),
    blackPlayer: player(black),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.whiteWins,
    roundId: 'round-$id',
    tourId: 'tour-1',
    fen: _fen,
    lastMove: 'b8c6',
    lastMoveTime: at,
  );
}

final _page = [
  _report(
    'carlsen',
    white: 'Carlsen, Magnus',
    black: 'Caruana, Fabiano',
    at: DateTime.utc(2026, 10, 29, 12),
  ),
  _report(
    'gukesh',
    white: 'Gukesh, D',
    black: 'Nakamura, Hikaru',
    at: DateTime.utc(2026, 10, 29, 10),
  ),
  _report(
    'firouzja',
    white: 'Firouzja, Alireza',
    black: 'Carlsen, Magnus',
    at: DateTime.utc(2026, 10, 28, 12),
  ),
];

CloudEval _cached(String fen) => CloudEval(
  fen: fen,
  knodes: 0,
  depth: 20,
  pvs: [Pv(moves: 'e2e4', cp: 40)],
  requestedMultiPv: 1,
);

Future<ProviderContainer> _pump(WidgetTester tester, _Reports reports) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      gamesListViewModeProvider.overrideWithValue(GamesListViewMode.gamesCard),
      boardSettingsProviderNew.overrideWith(_BoardSettings.new),
      engineSettingsProviderNew.overrideWith(_EngineSettings.new),
      playerPhotoProvider.overrideWith((ref, fideId) async => null),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) => _NoSpoilers(ref: ref, tourId: tourId),
      ),
      gameCardEvalWithStockfishFallbackProvider.overrideWith(
        (ref, fen) async => _cached(fen),
      ),
      gameCardEvalCacheOnlyProvider.overrideWith(
        (ref, fen) async => _cached(fen),
      ),
      discoveryRepositoryProvider.overrideWithValue(reports),
      premiumAccessProvider.overrideWithValue(true),
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
            return const ReportsScreen();
          },
        ),
      ),
    ),
  );
  await _settle(tester);
  return container;
}

/// Long enough for the search morph to land both ways.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _teardown(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
  container.dispose();
}

final _fab = find.byKey(const ValueKey('event_view_search_fab'));
final _field = find.byKey(const ValueKey('reports_search'));
final _close = find.byKey(const ValueKey('event_view_search_close'));
final _list = find.descendant(
  of: find.byKey(const PageStorageKey('reports_scroll')),
  matching: find.byType(Scrollable),
);

Iterable<String> _shown(WidgetTester tester) => tester
    .widgetList<DiscoveryGameCard>(find.byType(DiscoveryGameCard))
    .map((card) => card.games[card.index].gameId);

void main() {
  testWidgets('the search keeps the same list and the report types in reach '
      'under its field', (tester) async {
    final reports = _Reports();
    final container = await _pump(tester, reports);
    final list = tester.state<ScrollableState>(_list);
    expect(_shown(tester), unorderedEquals(['carlsen', 'gukesh', 'firouzja']));
    final chips = find.byKey(const ValueKey('report_type_all'));
    final chipsTop = tester.getRect(chips).top;

    await tester.tap(_fab);
    await _settle(tester);
    expect(_field, findsOneWidget);
    expect(tester.widget<TextField>(_field).focusNode!.hasFocus, isTrue);
    // The same list, not a new one, and no floating button over it.
    expect(tester.state<ScrollableState>(_list), same(list));
    expect(_fab.hitTestable(), findsNothing);
    expect(chips.hitTestable(), findsOneWidget);
    // The types sit under the field exactly where they sat under the
    // title: nothing under the header moves as the search opens.
    expect(
      tester.getRect(chips).top,
      greaterThan(tester.getRect(_field).bottom),
    );
    expect(tester.getRect(chips).top, closeTo(chipsTop, 0.5));

    await tester.enterText(_field, 'carlsen');
    await _settle(tester);
    expect(_shown(tester), unorderedEquals(['carlsen', 'firouzja']));
    expect(tester.state<ScrollableState>(_list), same(list));

    // Another type, picked without leaving the search: the words stay.
    await tester.tap(
      find.byKey(const ValueKey('report_type_missed_chance')).hitTestable(),
    );
    await _settle(tester);
    expect(
      container.read(reportsGameTypeProvider),
      ReportGameType.missedChance,
    );
    expect(reports.types.last, ReportGameType.missedChance);
    expect(_field, findsOneWidget);
    expect(tester.widget<TextField>(_field).controller!.text, 'carlsen');
    expect(_shown(tester), unorderedEquals(['carlsen', 'firouzja']));

    await tester.tap(_close);
    await _settle(tester);
    expect(_field, findsNothing);
    expect(_fab.hitTestable(), findsOneWidget);
    expect(_shown(tester), unorderedEquals(['carlsen', 'gukesh', 'firouzja']));
    expect(tester.state<ScrollableState>(_list), same(list));
    expect(tester.takeException(), isNull);
    await _teardown(tester, container);
  });

  testWidgets('a day folded before the search opens for its hits and is '
      'folded again after', (tester) async {
    final container = await _pump(tester, _Reports());
    // Fold the older day: its report leaves the list.
    await tester.tap(find.byType(ReportsDateShareHeader).last);
    await _settle(tester);
    expect(_shown(tester), unorderedEquals(['carlsen', 'gukesh']));

    await tester.tap(_fab);
    await _settle(tester);
    await tester.enterText(_field, 'firouzja');
    await _settle(tester);
    expect(_shown(tester), ['firouzja']);
    // Its fold still answers while searching.
    await tester.tap(find.byType(ReportsDateShareHeader));
    await _settle(tester);
    expect(_shown(tester), isEmpty);
    await tester.tap(find.byType(ReportsDateShareHeader));
    await _settle(tester);
    expect(_shown(tester), ['firouzja']);

    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_field, findsNothing);
    expect(find.byType(ReportsScreen), findsOneWidget);
    expect(_shown(tester), unorderedEquals(['carlsen', 'gukesh']));
    expect(tester.takeException(), isNull);
    await _teardown(tester, container);
  });

  testWidgets('the search button counts nothing: Reports has no filters', (
    tester,
  ) async {
    final container = await _pump(tester, _Reports());
    expect(tester.widget<SearchInkFab>(_fab).badgeCount, 0);
    expect(find.byKey(const ValueKey('event_view_filters')), findsNothing);
    expect(tester.takeException(), isNull);
    await _teardown(tester, container);
  });
}
