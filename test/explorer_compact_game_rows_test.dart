// Explorer inline game cards (original card from Trello #984):
// mini board + players + scrollable continuation chips + focus provider.
// Also covers games-pin expand contract + bottom-nav arrow ownership while pinned.

import 'dart:io' as io;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_game_focus_provider.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/utils/continuation_line.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/gamebase/widgets/explorer_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _anchorFen = kInitialFEN;

PlayerCard _player(String name, {int rating = 2800, String title = 'GM'}) =>
    PlayerCard(
      name: name,
      federation: '',
      title: title,
      rating: rating,
      countryCode: '',
      team: null,
    );

GamesTourModel _game({
  String id = 'g1',
  String white = 'Magnus Carlsen',
  String black = 'Hikaru Nakamura',
}) {
  return GamesTourModel(
    gameId: id,
    source: GameSource.gamebase,
    whitePlayer: _player(white),
    blackPlayer: _player(black),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.whiteWins,
    roundId: 'opening_explorer',
    tourId: 'Gamebase',
    eco: 'C45',
    lastMoveTime: DateTime(2024, 5, 12),
  );
}

ContinuationLine _lineFromUcis(List<String> ucis) =>
    buildContinuationLine(_anchorFen, ucis);

class _BoardSettingsNotifier extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async {
    const settings = BoardSettingsNew(useFigurine: false);
    state = const AsyncValue.data(settings);
    return settings;
  }
}

class _TestEngineSettingsNotifier extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async {
    const settings = EngineSettings(showEngineAnalysis: false);
    state = const AsyncValue.data(settings);
    return settings;
  }
}

class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository(this.rows)
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  final List<Map<String, dynamic>> rows;

  @override
  Future<GamebaseSearchQueryResponse> getPositionGames({
    required String fen,
    List<String> moves = const [],
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int notationPlies = 0,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    return GamebaseSearchQueryResponse(
      status: 'success',
      data: rows,
      metadata: GamebasePaginationMetadata(
        pageNumber: pageNumber,
        pageSize: pageSize,
        totalCount: rows.length,
        hasMoreValue: false,
      ),
    );
  }
}

