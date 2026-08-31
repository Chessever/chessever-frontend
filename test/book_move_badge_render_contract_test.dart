import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Book badge SVG is available through the Flutter asset bundle', () async {
    final svg = await rootBundle.loadString('assets/svgs/book.svg');

    expect(svg, contains('<svg'));
    expect(svg, contains('viewBox="0 0 56 56"'));
  });

  test('board classification badge gives the SVG an explicit visible size', () {
    final source = File(
      'lib/screens/chessboard/chess_board_screen_new.dart',
    ).readAsStringSync();
    final builder = source.substring(
      source.indexOf('Positioned _buildBoardAnnotationBadge'),
      source.indexOf('/// Render any NAG',
          source.indexOf('Positioned _buildBoardAnnotationBadge')),
    );

    expect(builder, contains('annotation.type.iconAssetPath'));
    expect(builder, contains('final badgeSize = widget.size / 8 * 0.40'));
    expect(
      builder,
      contains('width: badgeSize'),
      reason: 'BookMove has no positive text symbol; its SVG must be sized visibly.',
    );
    expect(builder, contains('height: badgeSize'));
  });
}
