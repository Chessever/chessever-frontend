import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/board_editor/board_editor_state.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/widgets/board_opening_explorer_panel.dart';
import 'package:chessever2/screens/gamebase/widgets/explorer_game_card.dart';
import 'package:chessever2/screens/gamebase/widgets/position_games_sheet.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A Board Editor position: real depth unknown, counters claim move 1. The
/// aggregate endpoint anchors on the ply the FEN claims, so it answers empty
/// for this no matter how many games actually reached the position.
const _editorEndgameFen = '8/8/8/4k3/8/4K3/4P3/8 w - - 0 1';

class _TestBoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _TestEngineSettings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async =>
      const EngineSettings(showEngineAnalysis: false);
}

class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository({
    required this.fenGamesRows,
    this.moveAggregates = const <MoveAggregate>[],
    this.fenGamesTotalCount,
  }) : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  final List<Map<String, dynamic>> fenGamesRows;

  /// Backend total when it exceeds the returned page — drives the overflow
  /// link out of the capped strip. Null means "exactly these rows".
  final int? fenGamesTotalCount;
  final List<MoveAggregate> moveAggregates;
  int fenGamesRequests = 0;
  int fullGameRequests = 0;
  int? lastFenNotationPlies;

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
  }) async {
    return GamebaseResponse(
      status: 'success',
      data: GamebaseData(moves: moveAggregates),
    );
  }

  @override
  Future<GamebaseSearchQueryResponse> getFenPositionGames({
    required String fen,
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
    fenGamesRequests++;
    lastFenNotationPlies = notationPlies;
    return GamebaseSearchQueryResponse(
      status: 'success',
      data: fenGamesRows,
      metadata: GamebasePaginationMetadata(
        pageNumber: pageNumber,
        pageSize: pageSize,
        totalCount: fenGamesTotalCount ?? fenGamesRows.length,
        hasMoreValue: fenGamesTotalCount != null,
      ),
    );
  }

  @override
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async {
    fullGameRequests++;
    return null;
  }
}

Future<ProviderContainer> _pumpPanelWithEditorPosition(
  WidgetTester tester,
  _FakeGamebaseRepository repository, {
  GamebaseFilters? initialFilters,
}) async {
  final container = ProviderContainer(
    overrides: [
      gamebaseRepositoryProvider.overrideWithValue(repository),
      boardSettingsProviderNew.overrideWith(_TestBoardSettings.new),
      engineSettingsProviderNew.overrideWith(_TestEngineSettings.new),
    ],
  );
  if (initialFilters != null) {
    container
        .read(gamebaseExplorerProvider.notifier)
        .updateFilters(initialFilters, fetch: false);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const Scaffold(
              body: BoardOpeningExplorerPanel(
                currentFen: _editorEndgameFen,
                startingFen: _editorEndgameFen,
                lineUcis: <String>[],
                onMoveSelected: _ignoreMove,
              ),
            );
          },
        ),
      ),
    ),
  );

  // Debounced fetch (200ms) + the FEN-keyed has-games follow-up.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 50));
  return container;
}

void _ignoreMove(String _) {}

