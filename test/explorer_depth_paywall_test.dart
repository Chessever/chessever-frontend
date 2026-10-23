import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_depth_access.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/utils/explorer_access_depth.dart';
import 'package:chessever2/screens/gamebase/widgets/board_opening_explorer_panel.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Najdorf with O-O-O: ply 20 is the position after 10...bxc6, the last one a
/// reader without Premium sees; ply 21 is after 11.Be3.
const _najdorf =
    '1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 '
    '6. Bg5 e6 7. Qd2 Be7 8. O-O-O O-O 9. f3 Nc6 10. Nxc6 bxc6 '
    '11. Be3 d5 12. Kb1';

/// Morphy's Opera Game: captures, checks, O-O-O and mate in 33 plies.
const _operaGame =
    '1. e4 e5 2. Nf3 d6 3. d4 Bg4 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 '
    '7. Qb3 Qe7 8. Nc3 c6 9. Bg5 b5 10. Nxb5 cxb5 11. Bxb5+ Nbd7 '
    '12. O-O-O Rd8 13. Rxd7 Rxd7 14. Rd1 Qe6 15. Bxd7+ Nxd7 16. Qb8+ Nxb8 '
    '17. Rd8# 1-0';

/// A Board Editor endgame: counters claim move 1, the pieces say otherwise.
const _editorEndgameFen = '8/8/8/4k3/8/4K3/4P3/8 w - - 0 1';

/// Same position as [_editorEndgameFen], counters stripped the way a pasted
/// FEN or a deep link can arrive.
const _editorEndgameNoCounters = '8/8/8/4k3/8/4K3/4P3/8 w - -';

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
  _FakeGamebaseRepository()
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

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
    final position = Position.setupPosition(Rule.chess, Setup.parseFen(fen));
    final first = position.legalMoves.entries.first;
    final move = NormalMove(from: first.key, to: first.value.squares.first);
    return GamebaseResponse(
      status: 'success',
      data: GamebaseData(
        moves: [
          MoveAggregate(
            uci: move.uci,
            white: 40,
            black: 30,
            draws: 30,
            total: 100,
          ),
        ],
      ),
    );
  }

  static const _empty = GamebaseSearchQueryResponse(
    status: 'success',
    data: [],
    metadata: GamebasePaginationMetadata(pageNumber: 0, pageSize: 20),
  );

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
  }) async => _empty;

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
  }) async => _empty;
}

/// Premium access the test flips, as a watched ad or a purchase would.
final _premium = StateProvider<bool>((_) => false);

final _lockFinder = find.text('Explorer past move 10 is Premium');
final _tableFinder = find.text('Results');

Future<ProviderContainer> _pumpBoardExplorer(
  WidgetTester tester, {
  required String currentFen,
  required String startingFen,
  required List<String> lineUcis,
}) async {
  final container = ProviderContainer(
    overrides: [
      gamebaseRepositoryProvider.overrideWithValue(_FakeGamebaseRepository()),
      boardSettingsProviderNew.overrideWith(_TestBoardSettings.new),
      engineSettingsProviderNew.overrideWith(_TestEngineSettings.new),
      explorerDepthUnlockedProvider.overrideWith((ref) => ref.watch(_premium)),
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
                currentFen: currentFen,
                startingFen: startingFen,
                lineUcis: lineUcis,
                onMoveSelected: (_) {},
              ),
            );
          },
        ),
      ),
    ),
  );
  // Position sync (microtask), debounced fetch (200ms), games warm-up.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 200));
  return container;
}

