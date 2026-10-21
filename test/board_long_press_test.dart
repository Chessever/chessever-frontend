import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_stream.dart';
import 'package:chessever2/screens/chessboard/widgets/board_game_menu_host.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_context_menu.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = 320.0;
const _hold = Duration(milliseconds: 600);

void main() {
  late ChessboardController controller;
  late List<Move> moves;
  late List<LongPressStartDetails> holds;

  setUp(() {
    final position = Chess.initial;
    controller = ChessboardController(
      game: GameData(
        fen: position.fen,
        playerSide: PlayerSide.both,
        sideToMove: Side.white,
        validMoves: position.legalMoves.map(
          (key, value) => MapEntry(key, value.squares.toSet()),
        ),
      ),
    );
    moves = [];
    holds = [];
  });

  Future<void> board(
    WidgetTester tester, {
    bool menu = true,
    Side orientation = Side.white,
    PieceShiftMethod method = PieceShiftMethod.tapTwoSquares,
    GestureLongPressStartCallback? onHold,
    GestureDragUpdateCallback? onHorizontalDragUpdate,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GestureDetector(
            onHorizontalDragUpdate: onHorizontalDragUpdate,
            child: Chessboard(
              size: _size,
              controller: controller,
              orientation: orientation,
              settings: ChessboardSettings(
                pieceShiftMethod: method,
                drawShape: const DrawShapeOptions(enable: true),
              ),
              onLongPress: menu ? (onHold ?? holds.add) : null,
              onMove: (move, {viaDragAndDrop}) => moves.add(move),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Offset square(WidgetTester tester, Square square, {bool flipped = false}) {
    final origin = tester.getTopLeft(find.byType(Chessboard));
    return origin +
        Offset(
          ((flipped ? 7 - square.file : square.file) + .5) * _size / 8,
          ((flipped ? square.rank : 7 - square.rank) + .5) * _size / 8,
        );
  }

  Future<void> clean(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  }

  for (final target in [Square.e2, Square.e4]) {
    testWidgets('stationary hold opens once on $target and consumes release', (
      tester,
    ) async {
      await board(tester);
      final point = square(tester, target);
      final gesture = await tester.startGesture(point);
      await tester.pump(_hold);
      expect(holds, hasLength(1));
      expect(holds.single.globalPosition, point);
      await tester.pump(_hold);
      await gesture.up();
      expect(holds, hasLength(1));
      expect(moves, isEmpty);
      await clean(tester);
    });
  }

  testWidgets('holding a legal destination never commits a selected piece', (
    tester,
  ) async {
    await board(tester);
    await tester.tapAt(square(tester, Square.e2));
    final gesture = await tester.startGesture(square(tester, Square.e4));
    expect(moves, isEmpty);
    await tester.pump(_hold);
    await gesture.up();
    expect(holds, hasLength(1));
    expect(moves, isEmpty);
    // Selection was consumed: the next empty-square tap cannot move the pawn.
    await tester.tapAt(square(tester, Square.e4));
    expect(moves, isEmpty);
    await clean(tester);
  });

  testWidgets('ordinary tap move commits once on release', (tester) async {
    await board(tester);
    await tester.tapAt(square(tester, Square.e2));
    final gesture = await tester.startGesture(square(tester, Square.e4));
    expect(moves, isEmpty);
    await gesture.up();
    expect(moves.single.uci, 'e2e4');
    expect(holds, isEmpty);
    await clean(tester);
  });

  testWidgets(
    'without callback, upstream pointer-down move timing is preserved',
    (tester) async {
      await board(tester, menu: false);
      await tester.tapAt(square(tester, Square.e2));
      final gesture = await tester.startGesture(square(tester, Square.e4));
      expect(moves.single.uci, 'e2e4');
      await tester.pump(_hold);
      await gesture.up();
      expect(holds, isEmpty);
      await clean(tester);
    },
  );

  testWidgets('a swipe cancels both the hold and deferred tap destination', (
    tester,
  ) async {
    await board(tester);
    await tester.tapAt(square(tester, Square.e2));
    final gesture = await tester.startGesture(square(tester, Square.e4));
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump(_hold);
    await gesture.up();
    expect(holds, isEmpty);
    expect(moves, isEmpty);
    await clean(tester);
  });

  for (final recognized in [false, true]) {
    testWidgets(
      'parent swipe is blocked only after hold recognition ($recognized)',
      (tester) async {
        var parentDrags = 0;
        await board(tester, onHorizontalDragUpdate: (_) => parentDrags++);
        final gesture = await tester.startGesture(square(tester, Square.e4));
        await tester.pump(
          recognized ? _hold : const Duration(milliseconds: 100),
        );
        await gesture.moveBy(const Offset(80, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump();
        await gesture.up();
        expect(holds, hasLength(recognized ? 1 : 0));
        expect(parentDrags, recognized ? 0 : greaterThan(0));
        expect(moves, isEmpty);
        await clean(tester);
      },
    );
  }

  testWidgets('second pointer cancels hold and retains two-finger drawing', (
    tester,
  ) async {
    await board(tester);
    final first = await tester.startGesture(
      square(tester, Square.a4),
      pointer: 1,
    );
    await tester.pump(const Duration(milliseconds: 200));
    final second = await tester.startGesture(
      square(tester, Square.b4),
      pointer: 2,
    );
    await second.moveTo(square(tester, Square.c4));
    await tester.pump(_hold);
    await second.up();
    await first.up();
    expect(holds, isEmpty);
    // ignore: invalid_use_of_internal_member
    expect(controller.drawnShapes, hasLength(1));
    expect(moves, isEmpty);
    await clean(tester);
  });

  testWidgets('piece drag cancels hold and still commits a move', (
    tester,
  ) async {
    await board(tester, method: PieceShiftMethod.either);
    final gesture = await tester.startGesture(square(tester, Square.e2));
    await gesture.moveTo(square(tester, Square.e4));
    await tester.pump(_hold);
    await gesture.up();
    expect(holds, isEmpty);
    expect(moves.single.uci, 'e2e4');
    await clean(tester);
  });

  testWidgets(
    'cancel, orientation, position, and disposal cancel pending holds',
    (tester) async {
      await board(tester);
      var gesture = await tester.startGesture(square(tester, Square.e2));
      await gesture.cancel();
      await tester.pump(_hold);
      expect(holds, isEmpty);

      gesture = await tester.startGesture(square(tester, Square.e2));
      await board(tester, orientation: Side.black);
      await tester.pump(_hold);
      await gesture.up();
      expect(holds, isEmpty);

      gesture = await tester.startGesture(
        square(tester, Square.e2, flipped: true),
      );
      final next = Chess.initial.playUnchecked(Move.parse('e2e4')!);
      controller.updatePosition(
        GameData(
          fen: next.fen,
          playerSide: PlayerSide.both,
          sideToMove: next.turn,
          validMoves: next.legalMoves.map(
            (key, value) => MapEntry(key, value.squares.toSet()),
          ),
        ),
        animate: false,
      );
      await tester.pump(_hold);
      await gesture.up();
      expect(holds, isEmpty);

      gesture = await tester.startGesture(
        square(tester, Square.e4, flipped: true),
      );
      await clean(tester);
      await tester.pump(_hold);
      await gesture.up();
      expect(holds, isEmpty);
    },
  );

  testWidgets('same-position controller refresh does not cancel a hold', (
    tester,
  ) async {
    await board(tester);
    final gesture = await tester.startGesture(square(tester, Square.e4));
    await tester.pump(const Duration(milliseconds: 250));
    controller.updatePosition(controller.game, animate: false);
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.up();
    expect(holds, hasLength(1));
    expect(moves, isEmpty);
    await clean(tester);
  });

  testWidgets('menu dismissal cannot move the board underneath', (
    tester,
  ) async {
    late BuildContext menuContext;
    var opened = 0;
    await board(
      tester,
      onHold: (details) {
        opened++;
        showMenu<String>(
          context: menuContext,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            0,
            0,
          ),
          items: const [
            PopupMenuItem(value: 'flip', child: Text('Flip Board')),
          ],
        );
      },
    );
    menuContext = tester.element(find.byType(Chessboard));
    await tester.tapAt(square(tester, Square.e2));
    final gesture = await tester.startGesture(square(tester, Square.e4));
    await tester.pump(_hold);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(opened, 1);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Flip Board'), findsNothing);
    expect(moves, isEmpty);
    await clean(tester);
  });

  testWidgets(
    'menu lists flip without video and respects export and analysis state',
    (tester) async {
      List<PopupMenuEntry<String>> entries = [];
      Future<void> pump({bool export = true, bool cleared = false}) =>
          tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [AppColors.dark],
              ),
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  entries = chessBoardContextMenuItems(
                    context,
                    videoSession: null,
                    analysisCleared: cleared,
                    allowCopyPgn: export,
                  );
                  return Material(
                    child: ExcludeSemantics(child: Column(children: entries)),
                  );
                },
              ),
            ),
          );
      await pump();
      expect(find.text('Flip Board'), findsOneWidget);
      expect(find.text('Copy PGN'), findsOneWidget);
      expect(find.text('Clear Analysis'), findsOneWidget);
      expect(entries.whereType<PopupMenuItem<String>>().map((e) => e.value), [
        'flip_board',
        'watch',
        'board_settings',
        'share',
        'copy_pgn',
        'clear_analysis',
      ]);
      await pump(export: false, cleared: true);
      expect(find.text('Copy PGN'), findsNothing);
      expect(find.text('Restore Analysis'), findsOneWidget);
      expect(find.text('Clear Analysis'), findsNothing);
      await clean(tester);
    },
  );

  testWidgets('stream actions follow visibility without removing Flip Board', (
    tester,
  ) async {
    final session = EventVideoSession(repository: null)
      ..selected = EventVideoStream(
        id: 'stream',
        label: 'Live',
        source: VideoSource.parse(
          'https://www.youtube.com/watch?v=abcdefghijk',
        ),
      );
    addTearDown(session.dispose);
    Future<void> pump() => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Material(
              child: ExcludeSemantics(
                child: Column(
                  children: chessBoardContextMenuItems(
                    context,
                    videoSession: session,
                    analysisCleared: false,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await pump();
    expect(find.text('Close Stream'), findsOneWidget);
    expect(find.text('Flip Board'), findsOneWidget);
    session.toggle();
    await pump();
    expect(find.text('Show Stream'), findsOneWidget);
    expect(find.text('Close Stream'), findsNothing);
    expect(find.text('Flip Board'), findsOneWidget);
    await clean(tester);
  });

  testWidgets('mounted adjacent pages route menu calls to their own actions', (
    tester,
  ) async {
    final calls = <String>[];
    final controllers = <BoardGameMenuController>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            for (final id in ['first', 'second'])
              BoardGameMenuHost(
                child: Builder(
                  builder: (context) {
                    final host = BoardGameMenuHost.maybeOf(context)!;
                    host.attach(id, (_) => calls.add(id));
                    controllers.add(host);
                    return const SizedBox();
                  },
                ),
              ),
          ],
        ),
      ),
    );
    controllers[1].showAt(Offset.zero);
    controllers[0].showAt(Offset.zero);
    expect(calls, ['second', 'first']);
    // A stale endpoint cannot detach its replacement.
    controllers[0].attach('replacement', (_) => calls.add('replacement'));
    controllers[0].detach('first');
    controllers[0].showAt(Offset.zero);
    expect(calls.last, 'replacement');
    controllers[0].detach('replacement');
    controllers[0].showAt(Offset.zero);
    expect(calls, hasLength(3));
    await clean(tester);
  });

  test('tablet popup stays inside safe bounds near every edge', () {
    for (final point in [
      Offset.zero,
      const Offset(1000, 10),
      const Offset(1000, 700),
      const Offset(0, 700),
    ]) {
      final delegate = BoardMenuPositionDelegate(
        anchor: point,
        padding: const EdgeInsets.fromLTRB(8, 32, 8, 24),
      );
      const viewport = Size(1024, 768);
      final constraints = delegate.getConstraintsForChild(
        BoxConstraints.tight(viewport),
      );
      expect(constraints.maxWidth, 280);
      const child = Size(220, 400);
      final position = delegate.getPositionForChild(viewport, child);
      expect(
        position.dx,
        inInclusiveRange(8, viewport.width - child.width - 8),
      );
      expect(
        position.dy,
        inInclusiveRange(32, viewport.height - child.height - 24),
      );
    }
    expect(
      const BoardMenuPositionDelegate(
            anchor: Offset.zero,
            padding: EdgeInsets.all(8),
          )
          .getConstraintsForChild(BoxConstraints.tight(const Size(600, 200)))
          .maxHeight,
      184,
    );
  });
}
