import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('board player row scorecard tap is limited to rendered player name', () {
    final source = File(
      'lib/screens/chessboard/widgets/player_first_row_detail_widget.dart',
    ).readAsStringSync();

    expect(source, contains('Future<void> openPlayerScoreCard() async'));
    expect(source, contains('final tappableName = GestureDetector('));
    expect(source, contains('onTap: openPlayerScoreCard'));
    // The tap box is the label itself: as wide as the rendered name (a name
    // too wide fades at the space's edge), never wider than that space.
    expect(
      source,
      contains(
        'child: ConstrainedBox(\n'
        '                    constraints: BoxConstraints(maxWidth: maxNameTapWidth),\n'
        '                    child: nameWidget,',
      ),
    );
    expect(
      source,
      contains(
        'return SizedBox(\n      height: playerView == PlayerView.gridView ? 20.h : null',
      ),
    );
    expect(
      source,
      isNot(contains('return GestureDetector(\n      onTap: () async {')),
    );
  });
}
