import 'dart:async';
import 'dart:convert';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';

import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_game_focus_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _pgn = '1. e4 e5 2. Nf3 (2. Bc4 Nf6) Nc6 3. Bb5 a6 *';

class _Repository implements GameRepository {
  @override
  Future<String?> getGamePgn(String gameId) async => _pgn;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Gamebase extends GamebaseRepository {
  _Gamebase() : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');
  @override
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async => null;
}

class _Stream extends GameStreamRepository {
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

class _Settings extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Board {
  _Board() {
    final player = PlayerCard(
      name: 'Player',
      federation: 'TR',
      title: '',
      rating: 0,
      countryCode: 'TR',
      team: null,
    );
    final game = GamesTourModel(
      gameId: 'hold-regression',
      whitePlayer: player,
      blackPlayer: player,
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.whiteWins,
      roundId: 'round',
      tourId: 'tour',
      pgn: _pgn,
    );
    params = ChessBoardProviderParams(game: game, index: 0);
    container = ProviderContainer(
      overrides: [
        engineSettingsProviderNew.overrideWith(_Settings.new),
        gameRepositoryProvider.overrideWithValue(_Repository()),
        gamebaseRepositoryProvider.overrideWithValue(_Gamebase()),
        gameStreamRepositoryProvider.overrideWithValue(_Stream()),
        chessBoardPersistenceEnabledProvider.overrideWithValue(false),
        cascadeEvalProviderForBoard.overrideWith((ref, params) async {
          final pending = engineResponse;
          engineResponse = null;
          if (pending != null) return pending.future;
          return CloudEval(fen: params.fen, knodes: 0, depth: 0, pvs: const []);
        }),
      ],
    );
    container.read(currentlyVisiblePageIndexProvider.notifier).state = 99;
    watch = container.listen(chessBoardScreenProviderNew(params), (_, __) {});
    notifier = container.read(chessBoardScreenProviderNew(params).notifier);
  }

  late final ProviderContainer container;
  late final ChessBoardProviderParams params;
  late final ProviderSubscription<AsyncValue<ChessBoardStateNew>> watch;
  late final ChessBoardScreenNotifierNew notifier;
  Completer<CloudEval>? engineResponse;
  ChessBoardStateNew get state =>
      container.read(chessBoardScreenProviderNew(params)).requireValue;
  String get tree =>
      jsonEncode(notifier.navigatorStateSnapshot()!.game.toJson());