Future<void> _teardownPanel(
  WidgetTester tester,
  ProviderContainer container,
) async {
  // The panel mounts the subscription provider, which owns a periodic timer.
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Board Editor position in the Explorer panel', () {
    testWidgets('custom-start positions use the regular Explorer move table', (
      tester,
    ) async {
      final repository = _FakeGamebaseRepository(
        fenGamesRows: const [],
        moveAggregates: const [
          MoveAggregate(uci: 'e3d3', white: 10, black: 6, draws: 4, total: 20),
        ],
      );
      final container = await _pumpPanelWithEditorPosition(tester, repository);

      expect(
        find.byKey(const ValueKey('opening_explorer_sort_games')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('opening_explorer_filter_button')),
        findsOneWidget,
      );
      expect(find.text('Results'), findsOneWidget);
      expect(find.text('Games'), findsOneWidget);
      expect(find.text('Last'), findsOneWidget);
      expect(find.byType(LibraryGameCard), findsNothing);
      expect(repository.fenGamesRequests, 0);

      await _teardownPanel(tester, container);
    });

    testWidgets('board explorer keeps active filters when it syncs the FEN', (
      tester,
    ) async {
      const filters = GamebaseFilters(
        timeControls: [TimeControl.rapid],
        minRating: 2400,
        yearFrom: 2020,
        gameResult: GamebaseGameResult.draw,
      );
      final repository = _FakeGamebaseRepository(
        fenGamesRows: const [],
        moveAggregates: const [
          MoveAggregate(uci: 'e3d3', white: 3, black: 2, draws: 5, total: 10),
        ],
      );
      final container = await _pumpPanelWithEditorPosition(
        tester,
        repository,
        initialFilters: filters,
      );

      expect(container.read(gamebaseExplorerProvider).filters, filters);
      expect(
        find.byKey(const ValueKey('opening_explorer_filter_button')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('opening_explorer_sort_last')),
      );
      await tester.pump();
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey('opening_explorer_sort_last')),
            )
            .properties
            .selected,
        isTrue,
      );

      container
          .read(gamebaseExplorerProvider.notifier)
          .updateFilters(
            filters.copyWith(gameResult: GamebaseGameResult.whiteWins),
            fetch: false,
          );
      await tester.pump();
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey('opening_explorer_sort_last')),
            )
            .properties
            .selected,
        isTrue,
      );

      await tester.tap(
        find.byKey(const ValueKey('opening_explorer_filter_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Rapid'), findsOneWidget);
      expect(find.text('½-½'), findsOneWidget);

      Navigator.of(tester.element(find.text('Filters'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _teardownPanel(tester, container);
    });

    testWidgets(
      'empty aggregates for a custom-start FEN fall back to the FEN-keyed '
      'games endpoint and render the same inline games strip as every other '
      'explorer position',
      (tester) async {
        tester.view.physicalSize = const Size(727, 282);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final repository = _FakeGamebaseRepository(
          fenGamesRows: const [
            {
              'id': 'g1',
              'white': 'Position White',
              'black': 'Position Black',
              'whiteElo': 2500,
              'blackElo': 2450,
              'result': 'W',
              'date': '2026-08-31T00:00:00.000Z',
              'continuation': <String>[],
            },
          ],
        );
        final container = await _pumpPanelWithEditorPosition(
          tester,
          repository,
        );

        expect(find.text('No games match this position'), findsNothing);
        expect(find.text('No move statistics for this position'), findsNothing);
        expect(find.text('View games'), findsNothing);

        // The strip is the regular explorer one, card for card. The old
        // embedded PositionGamesSheet — its own 'Games at this position'
        // header, its own list, LibraryGameCards — must not come back.
        expect(find.byType(ExplorerGameCard), findsOneWidget);
        expect(find.byType(LibraryGameCard), findsNothing);
        expect(find.byType(PositionGamesSheet), findsNothing);
        expect(find.text('Games at this position'), findsNothing);
        expect(find.byTooltip('Close'), findsNothing);

        expect(repository.fenGamesRequests, greaterThan(0));
        // Continuation chips need the preview slice the aggregate-fed strip
        // also asks for; 0 plies is what the old sheet requested.
        expect(repository.lastFenNotationPlies, 20);
        expect(tester.takeException(), isNull);

        await _teardownPanel(tester, container);
      },
    );

    testWidgets(
      'a FEN position with more games than the strip holds keeps the rest '
      'reachable through the full sheet',
      (tester) async {
        tester.view.physicalSize = const Size(727, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final repository = _FakeGamebaseRepository(
          fenGamesRows: List.generate(
            10,
            (i) => <String, dynamic>{
              'id': 'g$i',
              'white': 'White $i',
              'black': 'Black $i',
              'whiteElo': 2500,
              'blackElo': 2450,
              'result': 'W',
              'date': '2026-08-31T00:00:00.000Z',
              'continuation': <String>[],
            },
          ),
          fenGamesTotalCount: 47,
        );
        final container = await _pumpPanelWithEditorPosition(
          tester,
          repository,
        );

        // The strip stays capped at 10 like everywhere else, but an exact-FEN
        // position has no '∑' row, so the remaining 37 need their own way out.
        expect(find.byType(ExplorerGameCard), findsNWidgets(10));
        expect(find.text('View all 47 games'), findsOneWidget);

        await _teardownPanel(tester, container);
      },
    );

    testWidgets(
      'a truly unseen custom-start position may claim no games — but only '
      'after the FEN-keyed endpoint confirmed it',
      (tester) async {
        final repository = _FakeGamebaseRepository(fenGamesRows: const []);
        final container = await _pumpPanelWithEditorPosition(
          tester,
          repository,
        );

        expect(repository.fenGamesRequests, greaterThan(0));
        expect(find.text('No games match this position'), findsOneWidget);

        await _teardownPanel(tester, container);
      },
    );
  });

  group('Board Editor FEN counters', () {
    test('editing pieces keeps the fullmove counter, resets the rest', () {
      final notifier = BoardEditorNotifier();
      notifier.loadFen('8/8/8/4k3/8/4K3/4P3/8 w - - 7 42');

      notifier.onDroppedPiece(
        null,
        Square.a1,
        const Piece(color: Side.white, role: Role.rook),
      );

      final fen = notifier.state.fullFen;
      expect(fen.endsWith(' 0 42'), isTrue, reason: 'got $fen');
    });

    test('the starting position still reads as move 1 after edits', () {
      final notifier = BoardEditorNotifier();
      notifier.onDroppedPiece(
        null,
        Square.a4,
        const Piece(color: Side.white, role: Role.queen),
      );
      expect(notifier.state.fullFen.endsWith(' 0 1'), isTrue);
    });
  });
}
