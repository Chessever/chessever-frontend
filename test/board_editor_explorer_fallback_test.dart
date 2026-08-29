import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/board_editor/board_editor_state.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/widgets/move_statistics_panel.dart';
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

class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository({required this.fenGamesRows})
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  final List<Map<String, dynamic>> fenGamesRows;
  int fenGamesRequests = 0;

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
    return const GamebaseResponse(
      status: 'success',
      data: GamebaseData(moves: []),
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
    return GamebaseSearchQueryResponse(
      status: 'success',
      data: fenGamesRows,
      metadata: const GamebasePaginationMetadata(pageNumber: 0, pageSize: 1),
    );
  }
}

Future<ProviderContainer> _pumpPanelWithEditorPosition(
  WidgetTester tester,
  _FakeGamebaseRepository repository,
) async {
  final container = ProviderContainer(
    overrides: [gamebaseRepositoryProvider.overrideWithValue(repository)],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const Scaffold(body: MoveStatisticsPanel());
          },
        ),
      ),
    ),
  );

  // What the Board workspace does when the editor's Analyze returns a FEN.
  container
      .read(gamebaseExplorerProvider.notifier)
      .setPosition(_editorEndgameFen, startingFen: _editorEndgameFen);

  // Debounced fetch (200ms) + the FEN-keyed has-games follow-up.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 50));
  return container;
}

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
    testWidgets(
      'empty aggregates for a custom-start FEN fall back to the FEN-keyed '
      'games endpoint instead of claiming no games match',
      (tester) async {
        final repository = _FakeGamebaseRepository(
          fenGamesRows: const [
            {'id': 'g1'},
          ],
        );
        final container = await _pumpPanelWithEditorPosition(
          tester,
          repository,
        );

        expect(find.text('No games match this position'), findsNothing);
        expect(
          find.text('No move statistics for this position'),
          findsOneWidget,
        );
        expect(find.text('View games'), findsOneWidget);
        expect(repository.fenGamesRequests, greaterThan(0));

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