Future<void> _teardown(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Explorer depth rule', () {
    test('the whole 10th move is open, the 11th is Premium', () {
      expect(explorerPlyLocked(19), isFalse);
      expect(explorerPlyLocked(20), isFalse, reason: 'after 10...Black');
      expect(explorerPlyLocked(21), isTrue, reason: 'after 11.White');

      expect(explorerNextStepLocked(19), isFalse, reason: "Black's 10th");
      expect(explorerNextStepLocked(20), isTrue, reason: "White's 11th");
    });

    test('a game played from the start is measured at its real depth', () {
      for (final pgn in [_najdorf, _operaGame]) {
        final game = ChessGame.fromPgn('t', pgn);
        expect(explorerMinimumPliesToReach(Chess.initial.fen), 0);
        for (var i = 0; i < game.mainline.length; i++) {
          final ply = i + 1;
          final fen = game.mainline[i].fen;
          final counterless = fen.split(' ').take(4).join(' ');
          expect(
            explorerMinimumPliesToReach(fen),
            lessThanOrEqualTo(ply),
            reason: 'bound never passes the real depth (ply $ply)',
          );
          expect(explorerAccessPly(treePly: ply, fen: fen), ply);
          // A dropped tree or stripped counters never let a real position
          // read shallower than the pieces prove, and never deeper than it is.
          expect(
            explorerAccessPly(treePly: 0, fen: counterless),
            lessThanOrEqualTo(ply),
          );
          expect(explorerAccessPly(treePly: 0, fen: fen), ply);
        }
      }
    });

    test('a dropped tree falls back to the FEN counters', () {
      final game = ChessGame.fromPgn('t', _najdorf);
      expect(
        explorerPlyLocked(
          explorerAccessPly(treePly: 0, fen: game.mainline[20].fen),
        ),
        isTrue,
      );
      expect(
        explorerPlyLocked(
          explorerAccessPly(treePly: 0, fen: game.mainline[19].fen),
        ),
        isFalse,
      );
    });

    test('a set-up endgame is deep whatever its counters claim', () {
      expect(explorerMinimumPliesToReach(_editorEndgameFen), greaterThan(20));
      expect(
        explorerPlyLocked(
          explorerAccessPly(treePly: 0, fen: _editorEndgameNoCounters),
        ),
        isTrue,
      );
    });

    test('a Chess960 start is move 1, not a set-up position', () {
      const chess960 =
          'bbqnnrkr/pppppppp/8/8/8/8/PPPPPPPP/BBQNNRKR w KQkq - 0 1';
      expect(explorerMinimumPliesToReach(chess960), 0);
      expect(explorerAccessPly(treePly: 0, fen: chess960), 0);
    });

    test('unreadable input is not treated as deep', () {
      expect(explorerMinimumPliesToReach(''), 0);
      expect(explorerMinimumPliesToReach('not a fen'), 0);
      expect(explorerAccessPly(treePly: 3, fen: ''), 3);
    });
  });

  group('Explorer notifier depth', () {
    late ProviderContainer container;
    late GamebaseExplorerNotifier notifier;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          gamebaseRepositoryProvider.overrideWithValue(
            _FakeGamebaseRepository(),
          ),
        ],
      );
      container.listen(gamebaseExplorerProvider, (_, __) {});
      notifier = container.read(gamebaseExplorerProvider.notifier);
    });
    tearDown(() => container.dispose());

    test('a board line counts every ply, castling included', () {
      final game = ChessGame.fromPgn('t', _najdorf);
      for (final ply in [20, 21]) {
        notifier.setPositionWithMoves(
          game.mainline[ply - 1].fen,
          game.mainline.take(ply).map((m) => m.uci).toList(),
          startingFen: Chess.initial.fen,
        );
        expect(notifier.accessPly, ply);
      }
    });

    test('a Board Editor endgame is past move 10', () {
      notifier.setPosition(_editorEndgameFen, startingFen: _editorEndgameFen);
      expect(explorerPlyLocked(notifier.accessPly), isTrue);
    });
  });

  group('Board explorer panel without Premium', () {
    final game = ChessGame.fromPgn('t', _najdorf);
    List<String> line(int plies) =>
        game.mainline.take(plies).map((m) => m.uci).toList();

    testWidgets('shows the table through the end of move 10', (tester) async {
      final container = await _pumpBoardExplorer(
        tester,
        currentFen: game.mainline[19].fen,
        startingFen: Chess.initial.fen,
        lineUcis: line(20),
      );
      expect(_tableFinder, findsOneWidget);
      expect(_lockFinder, findsNothing);
      await _teardown(tester, container);
    });

    testWidgets('locks the table after move 10', (tester) async {
      final container = await _pumpBoardExplorer(
        tester,
        currentFen: game.mainline[20].fen,
        startingFen: Chess.initial.fen,
        lineUcis: line(21),
      );
      expect(_lockFinder, findsOneWidget);
      expect(_tableFinder, findsNothing);
      expect(
        find.byKey(const ValueKey('opening_explorer_sort_games')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('explorer_depth_unlock')),
        findsOneWidget,
      );
      await _teardown(tester, container);
    });

    testWidgets('locks a set-up position that claims move 1', (tester) async {
      final container = await _pumpBoardExplorer(
        tester,
        currentFen: _editorEndgameFen,
        startingFen: _editorEndgameFen,
        lineUcis: const [],
      );
      expect(_lockFinder, findsOneWidget);
      expect(_tableFinder, findsNothing);
      await _teardown(tester, container);
    });

    testWidgets('opens the table as soon as Premium lands', (tester) async {
      final container = await _pumpBoardExplorer(
        tester,
        currentFen: game.mainline[20].fen,
        startingFen: Chess.initial.fen,
        lineUcis: line(21),
      );
      expect(_lockFinder, findsOneWidget);

      container.read(_premium.notifier).state = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_lockFinder, findsNothing);
      expect(_tableFinder, findsOneWidget);

      // Access ending (the ad's time running out) locks it again.
      container.read(_premium.notifier).state = false;
      await tester.pump();
      expect(_lockFinder, findsOneWidget);
      await _teardown(tester, container);
    });
  });
}