  Future<void> ready() => waitFor(
    () =>
        container
            .read(chessBoardScreenProviderNew(params))
            .valueOrNull
            ?.analysisState
            .game !=
        null,
  );
  Future<void> waitFor(bool Function() done) async {
    for (var i = 0; i < 200; i++) {
      if (done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Timed out waiting for board/engine callback');
  }

  Future<void> engineAtCurrentPosition({
    void Function()? beforeResponse,
  }) async {
    final response = Completer<CloudEval>();
    engineResponse = response;
    final fen = state.analysisState.position.fen;
    container.read(currentlyVisiblePageIndexProvider.notifier).state = 0;
    container.invalidate(cascadeEvalProviderForBoard);
    notifier.evaluateCurrentPosition();
    await waitFor(() => engineResponse == null);
    beforeResponse?.call();
    // At e4 the engine suggests a different existing-game continuation.
    // No actual Stockfish process or network is used.
    response.complete(
      CloudEval(
        fen: fen,
        knodes: 100,
        depth: 30,
        pvs: List.generate(5, (_) => Pv(moves: 'c7c5 g1f3 d7d6', cp: 20)),
      ),
    );
    await waitFor(() => state.principalVariations.isNotEmpty);
    container.read(currentlyVisiblePageIndexProvider.notifier).state = 99;
  }

  Future<void> dispose() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    watch.close();
    container.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform: touch tap/hold/release and branch-tail hold use existing game only',
      (tester) async {
        final board = _Board();
        addTearDown(() => tester.runAsync(board.dispose));
        await tester.runAsync(board.ready);
        board.notifier.goToMovePointer([1]);
        final tree = board.tree;
        final pgn = board.state.pgnData;
        final focus = ExplorerFocusedGameNotifier();
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: board.container,
            child: MaterialApp(
              theme: AppTheme.darkTheme.copyWith(platform: platform),
              home: Consumer(
                builder: (context, ref, child) {
                  ref.watch(chessBoardScreenProviderNew(board.params));
                  ResponsiveHelper.init(context);
                  final snapshot = board.notifier.navigatorStateSnapshot()!;
                  final arrows = resolveBoardNavArrowRouting(
                    focus: null,
                    focusNotifier: focus,
                    boardCanMoveForward: snapshot.canGoForward,
                    boardCanMoveBackward: snapshot.canGoBackward,
                    boardCanJumpToStart: snapshot.movePointer.isNotEmpty,
                    boardCanJumpToEnd:
                        snapshot.movePointer.length != 1 ||
                        snapshot.movePointer.first != 5,
                    onBoardForward: () => board.notifier.moveForward(),
                    onBoardBackward: () => board.notifier.moveBackward(),
                    onBoardLongPressBackwardStart: board.notifier.jumpToStart,
                    onBoardLongPressBackwardEnd: board.notifier.stopLongPress,
                    onBoardLongPressForwardStart: board.notifier.jumpToEnd,
                    onBoardLongPressForwardEnd: board.notifier.stopLongPress,
                  );
                  return Scaffold(
                    bottomNavigationBar: ChessBoardBottomNavBar(
                      gameIndex: 0,
                      onFlip: () {},
                      onLeftMove: arrows.onLeftMove,
                      onRightMove: arrows.onRightMove,
                      canMoveForward: arrows.canMoveForward,
                      canMoveBackward: arrows.canMoveBackward,
                      onLongPressBackwardStart: arrows.onLongPressBackwardStart,
                      onLongPressBackwardEnd: arrows.onLongPressBackwardEnd,
                      onLongPressForwardStart: arrows.onLongPressForwardStart,
                      onLongPressForwardEnd: arrows.onLongPressForwardEnd,
                      showEngineAnalysis: false,
                      showUnseenMoveBadge: false,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
        final right = find.byKey(e2eKey(E2eIds.boardMoveForward));
        final left = find.byKey(e2eKey(E2eIds.boardMoveBack));
        await tester.tap(right);
        await tester.pump(const Duration(milliseconds: 100));
        expect(board.state.analysisState.movePointer, [2]);
        await tester.tap(left);
        await tester.pump(const Duration(milliseconds: 100));
        expect(board.state.analysisState.movePointer, [1]);
        for (final forward in [true, false]) {
          final gesture = await tester.startGesture(
            tester.getCenter(forward ? right : left),
          );
          await tester.pump(const Duration(milliseconds: 600));
          expect(
            board.state.analysisState.movePointer,
            forward ? [5] : <int>[],
          );
          await tester.pump(const Duration(seconds: 1));
          await gesture.up();
          await tester.pump();
          expect(
            board.state.analysisState.movePointer,
            forward ? [5] : <int>[],
          );
        }
        board.notifier.goToMovePointer([1, 0, 1]);
        await tester.pump();
        await tester.tap(right);
        await tester.pump();
        // Existing navigator contract returns to the saved parent continuation
        // after a variation's tail; it never creates a suggested move.
        expect(board.state.analysisState.movePointer, [2]);
        board.notifier.goToMovePointer([1, 0, 1]);
        await tester.pump();
        await tester.longPress(right);
        await tester.pump();
        expect(board.state.analysisState.movePointer, [5]);
        expect(board.tree, tree);
        expect(board.state.pgnData, pgn);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
  }

  test(
    'engine arrival does not select a PV; holds reach game endpoints without edits',
    () async {
      final board = _Board();
      addTearDown(board.dispose);
      await board.ready();
      board.notifier.goToMovePointer([0]);
      final tree = board.tree;
      final pgn = board.state.pgnData;
      await board.engineAtCurrentPosition();
      expect(board.state.selectedVariantIndex, isNull);
      board.notifier.jumpToEnd();
      expect(board.state.analysisState.movePointer, [5]);
      board.notifier.jumpToStart();
      expect(board.state.analysisState.movePointer, isEmpty);
      expect(board.tree, tree);
      expect(board.state.pgnData, pgn);
    },
  );

  for (final forward in [true, false]) {
    test('hold ${forward ? 'end' : 'start'} supersedes queued taps', () async {
      final board = _Board();
      addTearDown(board.dispose);
      await board.ready();
      board.notifier.goToMovePointer([3]);
      final tree = board.tree;
      final taps = List.generate(3, (_) => board.notifier.moveBackward());
      if (forward) {
        board.notifier.jumpToEnd();
      } else {
        board.notifier.jumpToStart();
      }
      await Future.wait(taps);
      await Future<void>.delayed(Duration.zero);
      expect(board.state.analysisState.movePointer, forward ? [5] : <int>[]);
      expect(board.tree, tree);
    });
  }

  for (final forward in [true, false]) {
    test(
      'notation tap then delayed engine callback then ${forward ? 'right' : 'left'} hold never inserts',
      () async {
        final board = _Board();
        addTearDown(board.dispose);
        await board.ready();
        board.notifier.goToMovePointer([0]);
        final tree = board.tree;
        final pgn = board.state.pgnData;
        await board.engineAtCurrentPosition(
          beforeResponse: () => board.notifier.goToMovePointer([0]),
        );
        // Also exercise an explicitly selected engine line: hold is still game navigation.
        board.notifier.selectVariant(0);
        expect(board.state.selectedVariantIndex, 0);
        if (forward) {
          board.notifier.jumpToEnd();
        } else {
          board.notifier.jumpToStart();
        }
        expect(board.state.analysisState.movePointer, forward ? [5] : <int>[]);
        expect(board.state.selectedVariantIndex, isNull);
        expect(board.tree, tree);
        expect(board.state.pgnData, pgn);
      },
    );
  }

  test(
    'taps traverse existing variation; holds target mainline, not variation tail',
    () async {
      final board = _Board();
      addTearDown(board.dispose);
      await board.ready();
      final tree = board.tree;
      final pgn = board.state.pgnData;
      board.notifier.goToMovePointer([1, 0, 0]);
      await board.notifier.moveForward();
      expect(board.state.analysisState.movePointer, [1, 0, 1]);
      await board.notifier.moveBackward();
      expect(board.state.analysisState.movePointer, [1, 0, 0]);
      board.notifier.jumpToEnd();
      expect(board.state.analysisState.movePointer, [5]);
      board.notifier.jumpToEnd();
      board.notifier.jumpToStart();
      board.notifier.jumpToStart();
      expect(board.state.analysisState.movePointer, isEmpty);
      expect(board.tree, tree);
      expect(board.state.pgnData, pgn);
    },
  );

  test(
    'explicit PV preview stays non-mutating and insertion remains intentional',
    () async {
      final board = _Board();
      addTearDown(board.dispose);
      await board.ready();
      board.notifier.goToMovePointer([0]);
      await board.engineAtCurrentPosition();
      final tree = board.tree;
      final line = board.state.principalVariations.first;
      board.notifier.previewPrincipalVariationMoveAt(line, 0, 0);
      expect(board.state.isPvPreviewActive, isTrue);
      await board.notifier.moveForward();
      expect(board.state.lockedPvNavigationIndex, 1);
      await board.notifier.moveBackward();
      expect(board.state.lockedPvNavigationIndex, 0);
      expect(board.tree, tree);
      board.notifier.jumpToEnd();
      expect(board.state.isPvPreviewActive, isFalse);
      expect(board.state.analysisState.movePointer, [5]);
      expect(board.tree, tree);
      board.notifier.goToMovePointer([0]);
      board.notifier.insertPvMoves(line);
      expect(board.tree, isNot(tree));
    },
  );

  test('focused Explorer card owns taps and immediate endpoint holds', () {
    final focus = ExplorerFocusedGameNotifier();
    addTearDown(focus.dispose);
    focus.focus(
      gameId: 'card',
      anchorFen: 'anchor',
      sans: ['e4', 'e5', 'Nf3', 'Nc6'],
      fens: ['anchor', 'one', 'two', 'three', 'four'],
    );
    var boardCalls = 0;
    BoardNavArrowRouting routing() => resolveBoardNavArrowRouting(
      focus: focus.state,
      focusNotifier: focus,
      boardCanMoveForward: true,
      boardCanMoveBackward: true,
      onBoardForward: () => boardCalls++,
      onBoardBackward: () => boardCalls++,
      onBoardLongPressBackwardStart: () => boardCalls++,
      onBoardLongPressBackwardEnd: () {},
      onBoardLongPressForwardStart: () => boardCalls++,
      onBoardLongPressForwardEnd: () {},
    );
    final sans = focus.state!.sans;
    routing().onRightMove!();
    expect(focus.state!.ply, 1);
    routing().onLongPressForwardStart!();
    expect(focus.state!.ply, 3);
    routing().onLongPressForwardEnd!();
    routing().onLongPressBackwardStart!();
    expect(focus.state!.ply, -1);
    routing().onLongPressBackwardEnd!();
    expect(focus.state!.sans, same(sans));
    expect(boardCalls, 0);
    expect(focus.isLongPressing, isFalse);
    focus.onExplorerPositionChanged('new-position');
    expect(focus.state, isNull);
    routing().onRightMove!();
    expect(boardCalls, 1);
  });
}
