// A mini board card's board flies into the board screen's main board.
//
// Pins: every tap flies under its own tag, so one game on several cards of a
// route never trips Heroine's duplicate-tag assertion; the flight runs only
// when the board screen opens on the card's position the card's way up; the
// way back flies nothing and gives the card its board back; and, end to end
// through navigateToChessBoard, a live game lands on the real board screen
// while a finished one (which opens on its first move) does not fly.
import 'dart:async';

import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/board_engine_lines_visibility_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/gamebase_overlay_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/board_hero.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/contextual_swipe_coaching.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_page_transitions.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heroine/heroine.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/board_feature_teaching_store.dart';

/// After 1. e4 e5.
const _liveFen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';
const _startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

final ThemeData _theme = ThemeData.dark().copyWith(
  extensions: const [AppColors.dark],
  // The app's own page transitions: the flight has to work with them.
  pageTransitionsTheme: kAppPageTransitionsTheme,
);

PlayerCard _player(String name) => PlayerCard(
  name: name,
  federation: '',
  title: '',
  rating: 2700,
  countryCode: '',
  team: null,
);

GamesTourModel _liveGame([String id = 'live-1']) => GamesTourModel(
  gameId: id,
  source: GameSource.supabase,
  whitePlayer: _player('White'),
  blackPlayer: _player('Black'),
  whiteTimeDisplay: '90:00',
  blackTimeDisplay: '90:00',
  whiteClockCentiseconds: 540000,
  blackClockCentiseconds: 540000,
  gameStatus: GameStatus.ongoing,
  roundId: 'round-1',
  tourId: 'tour-1',
  fen: _liveFen,
  lastMove: 'e7e5',
);

// ---------------------------------------------------------------------------
// Light harness: real cards, a stand-in board route.
// ---------------------------------------------------------------------------

class _FakeEngineSettings extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async =>
      const EngineSettings(showEngineAnalysis: false, showEngineGauge: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeBoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async {
    const settings = BoardSettingsNew();
    state = const AsyncValue.data(settings);
    return settings;
  }
}