List<Override> _baseOverrides({GamebaseRepository? repo}) {
  return [
    boardSettingsProviderNew.overrideWith(_BoardSettingsNotifier.new),
    if (repo != null) gamebaseRepositoryProvider.overrideWithValue(repo),
  ];
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required GamesTourModel game,
  required ContinuationLine line,
  ProviderContainer? container,
}) async {
  final owned = container == null;
  final c = container ?? ProviderContainer(overrides: _baseOverrides());
  if (owned) addTearDown(c.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: UnconstrainedBox(
                  constrainedAxis: Axis.horizontal,
                  child: SizedBox(
                    width: 400,
                    child: ExplorerGameCard(
                      game: game,
                      anchorFen: _anchorFen,
                      line: line,
                      allGames: [game],
                      index: 0,
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
  await tester.pump();
}

Future<void> _pumpSection(
  WidgetTester tester, {
  required ProviderContainer container,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: SingleChildScrollView(
                child: ExplorerGamesSection(
                  fen: _anchorFen,
                  moves: const [],
                  filters: const GamebaseFilters(),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExplorerGameCard (original card)', () {
    testWidgets('shows mini board, players, scores, and SAN chips', (
      tester,
    ) async {
      final line = _lineFromUcis(const ['e2e4', 'e7e5', 'g1f3']);
      final game = _game();
      await _pumpCard(tester, game: game, line: line);

      expect(find.byType(GameCardChessboard), findsOneWidget);
      expect(find.byType(StaticChessboard), findsOneWidget);
      // Title+name+rating are a single RichText span: "GM Magnus Carlsen 2800"
      expect(find.textContaining('Magnus Carlsen'), findsOneWidget);
      expect(find.textContaining('Hikaru Nakamura'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('1. e4'), findsOneWidget);
      expect(find.text('e5'), findsOneWidget);
      expect(find.text('2. Nf3'), findsOneWidget);

      final scrollViews = tester.widgetList<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(
        scrollViews.any((s) => s.scrollDirection == Axis.horizontal),
        isTrue,
      );
    });

    testWidgets('tapping a notation chip focuses the game', (tester) async {
      final line = _lineFromUcis(const ['e2e4', 'e7e5', 'g1f3']);
      final game = _game();
      final container = ProviderContainer(overrides: _baseOverrides());
      addTearDown(container.dispose);

      await _pumpCard(tester, game: game, line: line, container: container);
      expect(container.read(explorerFocusedGameProvider), isNull);

      await tester.tap(find.text('2. Nf3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      final focus = container.read(explorerFocusedGameProvider);
      expect(focus, isNotNull);
      expect(focus!.gameId, game.gameId);
      expect(focus.ply, 2);
      expect(focus.sans, line.sans);
    });

    testWidgets('focused jumpTo updates board FEN; X clears focus', (
      tester,
    ) async {
      final line = _lineFromUcis(const ['e2e4', 'e7e5', 'g1f3']);
      final game = _game();
      final container = ProviderContainer(overrides: _baseOverrides());
      addTearDown(container.dispose);

      await _pumpCard(tester, game: game, line: line, container: container);

      await tester.tap(find.text('1. e4'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(container.read(explorerFocusedGameProvider)?.ply, 0);
      var board = tester.widget<GameCardChessboard>(
        find.byType(GameCardChessboard),
      );
      expect(board.fen, line.fens[1]);

      container.read(explorerFocusedGameProvider.notifier).jumpTo(1);
      await tester.pump();
      board = tester.widget<GameCardChessboard>(
        find.byType(GameCardChessboard),
      );
      expect(board.fen, line.fens[2]);

      // Body tap opens the board (not clear-only). Unfocus is the X control.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(container.read(explorerFocusedGameProvider), isNull);
    });
  });

  group('resolveExplorerCardBodyAction (first body tap opens board)', () {
    test('unfocused body always opens the chess board game', () {
      expect(
        resolveExplorerCardBodyAction(isThisCardFocused: false),
        ExplorerCardBodyAction.openGame,
      );
    });

    test('focused body still opens — never clear-focus-only fen snap', () {
      // Regression: focused body used to clear focus only, which jumped the
      // mini-board to the terminal fen without navigating to the board screen.
      expect(
        resolveExplorerCardBodyAction(isThisCardFocused: true),
        ExplorerCardBodyAction.openGame,
      );
    });

    test('shipped body handler wires openGamebaseGame, no early clear return', () {
      final source =
          io.File(
            'lib/screens/gamebase/widgets/explorer_game_card.dart',
          ).readAsStringSync();
      expect(source, contains('resolveExplorerCardBodyAction('));
      expect(source, contains('resolveExplorerCardOpenInitialFen('));
      expect(source, contains('await openGamebaseGame('));
      // Must not short-circuit body tap to clear-only when focused.
      expect(
        source,
        isNot(
          contains(
            '// Tapping the focused card\'s body toggles focus off',
          ),
        ),
      );
      expect(source, isNot(contains('toggles focus off (always allowed)')));
    });
  });

  group('resolveExplorerCardOpenInitialFen (continue from focused ply)', () {
    test('unfocused open uses explorer anchor fen', () {
      final fen = resolveExplorerCardOpenInitialFen(
        gameId: 'g1',
        anchorFen: _anchorFen,
        focus: null,
      );
      expect(fen, _anchorFen);
    });

    test('focused open uses focus.boardFen at mid continuation ply', () {
      final line = _lineFromUcis(const ['e2e4', 'e7e5', 'g1f3']);
      final focus = ExplorerGameFocus(
        gameId: 'g1',
        anchorFen: _anchorFen,
        sans: line.sans,
        fens: line.fens,
        ply: 1, // after e5
      );
      expect(focus.boardFen, line.fens[2]);
      final fen = resolveExplorerCardOpenInitialFen(
        gameId: 'g1',
        anchorFen: _anchorFen,
        focus: focus,
      );
      expect(fen, focus.boardFen);
      expect(fen, isNot(_anchorFen));
    });

    test('focus for a different game id falls back to anchor', () {
      final line = _lineFromUcis(const ['e2e4', 'e7e5']);
      final focus = ExplorerGameFocus(
        gameId: 'other',
        anchorFen: _anchorFen,
        sans: line.sans,
        fens: line.fens,
        ply: 0,
      );
      final fen = resolveExplorerCardOpenInitialFen(
        gameId: 'g1',
        anchorFen: _anchorFen,
        focus: focus,
      );
      expect(fen, _anchorFen);
    });

    test('body open reads open fen before openGamebaseGame clears focus', () {
      final source =
          io.File(
            'lib/screens/gamebase/widgets/explorer_game_card.dart',
          ).readAsStringSync();
      // openFen must be resolved from live focus prior to the open call.
      final openFenIdx = source.indexOf('resolveExplorerCardOpenInitialFen(');
      final openCallIdx = source.indexOf('await openGamebaseGame(');
      expect(openFenIdx, greaterThan(0));
      expect(openCallIdx, greaterThan(openFenIdx));
      expect(source, contains('openFen,'));
    });
  });

  group('ExplorerGamesSection', () {
    testWidgets('renders cards from position games response', (tester) async {
      final rows = [
        {
          'id': 'g1',
          'white': 'Magnus Carlsen',
          'black': 'Hikaru Nakamura',
          'result': '1-0',
          'whiteElo': 2800,
          'blackElo': 2750,
          'eco': 'C45',
          'date': '2024-05-12',
          'continuation': ['e2e4', 'e7e5', 'g1f3'],
        },
      ];
      final container = ProviderContainer(
        overrides: _baseOverrides(repo: _FakeGamebaseRepository(rows)),
      );
      addTearDown(container.dispose);

      await _pumpSection(tester, container: container);
      await tester.pumpAndSettle();

      expect(find.byType(ExplorerGameCard), findsOneWidget);
      expect(find.text('Games'), findsOneWidget);
      expect(find.textContaining('Magnus Carlsen'), findsOneWidget);
      expect(find.byType(GameCardChessboard), findsOneWidget);
    });
  });

  group('source audit', () {
    test('original card wiring preserved', () {
      final source =
          io.File(
            'lib/screens/gamebase/widgets/explorer_game_card.dart',
          ).readAsStringSync();
      expect(source, contains('GameCardChessboard'));
      expect(source, contains('requirePremiumGuard'));
      // Free users: full-card barrier + per-action gate → paywall on interact.
      expect(source, contains('_freeUserLocked'));
      expect(source, contains('_requirePremium'));
      expect(source, contains('IgnorePointer(child: shell)'));
      expect(source, contains('focusNotifier.focus('));
      expect(source, contains('openGamebaseGame('));
      expect(source, contains('_buildChip'));
      expect(source, contains('Scrollable.ensureVisible'));
      // Chip inset lives inside the horizontal scroll view.
      expect(
        source,
        contains('padding: EdgeInsets.fromLTRB(10.sp, 8.sp, 10.sp, 10.sp)'),
      );
      // Mini-board enlarged for readability when games fill the panel.
      expect(source, contains('final boardSize = 124.sp'));
    });

    test('board chrome wires shipped expand + arrow helpers', () {
      final nav =
          io.File(
            'lib/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart',
          ).readAsStringSync();
      // No slide-hide / IgnorePointer kill of the bar for games pin.
      expect(nav, isNot(contains('AnimatedSlide')));
      expect(nav, isNot(contains('hideForExplorer')));
      expect(nav, isNot(contains('explorerInlineGamesPinnedProvider')));
      expect(nav, contains('Bottom nav always stays put'));

      final screen =
          io.File(
            'lib/screens/chessboard/chess_board_screen_new.dart',
          ).readAsStringSync();
      // Expand path uses the shipped helper (not a parallel reimplementation).
      expect(screen, contains('shouldExpandExplorerGamesOverPv('));
      expect(screen, contains('resolveBoardNavArrowRouting('));
      expect(screen, contains('explorerInlineGamesPinnedProvider'));
      expect(
        screen,
        contains(
          'ref.read(explorerInlineGamesPinnedProvider.notifier).state = false',
        ),
      );
    });
  });

  group('shouldExpandExplorerGamesOverPv', () {
    test('true only when visible page + explorer open + games pinned', () {
      expect(
        shouldExpandExplorerGamesOverPv(
          pageVisible: true,
          explorerPanelVisible: true,
          gamesPinned: true,
        ),
        isTrue,
      );
      expect(
        shouldExpandExplorerGamesOverPv(
          pageVisible: false,
          explorerPanelVisible: true,
          gamesPinned: true,
        ),
        isFalse,
      );
      expect(
        shouldExpandExplorerGamesOverPv(
          pageVisible: true,
          explorerPanelVisible: false,
          gamesPinned: true,
        ),
        isFalse,
      );
      expect(
        shouldExpandExplorerGamesOverPv(
          pageVisible: true,
          explorerPanelVisible: true,
          gamesPinned: false,
        ),
        isFalse,
      );
    });
  });

  group('board nav arrow ownership while games pinned', () {
    test(
      'resolveBoardNavArrowRouting hands arrows to focus notifier when pinned',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Games expand mode active — must not change arrow ownership.
        container.read(explorerInlineGamesPinnedProvider.notifier).state = true;

        final line = _lineFromUcis(const ['e2e4', 'e7e5', 'g1f3']);
        final focusNotifier = container.read(
          explorerFocusedGameProvider.notifier,
        );
        focusNotifier.focus(
          gameId: 'g1',
          anchorFen: _anchorFen,
          sans: line.sans,
          fens: line.fens,
          ply: 0,
        );

        var boardForwardHits = 0;
        var boardBackwardHits = 0;
        final routing = resolveBoardNavArrowRouting(
          focus: container.read(explorerFocusedGameProvider),
          focusNotifier: focusNotifier,
          boardCanMoveForward: true,
          boardCanMoveBackward: true,
          onBoardForward: () => boardForwardHits++,
          onBoardBackward: () => boardBackwardHits++,
          onBoardLongPressBackwardStart: () {},
          onBoardLongPressBackwardEnd: () {},
          onBoardLongPressForwardStart: () {},
          onBoardLongPressForwardEnd: () {},
        );

        expect(routing.canMoveForward, isTrue);
        expect(routing.canMoveBackward, isTrue);
        expect(routing.onRightMove, isNotNull);
        expect(routing.onLeftMove, isNotNull);

        routing.onRightMove!();
        expect(container.read(explorerFocusedGameProvider)!.ply, 1);
        expect(boardForwardHits, 0);

        routing.onRightMove!();
        expect(container.read(explorerFocusedGameProvider)!.ply, 2);

        routing.onLeftMove!();
        expect(container.read(explorerFocusedGameProvider)!.ply, 1);
        expect(boardBackwardHits, 0);

        // Pin still true after arrow steps.
        expect(container.read(explorerInlineGamesPinnedProvider), isTrue);
      },
    );

    testWidgets(
      'ChessBoardBottomNavBar forward/back walk focused card while pinned',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            engineSettingsProviderNew.overrideWith(
              _TestEngineSettingsNotifier.new,
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(explorerInlineGamesPinnedProvider.notifier).state = true;

        // Keep autoDispose focus provider alive for the whole test (avoids
        // Riverpod dispose timers after the last read).
        final focusSub = container.listen(
          explorerFocusedGameProvider,
          (_, __) {},
        );
        addTearDown(focusSub.close);

        final line = _lineFromUcis(const ['e2e4', 'e7e5', 'g1f3']);
        final focusNotifier = container.read(
          explorerFocusedGameProvider.notifier,
        );
        focusNotifier.focus(
          gameId: 'g1',
          anchorFen: _anchorFen,
          sans: line.sans,
          fens: line.fens,
          ply: 0,
        );

        var boardForwardHits = 0;
        final routing = resolveBoardNavArrowRouting(
          focus: container.read(explorerFocusedGameProvider),
          focusNotifier: focusNotifier,
          boardCanMoveForward: true,
          boardCanMoveBackward: true,
          onBoardForward: () => boardForwardHits++,
          onBoardBackward: () {},
          onBoardLongPressBackwardStart: () {},
          onBoardLongPressBackwardEnd: () {},
          onBoardLongPressForwardStart: () {},
          onBoardLongPressForwardEnd: () {},
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
                  return Scaffold(
                    bottomNavigationBar: ChessBoardBottomNavBar(
                      gameIndex: 0,
                      onLeftMove: routing.onLeftMove,
                      onRightMove: routing.onRightMove,
                      onFlip: () {},
                      canMoveForward: routing.canMoveForward,
                      canMoveBackward: routing.canMoveBackward,
                      showEngineAnalysis: false,
                      showUnseenMoveBadge: false,
                      onLongPressBackwardStart:
                          routing.onLongPressBackwardStart,
                      onLongPressBackwardEnd: routing.onLongPressBackwardEnd,
                      onLongPressForwardStart: routing.onLongPressForwardStart,
                      onLongPressForwardEnd: routing.onLongPressForwardEnd,
                      explorerPanelVisible: true,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        // Bar is present and interactive (not slid away / ignore-pointered).
        expect(find.byType(ChessBoardBottomNavBar), findsOneWidget);
        expect(find.byKey(e2eKey(E2eIds.boardMoveForward)), findsOneWidget);
        expect(find.byKey(e2eKey(E2eIds.boardMoveBack)), findsOneWidget);

        await tester.tap(find.byKey(e2eKey(E2eIds.boardMoveForward)));
        await tester.pump();
        expect(container.read(explorerFocusedGameProvider)!.ply, 1);
        expect(boardForwardHits, 0);

        await tester.tap(find.byKey(e2eKey(E2eIds.boardMoveForward)));
        await tester.pump();
        expect(container.read(explorerFocusedGameProvider)!.ply, 2);

        await tester.tap(find.byKey(e2eKey(E2eIds.boardMoveBack)));
        await tester.pump();
        expect(container.read(explorerFocusedGameProvider)!.ply, 1);

        // Still pinned; board never stole the arrows.
        expect(container.read(explorerInlineGamesPinnedProvider), isTrue);
        expect(boardForwardHits, 0);

        // Unmount before container dispose so no pending Riverpod timers.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 50));
      },
    );
  });
}
