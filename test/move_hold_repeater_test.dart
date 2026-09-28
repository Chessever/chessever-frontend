import 'dart:async';

import 'package:chessever2/screens/chessboard/utils/move_hold_repeater.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_navbar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'holding visits every intermediate move and speeds up gradually',
    (tester) async {
      final visited = <int>[];
      final hold = MoveHoldRepeater();
      addTearDown(hold.stop);
      hold.start(() {
        visited.add(visited.length + 1);
        return MoveHoldStep.moved;
      });
      await tester.pump(const Duration(milliseconds: 150));
      expect(visited, [1]);
      await tester.pump(const Duration(milliseconds: 450));
      expect(visited, [1, 2, 3, 4]);
      await tester.pump(const Duration(milliseconds: 120));
      expect(visited.last, 5);
      await tester.pump(const Duration(milliseconds: 360));
      expect(visited.last, 8);
      await tester.pump(const Duration(milliseconds: 90));
      expect(visited.last, 9);
      await tester.pump(const Duration(milliseconds: 270));
      expect(visited.last, 12);
      await tester.pump(const Duration(milliseconds: 75));
      expect(visited.last, 13);
      hold.stop();
      await tester.pump(const Duration(seconds: 1));
      expect(visited.last, 13);
    },
  );

  testWidgets('a busy step keeps the hold alive until navigation is ready', (
    tester,
  ) async {
    var busy = true;
    var moves = 0;
    final hold = MoveHoldRepeater();
    addTearDown(hold.stop);
    hold.start(() {
      if (busy) return MoveHoldStep.waiting;
      moves++;
      return MoveHoldStep.moved;
    });
    await tester.pump(const Duration(milliseconds: 450));
    expect(moves, 0);
    expect(hold.isActive, isTrue);
    busy = false;
    await tester.pump(const Duration(milliseconds: 150));
    expect(moves, 1);
    hold.stop();
  });

  testWidgets(
    'slow async steps are serialized and release prevents more work',
    (tester) async {
      var calls = 0;
      final pending = Completer<MoveHoldStep>();
      final hold = MoveHoldRepeater();
      addTearDown(hold.stop);
      hold.start(() {
        calls++;
        return pending.future;
      });
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 1);
      hold.stop();
      pending.complete(MoveHoldStep.moved);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 1);
      expect(hold.isActive, isFalse);
    },
  );

  testWidgets('an old in-flight hold cannot stop a new direction', (
    tester,
  ) async {
    final old = Completer<MoveHoldStep>();
    var backwards = 0;
    final hold = MoveHoldRepeater();
    addTearDown(hold.stop);
    hold.start(() => old.future);
    await tester.pump(const Duration(milliseconds: 150));
    hold.start(() {
      backwards++;
      return MoveHoldStep.moved;
    });
    old.complete(MoveHoldStep.end);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(backwards, 1);
    expect(hold.isActive, isTrue);
    hold.stop();
  });

  testWidgets('reaching the boundary stops once without another move', (
    tester,
  ) async {
    var moves = 0;
    var ends = 0;
    final hold = MoveHoldRepeater(onEnd: () => ends++);
    addTearDown(hold.stop);
    hold.start(() {
      if (moves == 3) return MoveHoldStep.end;
      moves++;
      return MoveHoldStep.moved;
    });
    await tester.pump(const Duration(seconds: 2));
    expect(moves, 3);
    expect(ends, 1);
    expect(hold.isActive, isFalse);
  });

  for (final cancel in [false, true]) {
    testWidgets(
      'phone arrow walks moves while held and stops on ${cancel ? 'cancel' : 'release'}',
      (tester) async {
        var moves = 0;
        final hold = MoveHoldRepeater();
        addTearDown(hold.stop);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 80,
                      height: 60,
                      child: ChessSvgBottomNavbarWithLongPress(
                        key: const ValueKey('forward'),
                        svgPath: 'assets/svgs/right_arrows.svg',
                        width: 80,
                        onPressed: () => moves++,
                        onLongPressStart: () => hold.start(() {
                          moves++;
                          return MoveHoldStep.moved;
                        }),
                        onLongPressEnd: hold.stop,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('forward')));
        await tester.pump();
        expect(moves, 1, reason: 'A regular tap remains a single step.');
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('forward'))),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 150));
        expect(moves, 2);
        await tester.pump(const Duration(milliseconds: 300));
        expect(moves, 4, reason: 'The pointer visits each move, not the end.');
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pump();
        final afterRelease = moves;
        await tester.pump(const Duration(seconds: 1));
        expect(moves, afterRelease);
        expect(hold.isActive, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
