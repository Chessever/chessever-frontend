import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_game.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'dart:async';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart'
    show playerPhotoProvider;
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_games_tab.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_mode_provider.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The end of both Miniatures lists. The next page is asked for whenever
/// the end comes in reach, scrolled or not (the header folding away grows
/// the list, a page that lands short leaves the end in view), and the slot
/// under the rows keeps one height whatever it holds (room while more can
/// come, the spinner, the end), so the list's end never moves at the very
/// point a page is asked for.

GamebaseMiniature _miniature(String id) => GamebaseMiniature(
  gameId: id,
  plyCount: 30,
  finalMoveNumber: 15,
  result: 'W',
  timeControl: 'CLASSICAL',
  isOnline: false,
  date: DateTime.utc(2026, 10, 28),
  event: 'Club Open',
  eco: 'B90',
  whiteName: 'White, $id',
  blackName: 'Black, $id',
  whiteElo: 2600,
  blackElo: 2500,
);

/// Fifteen miniatures in all: twelve on the first page, which fills the
/// screen, and three on the last. With [hold] each page waits in [pages]
/// (keyed by its offset) until the test answers it.
class _Repo extends GamebaseRepository {
  _Repo({this.hold = false}) : super(Dio(), apiKey: 'test');

  final bool hold;
  final offsets = <int>[];
  final pages = <int, Completer<List<GamebaseMiniature>>>{};

  static List<GamebaseMiniature> page(int offset) => [
    for (var i = offset; i < (offset == 0 ? 12 : 15); i++) _miniature('m$i'),
  ];

  @override
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async => null;

  @override
  Future<GamebaseMiniaturesPage> getMiniatures({
    MiniatureGamesFilter filter = MiniatureGamesFilter.defaultFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    offsets.add(offset);
    final items = hold
        ? await (pages[offset] = Completer<List<GamebaseMiniature>>()).future
        : page(offset);
    return GamebaseMiniaturesPage(
      items: items,
      total: 15,
      limit: limit,
      offset: offset,
    );
  }
}

PlayerStandingModel _player(int i) => PlayerStandingModel(
  countryCode: 'NOR',
  title: 'GM',
  name: 'Player $i',
  score: 2800 - i,
  scoreChange: 0,
  matchScore: null,
);

/// The Players ranking, three rows in and more to come. A page asked for
/// stays out until [land].
class _Players extends StateNotifier<MiniaturePlayersState>
    implements MiniaturePlayersNotifier {
  _Players()
    : super(
        MiniaturePlayersState(items: [for (var i = 1; i <= 3; i++) _player(i)]),
      );

  /// The offsets asked for, in order.
  final asked = <int>[];

  @override
  Future<void> loadNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    asked.add(state.items.length);
    state = state.copyWith(isLoading: true);
  }

  /// The last page lands.
  void land() => state = state.copyWith(
    items: [...state.items, for (var i = 4; i <= 6; i++) _player(i)],
    isLoading: false,
    hasMore: false,
  );

