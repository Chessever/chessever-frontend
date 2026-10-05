// The board's swipe explorer shows a position's games strip as soon as the
// games page answers, which can be before the move statistics do. Past the
// indexed window those statistics come back empty, and the panel used to
// answer that by re-asking the same position through the FEN endpoint: the
// cards reloaded under a reader already walking one of them, and the focused
// card lost the bottom-nav arrows.
import 'dart:async';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_game_focus_provider.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/widgets/board_opening_explorer_panel.dart';
import 'package:chessever2/screens/gamebase/widgets/explorer_game_card.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A real game, long enough to stand past the indexed aggregate window.
const _pgn =
    '1. e4 c5 2. Nf3 e6 3. d4 cxd4 4. Nxd4 Nc6 5. Nc3 Qc7 6. Be3 a6 '
    '7. Qf3 Nf6 8. O-O-O h5 9. Nxc6 dxc6 10. h3 b5 11. e5 Nd5 12. Bf4 Bb7 '
    '13. Nxd5 cxd5 14. Bd3 Rc8 15. Kb1 Be7 16. Rhg1 g6 17. Rc1 Qc6 18. g4 h4 '
    '19. Rge1 Qc7 20. Bd2 Bc6 21. Qe2 Qb7 22. f4 d4 23. f5 gxf5 24. gxf5 Bd5 '
    '25. Qg4 Qb6 26. Be4 Qc6 27. fxe6 fxe6 28. Bg6+ Kd7 29. Qxd4 Qc4 0-1';

/// Move 23 to play: past the window, with a continuation left to walk.
const _ply = 44;

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _EngineSettings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async =>
      const EngineSettings(showEngineAnalysis: false);
}

class _Repo extends GamebaseRepository {
  _Repo({required this.continuation})
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  final List<String> continuation;

  /// Holds the statistics answer back, as a slow deep position does.
  final Completer<void> aggregatesGate = Completer<void>();
  int lineGamesRequests = 0;
  int fenGamesRequests = 0;

  GamebaseSearchQueryResponse _page(List<String> ids, int pageSize) {
    return GamebaseSearchQueryResponse(
      status: 'success',
      data: [
        for (final id in ids)
          <String, dynamic>{
            'id': id,
            'white': 'W $id',
            'black': 'B $id',
            'result': '1-0',
            'date': '2024-05-12',
            'continuation': continuation,
          },
      ],
      metadata: GamebasePaginationMetadata(
        pageNumber: 0,
        pageSize: pageSize,
        totalCount: ids.length,
        hasMoreValue: false,
      ),
    );
  }

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
    await aggregatesGate.future;
    return GamebaseResponse(
      status: 'success',
      data: GamebaseData(moves: const <MoveAggregate>[]),
    );
  }

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
    lineGamesRequests++;
    return _page(const ['line-1', 'line-2'], pageSize);
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
    return _page(const ['fen-1', 'fen-2'], pageSize);
  }

  @override
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async => null;
}

void _ignoreMove(String _) {}

/// Debounced statistics fetch, the games page's short settle, and the frames
/// each answer takes to reach the list.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'statistics landing empty do not reload a strip that is being walked',
    (tester) async {
      final game = ChessGame.fromPgn('deep', _pgn);
      final line = game.mainline
          .take(_ply)
          .map((m) => m.uci)
          .toList(growable: false);
      final repo = _Repo(
        continuation: game.mainline
            .skip(_ply)
            .take(4)
            .map((m) => m.uci)
            .toList(growable: false),
      );
      final container = ProviderContainer(
        overrides: [
          gamebaseRepositoryProvider.overrideWithValue(repo),
          boardSettingsProviderNew.overrideWith(_BoardSettings.new),
          engineSettingsProviderNew.overrideWith(_EngineSettings.new),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: BoardOpeningExplorerPanel(
                    currentFen: game.mainline[_ply - 1].fen,
                    startingFen: Chess.initial.fen,
                    lineUcis: line,
                    onMoveSelected: _ignoreMove,
                  ),
                );
              },
            ),
          ),
        ),
      );

      // The games page answers while the statistics are still out.
      await _settle(tester);
      expect(container.read(gamebaseExplorerProvider).isLoading, isTrue);
      expect(find.byType(ExplorerGameCard), findsNWidgets(2));
      expect(find.text('W line-1'), findsOneWidget);
      expect(repo.fenGamesRequests, 0);

      // The reader starts walking the first card.
      final card = tester.widget<ExplorerGameCard>(
        find.byType(ExplorerGameCard).first,
      );
      container
          .read(explorerFocusedGameProvider.notifier)
          .focus(
            gameId: card.game.gameId,
            anchorFen: card.anchorFen,
            sans: card.line.sans,
            fens: card.line.fens,
          );
      container.read(explorerFocusedGameProvider.notifier).forward();
      await tester.pump();
      expect(container.read(explorerFocusedGameProvider)?.ply, 1);

      // Now the statistics land, empty, past the indexed window.
      repo.aggregatesGate.complete();
      await tester.pump();
      await _settle(tester);
      final explorer = container.read(gamebaseExplorerProvider);
      expect(explorer.isLoading, isFalse);
      expect(explorer.moveAggregates, isEmpty);

      // Same cards, same request, same focus.
      expect(repo.fenGamesRequests, 0);
      expect(repo.lineGamesRequests, 1);
      expect(find.text('W line-1'), findsOneWidget);
      expect(find.byType(ExplorerGameCard), findsNWidgets(2));
      final focus = container.read(explorerFocusedGameProvider);
      expect(focus?.gameId, card.game.gameId);
      expect(focus?.ply, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
}
