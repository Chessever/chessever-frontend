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

  group('ChessTitleUtils.gameTimeTitle', () {
    test("the game's own tag beats today's title", () {
      // An IM in 2014 who is a GM today.
      expect(
        ChessTitleUtils.gameTimeTitle(
          {'WhiteTitle': 'IM', 'BlackTitle': 'GM'},
          isWhite: true,
          fallback: 'GM',
        ),
        'IM',
      );
    });

    test('a tag for the opponent only means untitled then', () {
      expect(
        ChessTitleUtils.gameTimeTitle(
          {'BlackTitle': 'GM'},
          isWhite: true,
          fallback: 'GM',
        ),
        '',
      );
    });

    test('no title tags keep the fallback title', () {
      expect(
        ChessTitleUtils.gameTimeTitle(
          {'White': 'Kasparov, Garry'},
          isWhite: true,
          fallback: 'GM',
        ),
        'GM',
      );
    });

    test('relay placeholders on both sides are no tags at all', () {
      expect(
        ChessTitleUtils.gameTimeTitle(
          {'WhiteTitle': '-', 'BlackTitle': '-'},
          isWhite: false,
          fallback: 'IM',
        ),
        'IM',
      );
    });
  });

  group('ChessTitleUtils title tags in a PGN', () {
    test('only a real title counts as carrying titles', () {
      expect(
        ChessTitleUtils.pgnCarriesTitles(
          '[White "A"]\n[BlackTitle "FM"]\n\n1. e4 *',
        ),
        isTrue,
      );
      expect(
        ChessTitleUtils.pgnCarriesTitles(
          '[WhiteTitle "-"]\n[BlackTitle "?"]\n\n1. e4 *',
        ),
        isFalse,
      );
      expect(ChessTitleUtils.pgnCarriesTitles(null), isFalse);
    });

    test("saving keeps the game's tags and fills only when it has none", () {
      final tagged = <String, dynamic>{'WhiteTitle': 'IM'};
      ChessTitleUtils.fillMissingTitleTags(tagged, white: 'GM', black: 'GM');
      expect(tagged, {'WhiteTitle': 'IM'});

      final untagged = <String, dynamic>{'White': 'A'};
      ChessTitleUtils.fillMissingTitleTags(untagged, white: 'GM', black: '');
      expect(untagged, {'White': 'A', 'WhiteTitle': 'GM'});
    });
  });
}