  @override
  Future<void> refresh() async {}

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

/// The Miniatures screen over [repo], on [mode].
Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Repo repo, {
  MiniaturesScreenMode mode = MiniaturesScreenMode.games,
  _Players? players,
  GamesListViewMode viewMode = GamesListViewMode.gamesCard,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      gamebaseRepositoryProvider.overrideWithValue(repo),
      selectedMiniaturesModeProvider.overrideWith((ref) => mode),
      gamesListViewModeProvider.overrideWithValue(viewMode),
      premiumAccessProvider.overrideWithValue(false),
      gameCardEvalWithStockfishFallbackProvider.overrideWith(
        (_, fen) async =>
            CloudEval(fen: fen, knodes: 0, depth: 0, pvs: const []),
      ),
      gameCardEvalCacheOnlyProvider.overrideWith(
        (_, fen) async =>
            CloudEval(fen: fen, knodes: 0, depth: 0, pvs: const []),
      ),
      miniaturePlayersPaginatedProvider.overrideWith(
        (ref) => players ?? _Players(),
      ),
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
        routes: {
          '/scorecard_screen': (_) =>
              const Scaffold(body: Text('Scorecard destination')),
        },
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

/// What the end slot [slot] held on the last frame, and how tall it was.
/// The spinner reads as loading, [endLabel] as the end, nothing as room.
({String kind, double height})? _readSlot(
  WidgetTester tester,
  Finder slot,
  String endLabel,
) {
  if (slot.evaluate().isEmpty) return null;
  bool holds(Finder finder) => find
      .descendant(of: slot, matching: finder, skipOffstage: false)
      .evaluate()
      .isNotEmpty;
  final kind =
      holds(find.byType(CircularProgressIndicator, skipOffstage: false))
      ? 'loading'
      : holds(find.text(endLabel, skipOffstage: false))
      ? 'end'
      : 'room';
  return (kind: kind, height: tester.getSize(slot).height);
}

Future<void> _dispose(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
  container.dispose();
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

  testWidgets('Miniatures grid player name uses the game paywall', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      _Repo(),
      viewMode: GamesListViewMode.chessBoardGrid,
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final card = find.byType(GridGameCardWrapperWidget).hitTestable().first;
    final name = find.descendant(
      of: card,
      matching: find.textContaining('White', findRichText: true),
    );
    expect(name, findsOneWidget);
    await tester.tap(name);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Scorecard destination'), findsNothing);
    final prompt = find.text('Sign in to get Premium');
    expect(prompt, findsOneWidget);
    Navigator.of(tester.element(prompt)).pop();
    await _dispose(tester, container);
  });
  testWidgets('Games: the header folding away with no scroll brings the '
      'end in reach and asks for the next page, and the end slot keeps one '
      'height from room to the spinner to the end', (tester) async {
    final repo = _Repo(hold: true);
    final container = await _pump(tester, repo);
    await tester.pump(const Duration(milliseconds: 50));
    repo.pages[0]!.complete(_Repo.page(0));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(repo.offsets, [0]);

    // Built under the fold as well as on screen: the list's cache keeps it.
    final slot = find.byKey(
      const ValueKey('miniatures_games_list_end'),
      skipOffstage: false,
    );
    final seen = <({String kind, double height})>[];
    Future<void> frames() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final read = _readSlot(tester, slot, 'No more miniatures');
        if (read != null) seen.add(read);
      }
    }

    // Short of the point the next page is asked for, the header still
    // over the list.
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(MiniaturesGamesTab),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    position.jumpTo(position.maxScrollExtent - 250);
    await frames();
    final chrome = tester
        .widget<CollapsingChrome>(find.byType(CollapsingChrome))
        .controller;
    expect(chrome.value, 1);
    expect(repo.offsets, [0]);
    expect(seen.map((r) => r.kind).toSet(), {'room'});

    // The header folds away and nothing scrolls: the list grows by what it
    // gave up, which brings the end in reach. Only the list's own measure
    // can tell.
    final pixels = position.pixels;
    chrome.hide();
    await frames();
    expect(chrome.value, 0);
    expect(position.pixels, pixels);
    expect(repo.offsets, [0, 12]);

    repo.pages[12]!.complete(_Repo.page(12));
    await frames();
    expect(repo.offsets, [0, 12]);
    expect(
      find.text('No more miniatures', skipOffstage: false),
      findsOneWidget,
    );

    expect(
      seen.map((r) => r.kind).toSet(),
      containsAll(<String>['room', 'loading', 'end']),
    );
    expect(
      seen.map((r) => r.height).toSet(),
      hasLength(1),
      reason: 'the slot is one height whatever it holds: $seen',
    );
    expect(tester.takeException(), isNull);
    await _dispose(tester, container);
  });

  testWidgets('Players: a first page that ends on screen asks for the next '
      'one with no scroll, and the end slot keeps one height from room to '
      'the spinner to the end', (tester) async {
    final players = _Players();
    final container = await _pump(
      tester,
      _Repo(),
      mode: MiniaturesScreenMode.players,
      players: players,
    );

    final slot = find.byKey(const ValueKey('miniatures_players_list_end'));
    final seen = <({String kind, double height})>[];
    Future<void> frames() async {
      for (var i = 0; i < 6; i++) {
        final read = _readSlot(tester, slot, 'No more players');
        if (read != null) seen.add(read);
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await frames();
    // Three rows end well inside the screen and nothing scrolled: the
    // list's own measure asked for the rest.
    expect(players.asked, [3]);
    expect(find.text('Loading more…'), findsOneWidget);

    players.land();
    await frames();
    expect(players.asked, [3]);
    expect(find.text('No more players'), findsOneWidget);

    expect(
      seen.map((r) => r.kind).toSet(),
      containsAll(<String>['room', 'loading', 'end']),
    );
    expect(
      seen.map((r) => r.height).toSet(),
      hasLength(1),
      reason: 'the slot is one height whatever it holds: $seen',
    );
    expect(tester.takeException(), isNull);
    await _dispose(tester, container);
  });
}
