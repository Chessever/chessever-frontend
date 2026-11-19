import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every Feed page is the whole screen, one post to a page, so nothing of
/// the next post shows under it. The post uses the whole of it: the board
/// as large as the screen allows, the zone (chart, scrub line, caption and
/// the rail) under it, and the height the board cannot take spread through
/// the post, never left as one empty band.
void main() {
  // Phone and tablet widths, the Feed viewport heights they give (the screen
  // less the bars and the insets), and the text sizes Feed allows.
  const widths = [360.0, 375.0, 393.0, 402.0, 412.0, 430.0, 440.0, 820.0];
  const scales = [1.0, 1.12, 1.3, 1.4];

  FeedLayout resolve(double width, double height, double scale) =>
      FeedLayout.resolve(
        BoxConstraints(maxWidth: width, maxHeight: height),
        TextScaler.linear(scale),
        evalWidth: 20 * width / 393,
      );

  test('a post fills its page exactly, on every screen and text size', () {
    for (final width in widths) {
      for (final scale in scales) {
        for (var height = 480.0; height <= 1200; height += 7.5) {
          final l = resolve(width, height, scale);
          final why = '$width x $height at ${scale}x';
          // Everything stacked, the zone and the foot under it: the page, to
          // the point, with nothing hanging over.
          if (l.board > FeedLayout.minBoard) {
            expect(l.zoneBottom + l.foot, closeTo(height, 1e-6), reason: why);
          }
          // Every gap at least its least.
          expect(l.top, greaterThanOrEqualTo(FeedLayout.topGap), reason: why);
          expect(
            l.zoneSpace,
            greaterThanOrEqualTo(FeedLayout.zoneGap),
            reason: why,
          );
          expect(l.foot, greaterThanOrEqualTo(0), reason: why);
          // The board block stays one block, whatever the spare.
          expect(
            l.boardTop - l.top,
            closeTo(l.rowHeight + FeedLayout.gap, 1e-9),
            reason: why,
          );
          expect(
            l.deckTop - l.boardBottom,
            closeTo(FeedLayout.gap + l.rowHeight, 1e-9),
            reason: why,
          );
          // The zone holds its left column and the rail, both inside it.
          expect(
            l.scrubTop + FeedLayout.scrubHeight,
            lessThanOrEqualTo(l.captionTop + 1e-6),
            reason: why,
          );
          expect(l.captionTop + l.captionHeight, closeTo(l.zoneBottom, 1e-9));
          expect(l.railTop, greaterThanOrEqualTo(l.zoneTop - 1e-9));
          expect(l.railTop + l.railHeight, closeTo(l.zoneBottom, 1e-9));
        }
      }
    }
  });

  test('the rail stands at the board column\'s right edge, clear of the '
      'left column, and never over the board', () {
    for (final width in widths) {
      for (final scale in scales) {
        for (var height = 480.0; height <= 1200; height += 15) {
          final l = resolve(width, height, scale);
          final why = '$width x $height at ${scale}x';
          expect(
            l.railLeft + FeedLayout.railWidth,
            closeTo(l.contentRight, 1e-9),
            reason: why,
          );
          expect(
            l.leftColumnRight + FeedLayout.railGap,
            closeTo(l.railLeft, 1e-9),
            reason: why,
          );
          // Ranks 1 and 2 and the h-file stay playable: nothing of the zone
          // reaches the board.
          expect(l.zoneTop, greaterThan(l.boardBottom), reason: why);
          expect(l.contentLeft, greaterThanOrEqualTo(FeedLayout.boardGutter));
          expect(
            l.contentRight,
            lessThanOrEqualTo(width - FeedLayout.boardGutter + 1e-9),
            reason: why,
          );
          // Every rail cell is a full target.
          expect(l.railCell, greaterThanOrEqualTo(44));
        }
      }
    }
  });

  test('no gap grows into a band: each stays under its cap', () {
    for (final width in widths) {
      for (final scale in scales) {
        for (var height = 480.0; height <= 1200; height += 7.5) {
          final l = resolve(width, height, scale);
          final why = '$width x $height at ${scale}x';
          expect(
            l.zoneSpace - FeedLayout.zoneGap,
            lessThanOrEqualTo(30.001),
            reason: why,
          );
          // Past every cap the post stands centred: what is over goes
          // evenly above and under it.
          final spare =
              (l.top - FeedLayout.topGap) +
              (l.zoneSpace - FeedLayout.zoneGap) +
              l.foot;
          if (spare > 110) {
            expect(
              l.top - FeedLayout.topGap - 36,
              closeTo(l.foot - 36, 1e-6),
              reason: why,
            );
          }
        }
      }
    }
  });

  test('the base phone: a 357pt board on 8pt gutters, the rail beside the '
      'chart, the caption at the foot', () {
    // The Feed page on an iPhone 15 in the home shell: 852 less the top bar
    // (139) and the dock's slot (78).
    final l = resolve(393, 635, 1);
    expect(l.board, 357);
    expect(l.contentLeft, FeedLayout.boardGutter);
    expect(l.contentRight, 393 - FeedLayout.boardGutter);
    expect(l.railLeft, 329);
    expect(l.leftColumnWidth, 313);
    expect(l.railCell, FeedLayout.railCellMin);
    // Chart, scrub line, caption: 118 + 44 + 44.
    expect(l.zoneHeight, 206);
    expect(l.graphHeight, 118);
    // Stacked to the page's foot, the little spare spread over it.
    expect(l.zoneBottom + l.foot, closeTo(635, 1e-9));
    expect(l.deckTop, closeTo(l.top + 24 + 4 + 357 + 4 + 24, 1e-9));
  });

  test(
    'where the board is bound by the height there is no spare to spread',
    () {
      // A short screen: the board gives way, the gaps stay at their least.
      final l = resolve(393, 560, 1);
      expect(l.board, lessThan(393 - 2 * FeedLayout.boardGutter - 20));
      expect(l.top, FeedLayout.topGap);
      expect(l.zoneSpace, FeedLayout.zoneGap);
      expect(l.foot, 0);
      // The column is centred on the screen, the rail with it.
      expect(l.contentLeft, closeTo((393 - l.contentWidth) / 2, 1e-9));
    },
  );

  test('the natural height is the post with a full-width board', () {
    for (final width in widths) {
      for (final scale in scales) {
        final scaler = TextScaler.linear(scale);
        final natural = FeedLayout.naturalHeight(
          width,
          scaler,
          evalWidth: 20 * width / 393,
        );
        final l = resolve(width, natural, scale);
        expect(
          l.board,
          (width - 2 * FeedLayout.boardGutter - 20 * width / 393)
              .floorToDouble(),
        );
        expect(l.foot, closeTo(0, 1e-6));
      }
    }
  });

  test('the spread on its own: nothing for nothing, every point placed', () {
    expect(FeedLayout.spread(0), (top: 0.0, zone: 0.0, foot: 0.0));
    for (var spare = 1.0; spare < 400; spare += 3) {
      final s = FeedLayout.spread(spare);
      expect(s.top + s.zone + s.foot, closeTo(spare, 1e-9));
    }
  });
}
