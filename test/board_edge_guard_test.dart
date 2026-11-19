import 'package:chessever2/screens/chessboard/board_edge_guard.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A page over a home route, its lower half a "board" at the screen's edge
/// that reads raw pointers like chessground does, and holds a long press.
Future<(NavigatorState, List<Offset>, ValueNotifier<int>)> _pumpBoard(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.iOS,
}) async {
  final moves = <Offset>[];
  final longPresses = ValueNotifier<int>(0);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: ThemeData(platform: platform),
      home: const Scaffold(body: Text('home')),
    ),
  );
  navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: Column(
          children: [
            const SizedBox(height: 300, child: Text('app bar')),
            Expanded(
              child: BoardEdgeGuard(
                child: GestureDetector(
                  onLongPress: () => longPresses.value++,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerMove: (event) => moves.add(event.position),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (navigator.currentState!, moves, longPresses);
}

Future<void> _dragFrom(WidgetTester tester, Offset start) async {
  final gesture = await tester.startGesture(start);
  // Most of the screen's width: past the half a back swipe needs to pop
  // with no fling.
  for (var i = 0; i < 50; i++) {
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump(const Duration(milliseconds: 8));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a piece dragged from the board\'s edge never swipes the '
      'page back', (tester) async {
    final (navigator, moves, _) = await _pumpBoard(tester);
    await _dragFrom(tester, const Offset(6, 450));
    expect(navigator.canPop(), isTrue);
    expect(find.text('app bar'), findsOneWidget);
    // The board still had every move.
    expect(moves.length, 50);
  });

  testWidgets('a swipe from the edge off the board still goes back', (
    tester,
  ) async {
    final (navigator, _, _) = await _pumpBoard(tester);
    await _dragFrom(tester, const Offset(6, 150));
    expect(navigator.canPop(), isFalse);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a finger held on the board\'s edge keeps its long press', (
    tester,
  ) async {
    final (_, _, longPresses) = await _pumpBoard(tester);
    final gesture = await tester.startGesture(const Offset(6, 450));
    await gesture.moveBy(const Offset(2, 1));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(longPresses.value, 1);
  });

  testWidgets('where the platform has no back swipe, nothing is claimed', (
    tester,
  ) async {
    final (_, _, _) = await _pumpBoard(
      tester,
      platform: TargetPlatform.android,
    );
    expect(find.byType(RawGestureDetector), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(BoardEdgeGuard),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is RawGestureDetector &&
              widget.gestures.containsKey(BoardEdgeClaim),
        ),
      ),
      findsNothing,
    );
  });
}
