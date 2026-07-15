import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/utils/engine_pv_palette.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/engine_pv_layouts.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_eval_provider.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _initialFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _pvLines = <ExplorerPvLine>[
  ExplorerPvLine(
    evaluation: 0.3,
    sanMoves: ['e4', 'e5', 'Nf3'],
    uciMoves: ['e2e4', 'e7e5', 'g1f3'],
  ),
  ExplorerPvLine(
    evaluation: 0.2,
    sanMoves: ['d4', 'd5', 'c4'],
    uciMoves: ['d2d4', 'd7d5', 'c2c4'],
  ),
  ExplorerPvLine(
    evaluation: 0.1,
    sanMoves: ['Nf3', 'd5', 'g3'],
    uciMoves: ['g1f3', 'd7d5', 'g2g3'],
  ),
];

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
    return const GamebaseResponse(
      status: 'success',
      data: GamebaseData(moves: []),
    );
  }
}

class _SubscribedNotifier extends SubscriptionNotifier {
  _SubscribedNotifier() : super() {
    state = SubscriptionState(isSubscribed: true);
  }
}

class _CardEngineSettingsNotifier extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async {
    const settings = EngineSettings(
      showEngineAnalysis: true,
      engineLinesView: EngineLinesView.cards,
      principalVariationIndex: 2,
    );
    state = const AsyncValue.data(settings);
    return settings;
  }
}

class _BoardSettingsNotifier extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async {
    const settings = BoardSettingsNew(useFigurine: false);
    state = const AsyncValue.data(settings);
    return settings;
  }
}

class _FixedExplorerEvalNotifier extends ExplorerEvalNotifier {
  _FixedExplorerEvalNotifier(super.ref) {
    _restoreLines(_initialFen);
  }

  void _restoreLines(String fen) {
    state = ExplorerEvalState(
      evaluation: _pvLines.first.evaluation,
      depth: 18,
      isEvaluating: false,
      fen: fen,
      pvLines: _pvLines,
    );
  }

  @override
  void setEngineEnabled({
    required bool enabled,
    required String fen,
    bool force = false,
  }) {
    if (enabled) {
      if (state.pvPreview == null) _restoreLines(fen);
      return;
    }
    state = state.copyWith(isEvaluating: false, clearPvPreview: true);
  }

  @override
  Future<void> evaluatePosition(String fen, {bool force = false}) async {
    if (state.pvPreview == null) _restoreLines(fen);
  }

  @override
  void clearPvPreview({bool resumeEvaluation = true}) {
    super.clearPvPreview(resumeEvaluation: false);
  }
}

ProviderContainer _createContainer() {
  return ProviderContainer(
    overrides: [
      gamebaseRepositoryProvider.overrideWithValue(_FakeGamebaseRepository()),
      subscriptionProvider.overrideWith((ref) => _SubscribedNotifier()),
      engineSettingsProviderNew.overrideWith(_CardEngineSettingsNotifier.new),
      boardSettingsProviderNew.overrideWith(_BoardSettingsNotifier.new),
      explorerEvalProvider.overrideWith(
        (ref) => _FixedExplorerEvalNotifier(ref),
      ),
    ],
  );
}

Future<void> _pumpExplorer(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const GamebaseExplorerScreen();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Explorer cards use ranked colors and move taps drive locked navigation',
    (tester) async {
      final container = _createContainer();
      var containerDisposed = false;
      void disposeContainer() {
        if (containerDisposed) return;
        containerDisposed = true;
        container.dispose();
      }

      addTearDown(disposeContainer);
      await _pumpExplorer(tester, container);

      final cards = tester.widget<EnginePvCardsView>(
        find.byType(EnginePvCardsView),
      );
      expect(cards.items, hasLength(3));
      expect(cards.items.map((item) => item.accentColor).toList(), [
        enginePvVariantColor(0, isSelected: true),
        enginePvVariantColor(1, isSelected: true),
        enginePvVariantColor(2, isSelected: true),
      ]);

      final baseState = container.read(gamebaseExplorerProvider);
      final baseGame = baseState.game;
      final basePointer = List<int>.of(baseState.movePointer);

      final secondMoveTarget = tester.widget<GestureDetector>(
        find.byKey(const ValueKey<String>('opening_explorer_pv_move_0_1')),
      );
      secondMoveTarget.onTap!();
      await tester.pump();

      var preview = container.read(explorerEvalProvider).pvPreview;
      expect(preview, isNotNull);
      expect(preview!.moveIndex, 1);
      expect(preview.currentMove.uci, 'e7e5');
      expect(container.read(gamebaseExplorerProvider).currentFen, _initialFen);
      expect(container.read(gamebaseExplorerProvider).game, same(baseGame));
      expect(container.read(gamebaseExplorerProvider).movePointer, basePointer);
      var board = tester.widget<Chessboard>(find.byType(Chessboard));
      expect(board.controller.fen, preview.currentFen);
      expect(board.controller.interactive, isFalse);

      var bottomNav = tester.widget<ChessBoardBottomNavBar>(
        find.byType(ChessBoardBottomNavBar),
      );
      expect(bottomNav.canMoveBackward, isTrue);
      expect(bottomNav.canMoveForward, isTrue);
      bottomNav.onRightMove!();
      await tester.pump();

      preview = container.read(explorerEvalProvider).pvPreview;
      expect(preview!.moveIndex, 2);
      expect(preview.currentMove.uci, 'g1f3');
      bottomNav = tester.widget<ChessBoardBottomNavBar>(
        find.byType(ChessBoardBottomNavBar),
      );
      expect(bottomNav.canMoveForward, isFalse);
      expect(bottomNav.canMoveBackward, isTrue);

      bottomNav.onLeftMove!();
      await tester.pump();
      expect(container.read(explorerEvalProvider).pvPreview?.moveIndex, 1);

      final dismiss = tester.widget<InkWell>(
        find.byKey(
          const ValueKey<String>('opening_explorer_pv_preview_dismiss'),
        ),
      );
      dismiss.onTap!();
      await tester.pump();

      expect(container.read(explorerEvalProvider).pvPreview, isNull);
      expect(container.read(gamebaseExplorerProvider).currentFen, _initialFen);
      expect(container.read(gamebaseExplorerProvider).game, same(baseGame));
      expect(container.read(gamebaseExplorerProvider).movePointer, basePointer);
      board = tester.widget<Chessboard>(find.byType(Chessboard));
      expect(board.controller.fen, _initialFen);
      expect(board.controller.interactive, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      disposeContainer();
      await tester.pump();
    },
  );
}
