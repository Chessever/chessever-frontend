import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/gamebase_overlay_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'swipable_walkthrough_dont_show': true,
    });
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      anonKey: 'placeholder-anon-key',
    );
    GameAnalysisReportStore.debugSetInstance(GameAnalysisReportStore.memory());
  });

  tearDownAll(GameAnalysisReportStore.debugResetInstance);

  testWidgets(
    'delayed player-list refresh keeps the swiped game and dropdown in sync',
    (tester) async {
      final tourOne = <Games>[
        _rawGame(
          id: 'tour-1-round-3',
          tourId: 'tour-1',
          round: 'round-3',
          board: 1,
        ),
        _rawGame(
          id: 'opened-game',
          tourId: 'tour-1',
          round: 'round-2',
          board: 1,
        ),
        _rawGame(
          id: 'tour-1-round-1',
          tourId: 'tour-1',
          round: 'round-1',
          board: 1,
        ),
      ];
      final otherTourGame = _rawGame(
        id: 'swiped-game',
        tourId: 'tour-2',
        round: 'round-4',
        board: 2,
      );
      final scopedPlayerGames = <GamesTourModel>[
        GamesTourModel.fromGame(tourOne[1]),
        GamesTourModel.fromGame(otherTourGame),
      ];

      final hydration = _DelayedGameRepository(
        _rawGame(
          id: 'opened-game',
          tourId: 'tour-1',
          round: 'round-2',
          board: 1,
          event: 'Hydrated event row',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          gamesLocalStorage.overrideWith(
            (ref) => _FullCacheGamesLocalStorage(ref, {
              'tour-1': tourOne,
              'tour-2': [otherTourGame],
            }),
          ),
          gameRepositoryProvider.overrideWithValue(hydration),
          gamebaseRepositoryProvider.overrideWithValue(
            _FakeGamebaseRepository(),
          ),
          gameStreamRepositoryProvider.overrideWithValue(
            _FakeGameStreamRepository(),
          ),
          localEvalCacheProvider.overrideWith(_FakeLocalEvalCache.new),
          engineSettingsProviderNew.overrideWith(
            _FakeEngineSettingsNotifier.new,
          ),
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
      addTearDown(container.dispose);

      final launch = container
          .read(gameCardWrapperProvider)
          .debugBeginBoardNavigation(
            orderedGames: scopedPlayerGames,
            gameIndex: 0,
            viewSource: ChessboardView.favScorecard,
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [AppColors.dark],
            ),
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return expandingChessBoardScreenForTesting(
                  initialGames: launch.immediateGames,
                  initialIndex: launch.immediateIndex,
                  expandedNavigation: launch.expanded,
                  viewSource: ChessboardView.favScorecard,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(
        () => hydration.requested.future.timeout(const Duration(seconds: 2)),
      );

      final pages = find.byKey(boardGamesPageViewTestKey);
      expect(pages, findsOneWidget);
      await tester.drag(pages, const Offset(-700, 0));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      PageView pageView = tester.widget<PageView>(pages);
      expect(pageView.controller!.page, 1);
      expect(container.read(currentlyVisiblePageIndexProvider), 1);

      hydration.release.complete();
      await tester.runAsync(
        () => launch.expanded.timeout(const Duration(seconds: 3)),
      );
      await tester.pump();
      await tester.pump();

      final board = tester.widget<ChessBoardScreenNew>(
        find.byType(ChessBoardScreenNew),
      );
      expect(board.games.map((game) => game.gameId), [
        'opened-game',
        'swiped-game',
      ], reason: 'the board must retain the player-scoped swipe collection');
      expect(board.viewSource, ChessboardView.favScorecard);

      pageView = tester.widget<PageView>(pages);
      expect(pageView.controller!.page, 1);
      expect(container.read(currentlyVisiblePageIndexProvider), 1);

      await tester.tap(find.byKey(e2eKey(E2eIds.boardGameSelector)).first);
      await tester.pump(const Duration(milliseconds: 300));

      final dropdown = boardGameDropdownSnapshotForTesting(
        tester.widget(find.byKey(boardGameDropdownContentTestKey)),
      );
      expect(dropdown.gameIds, ['opened-game', 'swiped-game']);
      expect(dropdown.currentIndex, 1);
      expect(dropdown.selectedGameId, 'swiped-game');

      await tester.tap(find.byKey(boardGameDropdownCardTestKey('opened-game')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      pageView = tester.widget<PageView>(pages);
      expect(pageView.controller!.page, 0);
      expect(container.read(currentlyVisiblePageIndexProvider), 0);
      expect(find.byKey(boardGameDropdownContentTestKey), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
    },
  );

  testWidgets(
    'different-tour swipe rejects an expansion that omits the active game',
    (tester) async {
      final openedRaw = _rawGame(
        id: 'opened-tour-a',
        tourId: 'tour-a',
        round: 'round-2',
        board: 1,
      );
      final swipedRaw = _rawGame(
        id: 'swiped-tour-b',
        tourId: 'tour-b',
        round: 'round-1',
        board: 2,
      );
      final expandedOnlyRaw = _rawGame(
        id: 'expanded-tour-a',
        tourId: 'tour-a',
        round: 'round-3',
        board: 3,
      );
      final immediateGames = [
        GamesTourModel.fromGame(openedRaw),
        GamesTourModel.fromGame(swipedRaw),
      ];
      final eventAExpansion = [
        GamesTourModel.fromGame(openedRaw),
        GamesTourModel.fromGame(expandedOnlyRaw),
      ];
      final expansion = Completer<({List<GamesTourModel> games, int index})>();
      final container = _boardTestContainer(
        gamesByTour: const {},
        gameRepository: _ImmediateGameRepository({
          openedRaw.id: openedRaw,
          swipedRaw.id: swipedRaw,
          expandedOnlyRaw.id: expandedOnlyRaw,
        }),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [AppColors.dark],
            ),
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return expandingChessBoardScreenForTesting(
                  initialGames: immediateGames,
                  initialIndex: 0,
                  expandedNavigation: expansion.future,
                  viewSource: ChessboardView.forYou,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final pages = find.byKey(boardGamesPageViewTestKey);
      tester.widget<PageView>(pages).controller!.jumpToPage(1);
      await tester.pump();
      expect(tester.widget<PageView>(pages).controller!.page, 1);
      expect(container.read(currentlyVisiblePageIndexProvider), 1);

      expansion.complete((games: eventAExpansion, index: 0));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final board = tester.widget<ChessBoardScreenNew>(
        find.byType(ChessBoardScreenNew),
      );
      expect(
        board.games.map((game) => game.gameId),
        ['opened-tour-a', 'swiped-tour-b'],
        reason:
            'event A hydration must not delete the event B game the user '
            'already made active',
      );
      expect(tester.widget<PageView>(pages).controller!.page, 1);
      expect(container.read(currentlyVisiblePageIndexProvider), 1);

      final selector = find.byKey(e2eKey(E2eIds.boardGameSelector)).first;
      final selectorTapTarget = find.descendant(
        of: selector,
        matching: find.byType(GestureDetector),
      );
      tester.widget<GestureDetector>(selectorTapTarget.first).onTap!();
      await tester.pump(const Duration(milliseconds: 300));
      final dropdown = boardGameDropdownSnapshotForTesting(
        tester.widget(find.byKey(boardGameDropdownContentTestKey)),
      );
      expect(dropdown.gameIds, ['opened-tour-a', 'swiped-tour-b']);
      expect(dropdown.currentIndex, 1);
      expect(dropdown.selectedGameId, 'swiped-tour-b');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
    },
  );

  testWidgets(
    'nested board navigation restores the caller context when the route exits',
    (tester) async {
      final priorGames = <GamesTourModel>[
        GamesTourModel.fromGame(
          _rawGame(
            id: 'prior-a',
            tourId: 'prior-tour',
            round: 'round-2',
            board: 1,
          ),
        ),
        GamesTourModel.fromGame(
          _rawGame(
            id: 'prior-b',
            tourId: 'prior-tour',
            round: 'round-1',
            board: 2,
          ),
        ),
      ];
      final nestedRaw = <Games>[
        _rawGame(
          id: 'nested-a',
          tourId: 'nested-tour',
          round: 'round-1',
          board: 1,
        ),
        _rawGame(
          id: 'nested-b',
          tourId: 'nested-tour',
          round: 'round-2',
          board: 2,
        ),
      ];
      final nestedGames = nestedRaw.map(GamesTourModel.fromGame).toList();

      final container = ProviderContainer(
        overrides: [
          gamesLocalStorage.overrideWith(
            (ref) =>
                _FullCacheGamesLocalStorage(ref, {'nested-tour': nestedRaw}),
          ),
          gameRepositoryProvider.overrideWithValue(
            _ImmediateGameRepository({
              for (final game in nestedRaw) game.id: game,
            }),
          ),
          gamebaseRepositoryProvider.overrideWithValue(
            _FakeGamebaseRepository(),
          ),
          gameStreamRepositoryProvider.overrideWithValue(
            _FakeGameStreamRepository(),
          ),
          localEvalCacheProvider.overrideWith(_FakeLocalEvalCache.new),
          engineSettingsProviderNew.overrideWith(
            _FakeEngineSettingsNotifier.new,
          ),
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
      addTearDown(container.dispose);

      container.read(chessboardViewFromProviderNew.notifier).state =
          ChessboardView.favorites;
      container.read(chessBoardAllGamesProvider.notifier).state = priorGames;
      container.read(currentlyVisiblePageIndexProvider.notifier).state = 7;
      container.read(shouldStreamProvider.notifier).state = true;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [AppColors.dark],
            ),
            home: _NestedBoardNavigationHost(games: nestedGames),
          ),
        ),
      );

      await tester.tap(find.byKey(_openNestedBoardKey));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(ChessBoardScreenNew), findsOneWidget);
      expect(
        container.read(chessboardViewFromProviderNew),
        ChessboardView.tour,
      );
      expect(
        container.read(chessBoardAllGamesProvider).map((game) => game.gameId),
        ['nested-a', 'nested-b'],
      );
      expect(container.read(currentlyVisiblePageIndexProvider), 0);
      expect(container.read(shouldStreamProvider), isFalse);

      final selector = find.byKey(e2eKey(E2eIds.boardGameSelector)).first;
      final selectorTapTarget = find.descendant(
        of: selector,
        matching: find.byType(GestureDetector),
      );
      tester.widget<GestureDetector>(selectorTapTarget.first).onTap!();
      await tester.pump(const Duration(milliseconds: 300));

      final dropdown = boardGameDropdownSnapshotForTesting(
        tester.widget(find.byKey(boardGameDropdownContentTestKey)),
      );
      expect(dropdown.gameIds, ['nested-a', 'nested-b']);
      expect(dropdown.currentIndex, 0);
      expect(dropdown.selectedGameId, 'nested-a');
      expect(
        container.read(shouldStreamProvider),
        isTrue,
        reason: 'the mounted dropdown temporarily streams its mini-board',
      );

      final boardContext = tester.element(find.byType(ChessBoardScreenNew));
      final boardRoute = ModalRoute.of(boardContext)!;
      expect(boardRoute.isCurrent, isTrue);
      expect(boardRoute.willHandlePopInternally, isFalse);
      expect(boardRoute.popDisposition, RoutePopDisposition.doNotPop);
      expect(Navigator.of(boardContext).canPop(), isTrue);
      final routeCompleted = boardRoute.completed;
      Navigator.of(boardContext).removeRoute(boardRoute, 0);
      await tester.pump();
      await tester.runAsync(
        () => routeCompleted.timeout(const Duration(seconds: 2)),
      );
      await tester.pump();

      expect(find.byKey(_openNestedBoardKey), findsOneWidget);
      expect(find.byType(ChessBoardScreenNew), findsNothing);
      expect(
        container.read(chessboardViewFromProviderNew),
        ChessboardView.favorites,
      );
      expect(container.read(chessBoardAllGamesProvider), same(priorGames));
      expect(container.read(currentlyVisiblePageIndexProvider), 7);
      expect(container.read(shouldStreamProvider), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
    },
  );

  testWidgets(
    'covered expansion keeps the visible game aligned when the child pops',
    (tester) async {
      final rawA = _rawGame(
        id: 'covered-a',
        tourId: 'covered-tour',
        round: 'round-2',
        board: 1,
      );
      final rawB = _rawGame(
        id: 'covered-b',
        tourId: 'covered-tour',
        round: 'round-1',
        board: 2,
      );
      final inserted = _rawGame(
        id: 'covered-inserted',
        tourId: 'covered-tour',
        round: 'round-3',
        board: 3,
      );
      final immediateGames = [
        GamesTourModel.fromGame(rawA),
        GamesTourModel.fromGame(rawB),
      ];
      final expandedGames = [
        GamesTourModel.fromGame(inserted),
        GamesTourModel.fromGame(rawA),
        GamesTourModel.fromGame(rawB),
      ];
      final expansion = Completer<({List<GamesTourModel> games, int index})>();
      final container = _boardTestContainer(
        gamesByTour: const {},
        gameRepository: _ImmediateGameRepository({
          rawA.id: rawA,
          rawB.id: rawB,
          inserted.id: inserted,
        }),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorObservers: [routeObserver],
            theme: ThemeData.dark().copyWith(
              extensions: const [AppColors.dark],
            ),
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return expandingChessBoardScreenForTesting(
                  initialGames: immediateGames,
                  initialIndex: 1,
                  expandedNavigation: expansion.future,
                  viewSource: ChessboardView.favScorecard,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(container.read(currentlyVisiblePageIndexProvider), 1);
      expect(
        container.read(chessBoardAllGamesProvider).map((game) => game.gameId),
        ['covered-a', 'covered-b'],
      );

      final boardContext = tester.element(find.byType(ChessBoardScreenNew));
      unawaited(
        Navigator.of(boardContext).push<void>(
          PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder:
                (_, _, _) =>
                    const Scaffold(body: SizedBox(key: _coveredChildRouteKey)),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(_coveredChildRouteKey), findsOneWidget);

      expansion.complete((games: expandedGames, index: 1));
      await tester.pump();
      await tester.pump();

      final coveredBoard = tester.widget<ChessBoardScreenNew>(
        find.byType(ChessBoardScreenNew, skipOffstage: false),
      );
      expect(coveredBoard.games.map((game) => game.gameId), [
        'covered-inserted',
        'covered-a',
        'covered-b',
      ]);
      final coveredPages = find.byKey(
        boardGamesPageViewTestKey,
        skipOffstage: false,
      );
      expect(tester.widget<PageView>(coveredPages).controller!.page, 2);
      expect(
        container.read(chessBoardAllGamesProvider).map((game) => game.gameId),
        ['covered-a', 'covered-b'],
        reason: 'covered board globals stay frozen until didPopNext',
      );
      expect(container.read(currentlyVisiblePageIndexProvider), 1);

      Navigator.of(tester.element(find.byKey(_coveredChildRouteKey))).pop();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byKey(_coveredChildRouteKey), findsNothing);
      final visiblePages = find.byKey(boardGamesPageViewTestKey);
      expect(tester.widget<PageView>(visiblePages).controller!.page, 2);
      expect(
        container.read(chessBoardAllGamesProvider).map((game) => game.gameId),
        ['covered-inserted', 'covered-a', 'covered-b'],
      );
      expect(container.read(currentlyVisiblePageIndexProvider), 2);

      await tester.tap(find.byKey(e2eKey(E2eIds.boardGameSelector)).first);
      await tester.pump(const Duration(milliseconds: 300));
      final dropdown = boardGameDropdownSnapshotForTesting(
        tester.widget(find.byKey(boardGameDropdownContentTestKey)),
      );
      expect(dropdown.currentIndex, 2);
      expect(dropdown.selectedGameId, 'covered-b');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
    },
  );

  testWidgets(
    'game selected before expansion returns to its reordered caller row',
    (tester) async {
      final rawA = _rawGame(
        id: 'caller-a',
        tourId: 'expanded-tour',
        round: 'round-2',
        board: 1,
      );
      final rawB = _rawGame(
        id: 'caller-b',
        tourId: 'expanded-tour',
        round: 'round-1',
        board: 1,
      );
      final expandedOnly = _rawGame(
        id: 'expanded-only',
        tourId: 'expanded-tour',
        round: 'round-3',
        board: 1,
      );
      final callerGames = [
        GamesTourModel.fromGame(rawA),
        GamesTourModel.fromGame(rawB),
      ];
      final expandedGames = [
        GamesTourModel.fromGame(expandedOnly),
        GamesTourModel.fromGame(rawA),
        GamesTourModel.fromGame(rawB),
      ];
      final expansion = Completer<({List<GamesTourModel> games, int index})>();
      final returnedCallerIndexes = <int>[];

      final container = _boardTestContainer(
        gamesByTour: const {},
        gameRepository: _ImmediateGameRepository({'caller-a': rawA}),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [AppColors.dark],
            ),
            home: _ReturnMappingNavigationHost(
              callerGames: callerGames,
              expandedGames: expandedGames,
              expansion: expansion.future,
              onReturn: returnedCallerIndexes.add,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(_openReturnMappingBoardKey));
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final pages = find.byKey(boardGamesPageViewTestKey);
      tester.widget<PageView>(pages).controller!.jumpToPage(1);
      await tester.pump();
      expect(
        tester.widget<PageView>(pages).controller!.page,
        1,
        reason: 'caller B became the visible page before expansion',
      );

      expansion.complete((games: expandedGames, index: 1));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final board = tester.widget<ChessBoardScreenNew>(
        find.byType(ChessBoardScreenNew),
      );
      expect(board.games.map((game) => game.gameId), [
        'expanded-only',
        'caller-a',
        'caller-b',
      ]);
      expect(tester.widget<PageView>(pages).controller!.page, 2);

      final boardContext = tester.element(find.byType(ChessBoardScreenNew));
      final boardRoute = ModalRoute.of(boardContext)!;
      for (var i = 0; i < 3 && boardRoute.willHandlePopInternally; i++) {
        Navigator.of(boardContext).pop(-998);
        await tester.pump();
      }
      expect(boardRoute.willHandlePopInternally, isFalse);
      expect(boardRoute.popDisposition, RoutePopDisposition.doNotPop);
      await Navigator.of(boardContext).maybePop<int>(-999);
      expect(boardRoute.isCurrent, isFalse);
      await tester.pump();

      expect(
        returnedCallerIndexes,
        [1],
        reason:
            'caller B must map from expanded index 2 back to caller index 1',
      );
      expect(find.byKey(_openReturnMappingBoardKey), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
    },
  );

  testWidgets(
    'return mapping snapshot switches only after the expanded child rebuild',
    (tester) async {
      final rawA = _rawGame(
        id: 'pre-frame-a',
        tourId: 'pre-frame-tour',
        round: 'round-2',
        board: 1,
      );
      final rawB = _rawGame(
        id: 'pre-frame-b',
        tourId: 'pre-frame-tour',
        round: 'round-1',
        board: 2,
      );
      final expandedOnly = _rawGame(
        id: 'pre-frame-inserted',
        tourId: 'pre-frame-tour',
        round: 'round-3',
        board: 3,
      );
      final immediateGames = [
        GamesTourModel.fromGame(rawA),
        GamesTourModel.fromGame(rawB),
      ];
      final expandedGames = [
        GamesTourModel.fromGame(expandedOnly),
        GamesTourModel.fromGame(rawA),
        GamesTourModel.fromGame(rawB),
      ];
      final expansion = Completer<({List<GamesTourModel> games, int index})>();
      final snapshotProbe = BoardNavigationSnapshotProbe();
      final container = _boardTestContainer(
        gamesByTour: const {},
        gameRepository: _ImmediateGameRepository({
          rawA.id: rawA,
          rawB.id: rawB,
          expandedOnly.id: expandedOnly,
        }),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [AppColors.dark],
            ),
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return expandingChessBoardScreenForTesting(
                  initialGames: immediateGames,
                  initialIndex: 0,
                  expandedNavigation: expansion.future,
                  viewSource: ChessboardView.forYou,
                  snapshotProbe: snapshotProbe,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final pages = find.byKey(boardGamesPageViewTestKey);
      tester.widget<PageView>(pages).controller!.jumpToPage(1);
      await tester.pump();
      expect(tester.widget<PageView>(pages).controller!.page, 1);

      expansion.complete((games: expandedGames, index: 1));
      // Drain only the resolver/host microtasks. Do not pump a frame: the host
      // has accepted the expanded list, while the visible board still owns the
      // immediate [A, B] index space.
      await tester.idle();
      final preFrameBoard = tester.widget<ChessBoardScreenNew>(
        find.byType(ChessBoardScreenNew),
      );
      expect(preFrameBoard.games.map((game) => game.gameId), [
        'pre-frame-a',
        'pre-frame-b',
      ]);
      expect(
        snapshotProbe.games.map((game) => game.gameId),
        ['pre-frame-a', 'pre-frame-b'],
        reason:
            'Back in this pre-frame window must map the child\'s old index '
            'through the same old list',
      );

      await tester.pump();
      await tester.pump();
      final expandedBoard = tester.widget<ChessBoardScreenNew>(
        find.byType(ChessBoardScreenNew),
      );
      expect(expandedBoard.games.map((game) => game.gameId), [
        'pre-frame-inserted',
        'pre-frame-a',
        'pre-frame-b',
      ]);
      expect(tester.widget<PageView>(pages).controller!.page, 2);
      expect(snapshotProbe.games.map((game) => game.gameId), [
        'pre-frame-inserted',
        'pre-frame-a',
        'pre-frame-b',
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
    },
  );
}

const _openNestedBoardKey = ValueKey<String>('open-nested-board');
const _coveredChildRouteKey = ValueKey<String>('covered-child-route');
const _openReturnMappingBoardKey = ValueKey<String>(
  'open-return-mapping-board',
);

class _NestedBoardNavigationHost extends ConsumerWidget {
  const _NestedBoardNavigationHost({required this.games});

  final List<GamesTourModel> games;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ResponsiveHelper.init(context);
    final navigation = ref.watch(gameCardWrapperProvider);
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: _openNestedBoardKey,
          onPressed: () {
            navigation.navigateToChessBoard(
              context: context,
              orderedGames: games,
              gameIndex: 0,
              onReturnFromChessboard: null,
              viewSource: ChessboardView.tour,
              listPolicy: BoardNavigationListPolicy.preserve,
              disableGamebaseOverlayByDefault: true,
            );
          },
          child: const Text('Open board'),
        ),
      ),
    );
  }
}

class _ReturnMappingNavigationHost extends StatelessWidget {
  const _ReturnMappingNavigationHost({
    required this.callerGames,
    required this.expandedGames,
    required this.expansion,
    required this.onReturn,
  });

  final List<GamesTourModel> callerGames;
  final List<GamesTourModel> expandedGames;
  final Future<({List<GamesTourModel> games, int index})> expansion;
  final ValueChanged<int> onReturn;

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: _openReturnMappingBoardKey,
          onPressed: () async {
            final boardIndex = await Navigator.of(context).push<int>(
              MaterialPageRoute<int>(
                builder:
                    (_) => expandingChessBoardScreenForTesting(
                      initialGames: callerGames,
                      initialIndex: 0,
                      expandedNavigation: expansion,
                      viewSource: ChessboardView.forYou,
                    ),
              ),
            );
            if (boardIndex == null) return;
            final callerIndex = callerIndexForBoardReturn(
              callerGames: callerGames,
              boardGames: expandedGames,
              boardIndex: boardIndex,
            );
            if (callerIndex != null) onReturn(callerIndex);
          },
          child: const Text('Open expanding board'),
        ),
      ),
    );
  }
}

Games _rawGame({
  required String id,
  required String tourId,
  required String round,
  required int board,
  String event = 'Scoped games',
}) {
  return Games(
    id: id,
    roundId: round,
    roundSlug: round,
    tourId: tourId,
    tourSlug: tourId,
    players: [
      _player(name: 'White $id', fideId: board * 2 + 1),
      _player(name: 'Black $id', fideId: board * 2 + 2),
    ],
    boardNr: board,
    status: '1-0',
    lastMove: 'e7e5',
    pgn: '''
[Event "$event"]
[White "White $id"]
[Black "Black $id"]
[Result "1-0"]

1. e4 e5 1-0
''',
  );
}

Player _player({required String name, required int fideId}) {
  return Player(
    name: name,
    title: 'GM',
    rating: 2700,
    fideId: fideId,
    fed: 'USA',
    clock: 0,
    team: '',
  );
}

ProviderContainer _boardTestContainer({
  required Map<String, List<Games>> gamesByTour,
  required GameRepository gameRepository,
}) {
  return ProviderContainer(
    overrides: [
      gamesLocalStorage.overrideWith(
        (ref) => _FullCacheGamesLocalStorage(ref, gamesByTour),
      ),
      gameRepositoryProvider.overrideWithValue(gameRepository),
      gamebaseRepositoryProvider.overrideWithValue(_FakeGamebaseRepository()),
      gameStreamRepositoryProvider.overrideWithValue(
        _FakeGameStreamRepository(),
      ),
      localEvalCacheProvider.overrideWith(_FakeLocalEvalCache.new),
      engineSettingsProviderNew.overrideWith(_FakeEngineSettingsNotifier.new),
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

class _DelayedGameRepository extends GameRepository {
  _DelayedGameRepository(this.latest);

  final Games latest;
  final requested = Completer<void>();
  final release = Completer<void>();

  @override
  Future<Games> getGameWithPGN(String gameId) async {
    if (!requested.isCompleted) requested.complete();
    await release.future;
    return latest;
  }

  @override
  Future<String?> getGamePgn(String gameId) async => latest.pgn;
}

class _ImmediateGameRepository extends GameRepository {
  _ImmediateGameRepository(this.games);

  final Map<String, Games> games;

  @override
  Future<Games> getGameWithPGN(String gameId) async => games[gameId]!;

  @override
  Future<String?> getGamePgn(String gameId) async => games[gameId]?.pgn;
}

class _FullCacheGamesLocalStorage extends GamesLocalStorage {
  _FullCacheGamesLocalStorage(super.ref, this.byTour);

  final Map<String, List<Games>> byTour;

  @override
  Future<List<Games>> getCachedGames(String tourId) async =>
      byTour[tourId] ?? const [];

  @override
  Future<List<Games>> fetchAndSaveGames(
    String tourId, {
    bool forceRefresh = false,
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
  }) async =>
      const GamebaseResponse(status: 'success', data: GamebaseData(moves: []));

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

class _FakeEngineSettingsNotifier extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async =>
      const EngineSettings(showEngineAnalysis: false, showEngineGauge: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
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

class _FakeEventNoSpoilersController extends EventNoSpoilersController {
  _FakeEventNoSpoilersController({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
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
