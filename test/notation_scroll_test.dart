import 'package:chessever2/screens/chessboard/widgets/notation_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final axis in Axis.values) {
    testWidgets('move following preserves board offset with $axis notation', (
      tester,
    ) async {
      final board = ScrollController();
      final notation = ScrollController();
      final move = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: board,
              child: Column(
                children: [
                  const SizedBox(height: 700, child: Text('Board and video')),
                  SizedBox(
                    height: 150,
                    child: SingleChildScrollView(
                      controller: notation,
                      scrollDirection: axis,
                      child: Flex(
                        direction: axis,
                        children: [
                          const SizedBox(width: 1000, height: 1000),
                          SizedBox(
                            key: move,
                            width: 60,
                            height: 40,
                            child: const Text('Latest move'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 500),
                ],
              ),
            ),
          ),
        ),
      );
      for (final offset in [0.0, 180.0]) {
        board.jumpTo(offset);
        notation.jumpTo(0);
        scrollNotationToMove(notation, move.currentContext!);
        await tester.pumpAndSettle();
        expect(notation.offset, greaterThan(0));
        expect(board.offset, offset);
      }
      await tester.pumpWidget(const SizedBox());
      board.dispose();
      notation.dispose();
    });
  }
}
