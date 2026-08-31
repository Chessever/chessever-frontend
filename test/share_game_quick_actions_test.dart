import 'package:chessever2/screens/chessboard/widgets/share_game_card_overlay.dart';
import 'package:chessever2/widgets/icons/fen_position_icon.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Share Game quick row offers FEN instead of PGN', () {
    expect(shareGameQuickActionLabels, [
      'Share Image',
      'Share GIF',
      'Copy FEN',
    ]);
    expect(shareGameQuickActionLabels, isNot(contains('Copy PGN')));
  });

  test('Copy FEN preserves the exact visible position', () {
    const visibleFen = '8/8/8/3k4/8/4K3/8/8 w - - 12 48';

    expect(sharePositionFenForClipboard('  $visibleFen\n'), visibleFen);
  });

  testWidgets('Copy FEN uses an accessible queen-on-f7 board icon', (
    tester,
  ) async {
    expect(FenPositionIcon.queenSquare, Square.f7);

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: FenPositionIcon(size: 20, color: Colors.black)),
      ),
    );

    expect(find.bySemanticsLabel('Queen on f7 board position'), findsOneWidget);
    expect(tester.getSize(find.byType(FenPositionIcon)), const Size.square(20));
  });
}
