import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

/// The opponent scorecard sheet is expensive enough that its first frame used
/// to outlast a curve-driven transition, so the sheet appeared at its resting
/// place instead of travelling there. [MotionSheetRoute] holds the slide until
/// that frame is done, then springs the sheet in and back out.
void main() {
  const sheetKey = ValueKey('sheet-body');
  const sheetHeight = 400.0;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MotionSheetRoute<void>(
                        builder:
                            (_) => const Sheet(
                              child: SizedBox(
                                key: sheetKey,
                                height: sheetHeight,
                                width: double.infinity,
                                child: ColoredBox(color: Color(0xFF202020)),
                              ),
                            ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // The sheet is built (and measured off-stage) on the frame the push
    // schedules; the frame after it is the first one that renders.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  double topOf(WidgetTester tester) => tester.getRect(find.byKey(sheetKey)).top;

  double screenHeightOf(WidgetTester tester) =>
      tester.view.physicalSize.height / tester.view.devicePixelRatio;

  testWidgets('first rendered frame still has the sheet fully off-screen', (
    tester,
  ) async {
    await open(tester);

    // If the transition clock ran during the build frame, a card that takes
    // longer to build than the spring takes to run would show up here already
    // at (or near) its resting place - the jump this route exists to prevent.
    expect(topOf(tester), greaterThanOrEqualTo(screenHeightOf(tester)));

    await tester.pumpAndSettle();
  });

  testWidgets('springs in without skipping and settles exactly at rest', (
    tester,
  ) async {
    await open(tester);

    final offscreenTop = topOf(tester);
    final restingTop = screenHeightOf(tester) - sheetHeight;
    final travel = offscreenTop - restingTop;

    var previous = offscreenTop;
    var moved = false;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final top = topOf(tester);
      // Monotone: a spring this side of critically damped never backs up.
      expect(top, lessThanOrEqualTo(previous + 0.01));
      // No frame swallows most of the travel, which is what a skipped
      // transition looks like from the outside.
      expect(previous - top, lessThan(travel * 0.5));
      moved = moved || top < previous;
      previous = top;
    }
    expect(moved, isTrue);

    await tester.pumpAndSettle();
    // Critically damped and snapped to the end: no overshoot above the resting
    // top, which on a tall sheet would lift its bottom edge off the screen,
    // and no fractional gap left behind by a spring that never quite arrives.
    expect(topOf(tester), moreOrLessEquals(restingTop, epsilon: 0.01));
  });

  testWidgets('exit leaves rest immediately instead of stalling', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();

    final restingTop = topOf(tester);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();

    // A spring-shaped curve played backwards sits still for most of the
    // timeline and then drops; the reverse simulation has to accelerate away
    // from rest at once, the way the entrance accelerates towards it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(topOf(tester), greaterThan(restingTop + 20));

    await tester.pumpAndSettle();
    expect(find.byKey(sheetKey), findsNothing);
  });
}