class _FakeEventNoSpoilersController extends EventNoSpoilersController {
  _FakeEventNoSpoilersController({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

const _standInBoardKey = ValueKey<String>('stand-in-board');

/// What the board open helper does with a tap: claim the tap's ticket, hand
/// it to the board route, and the board route lands it on its board, which
/// shows [boardFen] with [flipped] orientation.
void _openStandInBoard(
  NavigatorState navigator, {
  required String gameId,
  required String boardFen,
  bool flipped = false,
}) {
  final ticket = BoardHeroTicket.claim(
    gameId: gameId,
    boardOrientation: flipped ? Side.black : Side.white,
  );
  final route = MaterialPageRoute<void>(
    builder: (_) {
      final Widget page = Scaffold(
        body: Padding(
          padding: const EdgeInsets.only(top: 140),
          child: Align(
            alignment: Alignment.topCenter,
            child: BoardHeroDestination(
              gameId: gameId,
              pageIndex: 0,
              placement: () => boardHeroPlacement(boardFen)!,
              flipped: flipped,
              child: const SizedBox.square(
                key: _standInBoardKey,
                dimension: 320,
                child: ColoredBox(color: Color(0xFF2F4F3A)),
              ),
            ),
          ),
        ),
      );
      return ticket == null
          ? page
          : BoardHeroScope(ticket: ticket, pageIndex: 0, child: page);
    },
  );
  navigator.push(route);
  ticket?.followTransition(route);
}

/// Two grid cards (both may hold the same game). A tap opens the stand-in
/// board after an await, the way the real open helper waits on its access
/// gate before it pushes.
Future<GlobalKey<NavigatorState>> _pumpCards(
  WidgetTester tester, {
  required List<GamesTourModel> games,
  List<Side?> bottomSides = const [null, null],
  String boardFen = _liveFen,
  bool flipped = false,
  bool opensBoard = true,
}) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        engineSettingsProviderNew.overrideWith(_FakeEngineSettings.new),
        boardSettingsProviderNew.overrideWith(_FakeBoardSettings.new),
        eventNoSpoilersProvider.overrideWith(
          (ref, tourId) =>
              _FakeEventNoSpoilersController(ref: ref, tourId: tourId),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [HeroineController()],
        theme: _theme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < games.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: SizedBox(
                          width: 180,
                          child: GridChessBoardFromFENNew(
                            gamesTourModel: games[i],
                            fixedBottomSide: bottomSides[i],
                            pinnedIds: const [],
                            onPinToggle: (_) {},
                            allowStockfishFallback: false,
                            onChanged: () async {
                              await Future<void>.delayed(Duration.zero);
                              if (!opensBoard) return;
                              _openStandInBoard(
                                navigator.currentState!,
                                gameId: games[i].gameId,
                                boardFen: boardFen,
                                flipped: flipped,
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return navigator;
}

/// The tag card [index]'s board flies under, or null while it carries no
/// heroine (it was never opened, or its open could not land it).
Object? _cardTag(WidgetTester tester, int index) {
  final heroines = find.descendant(
    of: find.byType(GridChessBoardFromFENNew, skipOffstage: false).at(index),
    matching: find.byType(Heroine, skipOffstage: false),
  );
  final found = heroines.evaluate().toList();
  expect(found.length, lessThanOrEqualTo(1));
  return found.isEmpty ? null : (found.single.widget as Heroine).tag;
}

Finder get _destinationHeroine => find.descendant(
  of: find.byType(BoardHeroDestination, skipOffstage: false),
  matching: find.byType(Heroine, skipOffstage: false),
);

/// Pumps [frames] frames of [step], recording whether a shuttle flew.
Future<bool> _pumpWatchingForShuttle(
  WidgetTester tester, {
  int frames = 40,
  Duration step = const Duration(milliseconds: 16),
}) async {
  var flew = false;
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
    if (find.byType(BoardHeroShuttle).evaluate().isNotEmpty) flew = true;
  }
  return flew;
}

// ---------------------------------------------------------------------------
// Real board screen harness (same fakes as the scoped navigation tests).
// ---------------------------------------------------------------------------

Games _rawGame({required String id, required String status}) {
  final live = status == '*';
  return Games(
    id: id,
    roundId: 'round-1',
    roundSlug: 'round-1',
    tourId: 'hero-tour',
    tourSlug: 'hero-tour',
    players: [
      Player(
        name: 'White $id',
        title: 'GM',
        rating: 2700,
        fideId: 1,
        fed: 'USA',
        clock: 0,
        team: '',
      ),
      Player(
        name: 'Black $id',
        title: 'GM',
        rating: 2700,
        fideId: 2,
        fed: 'USA',
        clock: 0,
        team: '',
      ),
    ],
    boardNr: 1,
    status: status,
    fen: _liveFen,
    lastMove: 'e7e5',
    pgn:
        '''
[Event "Hero"]
[White "White $id"]
[Black "Black $id"]
[Result "${live ? '*' : status}"]

1. e4 e5 ${live ? '*' : status}
''',
  );
}

ProviderContainer _boardContainer(List<Games> raw) {
  return ProviderContainer(
    overrides: [
      boardFeatureTeachingTrackerProvider.overrideWith(
        (_) => BoardFeatureTeachingTracker(QuietBoardTeachingStore()),
      ),
      effectiveCountryProvider.overrideWithValue(const AsyncValue.loading()),
      gamesLocalStorage.overrideWith(
        (ref) => _CachedGames(ref, {'hero-tour': raw}),
      ),
      gameRepositoryProvider.overrideWithValue(
        _ImmediateGameRepository({for (final game in raw) game.id: game}),
      ),
      gamebaseRepositoryProvider.overrideWithValue(_FakeGamebaseRepository()),
      gameStreamRepositoryProvider.overrideWithValue(
        _FakeGameStreamRepository(),
      ),
      localEvalCacheProvider.overrideWith(_FakeLocalEvalCache.new),
      engineSettingsProviderNew.overrideWith(_FakeEngineSettings.new),
      boardEngineLinesVisibleProvider.overrideWith(_VisibleBoardLines.new),
      gamebaseOverlayEnabledProvider.overrideWith(
        _FakeGamebaseOverlayNotifier.new,
      ),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) =>
            _FakeEventNoSpoilersController(ref: ref, tourId: tourId),
      ),
      chessBoardPersistenceEnabledProvider.overrideWithValue(false),
    ],
  );
}

/// A grid card that opens its game through the real open helper.
Future<void> _pumpCardOpeningRealBoard(
  WidgetTester tester,
  ProviderContainer container,
  GamesTourModel game,
) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorObservers: [
          routeObserver,
          contextualSwipeCoaching,
          HeroineController(),
        ],
        theme: _theme,
        home: Consumer(
          builder: (context, ref, _) {
            ResponsiveHelper.init(context);
            final navigation = ref.watch(gameCardWrapperProvider);
            return Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 180,
                    child: GridChessBoardFromFENNew(
                      gamesTourModel: game,
                      pinnedIds: const [],
                      onPinToggle: (_) {},
                      allowStockfishFallback: false,
                      onChanged: () => navigation.navigateToChessBoard(
                        context: context,
                        orderedGames: [game],
                        gameIndex: 0,
                        onReturnFromChessboard: null,
                        viewSource: ChessboardView.tour,
                        listPolicy: BoardNavigationListPolicy.preserve,
                        disableGamebaseOverlayByDefault: true,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _ImmediateGameRepository extends GameRepository {
  _ImmediateGameRepository(this.games);

  final Map<String, Games> games;

  @override
  Future<Games> getGameWithPGN(String gameId) async => games[gameId]!;

  @override
  Future<String?> getGamePgn(String gameId) async => games[gameId]?.pgn;
}

class _CachedGames extends GamesLocalStorage {
  _CachedGames(super.ref, this.byTour);

  final Map<String, List<Games>> byTour;

  @override
  Future<List<Games>> getCachedGames(String tourId) async =>
      byTour[tourId] ?? const [];

  @override
  Future<List<Games>> fetchAndSaveGames(
    String tourId, {
    bool forceRefresh = false,
    String? priorityRoundId,
    void Function(List<Games>)? onPriorityRound,
    Future<void> Function()? afterPriorityRound,
    bool rethrowErrors = false,
  }) async => byTour[tourId] ?? const [];
}

class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository()
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  @override
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async => null;

  @override
  Future<CloudEval?> getEvalByFen(String fen) async => null;

  @override
  Future<GamebaseResponse> getMoveAggregates({
    required String fen,
    List<String> moves = const [],
    String? playerId,
    TimeControl? timeControl,
    int? minRating,
    int? maxRating,
    String? color,
    String? result,
    int? yearFrom,
    int? yearTo,
    bool? isOnline,
  }) async => const GamebaseResponse(
    status: 'success',
    data: GamebaseData(moves: []),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGameStreamRepository extends GameStreamRepository {
  @override
  Stream<Map<String, dynamic>?> subscribeToGameUpdates(String gameId) =>
      const Stream.empty();

  @override
  Stream<String?> subscribeToPgn(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToLastMove(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToFen(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToStatus(String gameId) => const Stream.empty();
}

class _VisibleBoardLines extends BoardEngineLinesVisibleNotifier {
  @override
  Future<bool> build() async => true;
}

class _FakeGamebaseOverlayNotifier extends GamebaseOverlayEnabledNotifier {
  @override
  Future<bool> build() async => false;

  @override
  Future<void> setEnabled(bool enabled) async {
    state = AsyncValue.data(enabled);
  }

  @override
  Future<void> toggle() => setEnabled(!(state.valueOrNull ?? false));
}

class _FakeLocalEvalCache extends LocalEvalCache {
  _FakeLocalEvalCache(super.ref);

  @override
  Future<CloudEval?> fetch(
    String fen, {
    int? multiPV,
    int minDepth = 0,
  }) async => null;

  @override
  Future<void> save(String fen, CloudEval eval, {int? multiPV}) async {}
}

void main() {
  group('tickets', () {
    test('only the tap chain that issued one can claim it, once', () async {
      final slot = BoardHeroSlot();
      addTearDown(slot.dispose);
      final ticket = slot.issue(
        gameId: 'g1',
        fen: _liveFen,
        orientation: Side.white,
        lastMove: null,
      )!;

      expect(
        BoardHeroTicket.claim(gameId: 'g1', boardOrientation: Side.white),
        isNull,
        reason: 'outside the tap chain',
      );

      final claimed = Completer<List<BoardHeroTicket?>>();
      openWithBoardHero(ticket, () async {
        // Across an await, as the open helper's access gate does.
        await Future<void>.delayed(Duration.zero);
        claimed.complete([
          BoardHeroTicket.claim(
            gameId: 'another-game',
            boardOrientation: Side.white,
          ),
          BoardHeroTicket.claim(gameId: 'g1', boardOrientation: Side.black),
          BoardHeroTicket.claim(gameId: 'g1', boardOrientation: Side.white),
          BoardHeroTicket.claim(gameId: 'g1', boardOrientation: Side.white),
        ]);
      });
      expect(slot.armed, isNull);
      final results = await claimed.future;
      expect(results[0], isNull, reason: 'another game never takes it');
      expect(results[1], isNull, reason: 'a board turned over never takes it');
      expect(results[2], same(ticket));
      expect(results[3], isNull, reason: 'a ticket opens one board');
      expect(slot.armed, same(ticket), reason: 'claiming arms the card');
    });

    test('a card showing no readable position issues nothing', () {
      final slot = BoardHeroSlot();
      addTearDown(slot.dispose);
      expect(
        slot.issue(
          gameId: 'g1',
          fen: null,
          orientation: Side.white,
          lastMove: null,
        ),
        isNull,
      );
      expect(
        slot.issue(
          gameId: 'g1',
          fen: 'not a fen',
          orientation: Side.white,
          lastMove: null,
        ),
        isNull,
      );
    });

    test('positions compare on piece placement only', () {
      final slot = BoardHeroSlot();
      addTearDown(slot.dispose);
      final ticket = slot.issue(
        gameId: 'g1',
        fen: _liveFen,
        orientation: Side.white,
        lastMove: null,
      )!;
      final sameBoardOtherClock = _liveFen.replaceFirst(' 0 2', ' 3 9');
      expect(
        ticket.landsOn(
          placement: boardHeroPlacement(sameBoardOtherClock)!,
          orientation: Side.white,
        ),
        isTrue,
      );
      expect(
        ticket.landsOn(
          placement: boardHeroPlacement(_liveFen)!,
          orientation: Side.black,
        ),
        isFalse,
      );
      expect(
        ticket.landsOn(
          placement: boardHeroPlacement(_startFen)!,
          orientation: Side.white,
        ),
        isFalse,
      );
    });
  });

  group('cards', () {
    testWidgets(
      'one game on two cards: the tapped card flies under its own tag',
      (tester) async {
        final game = _liveGame();
        final navigator = await _pumpCards(tester, games: [game, game]);

        expect(_cardTag(tester, 0), isNull, reason: 'idle cards carry none');
        expect(_cardTag(tester, 1), isNull);

        await tester.tap(find.byType(GameCardChessboard).at(1));
        final flew = await _pumpWatchingForShuttle(tester);
        expect(flew, isTrue, reason: 'the tapped card board flies');
        expect(tester.takeException(), isNull);

        expect(_cardTag(tester, 0), isNull, reason: 'the other card stays');
        final firstTag = _cardTag(tester, 1);
        expect(firstTag, isA<BoardHeroTicket>());
        final landed = tester.widget<Heroine>(_destinationHeroine);
        expect(landed.tag, same(firstTag));
        expect(find.byType(BoardHeroShuttle), findsNothing);
        expect(find.byKey(_standInBoardKey), findsOneWidget);

        // The way back flies nothing and gives the card its board back.
        navigator.currentState!.pop();
        final flewBack = await _pumpWatchingForShuttle(tester);
        expect(flewBack, isFalse);
        expect(tester.takeException(), isNull);
        expect(find.byType(GameCardChessboard), findsNWidgets(2));

        // The other card of the same game: a new tag, still no duplicate.
        await tester.tap(find.byType(GameCardChessboard).at(0));
        final flewAgain = await _pumpWatchingForShuttle(tester);
        expect(flewAgain, isTrue);
        expect(tester.takeException(), isNull);
        final secondTag = _cardTag(tester, 0);
        expect(secondTag, isA<BoardHeroTicket>());
        expect(_cardTag(tester, 1), same(firstTag));
        expect(identical(secondTag, firstTag), isFalse);
        expect(
          tester.widget<Heroine>(_destinationHeroine).tag,
          same(secondTag),
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('a card showing black at the bottom does not fly', (
      tester,
    ) async {
      await _pumpCards(
        tester,
        games: [_liveGame()],
        bottomSides: const [Side.black],
      );

      await tester.tap(find.byType(GameCardChessboard));
      final flew = await _pumpWatchingForShuttle(tester);

      expect(flew, isFalse);
      expect(tester.takeException(), isNull);
      expect(
        _destinationHeroine,
        findsNothing,
        reason: 'the board screen opens white at the bottom',
      );
      expect(_cardTag(tester, 0), isNull, reason: 'the card is left alone');
      expect(find.byKey(_standInBoardKey), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a board that opens on another position does not fly', (
      tester,
    ) async {
      await _pumpCards(tester, games: [_liveGame()], boardFen: _startFen);

      await tester.tap(find.byType(GameCardChessboard));
      final flew = await _pumpWatchingForShuttle(tester);

      expect(flew, isFalse);
      expect(_destinationHeroine, findsNothing);
      expect(tester.takeException(), isNull);

      // Back on the list the card shows its board again.
      Navigator.of(tester.element(find.byKey(_standInBoardKey))).pop();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(GameCardChessboard), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a tap that opens no board leaves the card untouched', (
      tester,
    ) async {
      await _pumpCards(tester, games: [_liveGame()], opensBoard: false);

      await tester.tap(find.byType(GameCardChessboard));
      await tester.pump(const Duration(milliseconds: 100));

      expect(_cardTag(tester, 0), isNull);
      expect(find.byType(GameCardChessboard), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('real board screen', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({
        'swipable_walkthrough_dont_show': true,
        'explorer_panel_walkthrough_dont_show': true,
        'like_walkthrough_dont_show': true,
      });
      await Supabase.initialize(
        url: 'https://placeholder.supabase.co',
        publishableKey: 'placeholder-anon-key',
      );
      GameAnalysisReportStore.debugSetInstance(
        GameAnalysisReportStore.memory(),
      );
    });
    tearDownAll(GameAnalysisReportStore.debugResetInstance);

    Future<bool> openFromCard(WidgetTester tester, Games raw) async {
      final container = _boardContainer([raw]);
      final game = GamesTourModel.fromGame(raw);
      await _pumpCardOpeningRealBoard(tester, container, game);
      await tester.pump();

      await tester.tap(find.byType(GameCardChessboard));
      final flew = await _pumpWatchingForShuttle(tester, frames: 60);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(ChessBoardScreenNew), findsOneWidget);
      expect(find.byType(BoardHeroShuttle), findsNothing);

      final landed = find.descendant(
        of: find.byType(ChessBoardScreenNew),
        matching: _destinationHeroine,
      );
      final carried = landed.evaluate().isNotEmpty;
      if (carried) {
        expect(tester.widget<Heroine>(landed).tag, isA<BoardHeroTicket>());
      }

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump();
      return flew && carried;
    }

    testWidgets('a live game card lands on the board screen board', (
      tester,
    ) async {
      final flew = await openFromCard(
        tester,
        _rawGame(id: 'hero-live', status: '*'),
      );
      expect(flew, isTrue);
    });

    testWidgets(
      'a finished game card does not fly: the board opens on its first move',
      (tester) async {
        final flew = await openFromCard(
          tester,
          _rawGame(id: 'hero-finished', status: '1-0'),
        );
        expect(flew, isFalse);
      },
    );
  });
}
