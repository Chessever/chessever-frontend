import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notation never renders the pasted-position reset button', () {
    final source =
        File(
          'lib/screens/chessboard/chess_board_screen_new.dart',
        ).readAsStringSync();

    expect(source, isNot(contains("tooltip: 'Reset to pasted position'")));
    expect(source, isNot(contains('Icons.restart_alt_rounded')));
  });
}
