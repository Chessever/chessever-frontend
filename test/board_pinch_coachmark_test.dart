import 'package:chessever2/screens/chessboard/widgets/board_pinch_coachmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pinch hint leaves the board touchable and can be dismissed', (
    tester,
  ) async {
    var boardTaps = 0;
    var dismissals = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 320,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      key: const ValueKey('board'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => boardTaps++,
                    ),
                  ),
                  Positioned.fill(
                    child: BoardPinchCoachmark(
                      onDismiss: () => dismissals++,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Pinch to resize the board'), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('board'))));
    expect(boardTaps, 1);
    await tester.tap(find.byKey(const ValueKey('dismiss_board_pinch_coachmark')));
    expect(dismissals, 1);
  });
}
