import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChessTitleUtils.normalize', () {
    test('a feed placeholder is no title, not a badge', () {
      // DGT LiveChess and the FIDE relay write `-` for a title they do not
      // know; `?` is PGN's own unknown. Both used to fall through to
      // "preserve unknown titles as-is" and render as a badge.
      for (final raw in ['-', '--', '?', ' - ', '_', '/']) {
        expect(ChessTitleUtils.normalize(raw), '', reason: 'raw: "$raw"');
      }
    });

    test('known and long-form titles still normalise', () {
      expect(ChessTitleUtils.normalize('gm'), 'GM');
      expect(ChessTitleUtils.normalize('Woman Grandmaster'), 'WGM');
      expect(ChessTitleUtils.normalize('International Master'), 'IM');
    });

    test('an unknown real value is preserved', () {
      expect(ChessTitleUtils.normalize('NM'), 'NM');
    });
  });
}
