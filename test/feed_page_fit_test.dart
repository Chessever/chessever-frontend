import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every Feed page is the whole screen, one post to a page, so nothing of
/// the next post shows under it. The post uses the whole of it: its header
/// line at the top, the board as large as the screen allows, the zone (the
/// chart across the column, the scrub line, the rail over their right end)
/// under it, and the height the board cannot take spread through the post,
/// never left as one empty band.
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
          // Never hard on the dock: the foot keeps its least on every
          // screen, the smallest phones included.
          expect(
            l.foot,
            greaterThanOrEqualTo(FeedLayout.footGap - 1e-9),
            reason: why,
          );
          // The header leads the post, and the board block under it stays
          // one block, whatever the spare.
          expect(l.headerTop, closeTo(l.top, 1e-9), reason: why);
          expect(l.headerHeight, greaterThanOrEqualTo(44), reason: why);
          expect(
            l.boardTop - l.top,
            closeTo(l.headerHeight + l.rowHeight + FeedLayout.gap, 1e-9),
            reason: why,
          );
          expect(
            l.deckTop - l.boardBottom,
            closeTo(FeedLayout.gap + l.rowHeight, 1e-9),
            reason: why,
          );
          // The zone: the chart over the scrub line, the rail spanning
          // both, its top and foot on theirs.
          expect(l.graphTop, closeTo(l.zoneTop, 1e-9), reason: why);
          expect(
            l.scrubTop + FeedLayout.scrubHeight,
            closeTo(l.zoneBottom, 1e-9),
            reason: why,
          );
          expect(
            l.graphHeight,
            greaterThanOrEqualTo(
              FeedLayout.graphHeightFor(TextScaler.linear(scale)) - 1e-9,
            ),
            reason: why,
          );
          expect(l.railTop, closeTo(l.zoneTop, 1e-9), reason: why);
          expect(l.railTop + l.railHeight, closeTo(l.zoneBottom, 1e-9));
          expect(
            l.railCell * FeedLayout.railCells + FeedLayout.railInsets,
            closeTo(l.railHeight, 1e-9),
            reason: why,
          );
        }
      }
    }
  });

  test('the rail stands over the chart\'s right end, on the board column\'s '
      'right edge, and never over the board', () {
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
          // The chart's live parts and the scrub line keep the rail's gap.
          expect(
            l.leftColumnRight + FeedLayout.railGap,
            closeTo(l.railLeft, 1e-9),
            reason: why,
          );
          expect(
            l.contentRight - l.railReserve,
            closeTo(l.leftColumnRight, 1e-9),
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
          // Every rail cell is a full target, and the rail is one wide.
          expect(l.railCell, greaterThanOrEqualTo(44), reason: why);
          expect(FeedLayout.railWidth, greaterThanOrEqualTo(44));
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
          // evenly above and under it (the caps: 38 over, 22 under on top
          // of the foot's least).
          final spare =
              (l.top - FeedLayout.topGap) +
              (l.zoneSpace - FeedLayout.zoneGap) +
              (l.foot - FeedLayout.footGap);
          if (spare > 100) {
            expect(
              l.top - FeedLayout.topGap - 38,
              closeTo(l.foot - FeedLayout.footGap - 22, 1e-6),
              reason: why,
            );
          }
        }
      }
    }
  });

  test('the base phone: a 357pt board on 8pt gutters, the header on top, '
      'the chart across the column, the rail over its right end', () {
    // The Feed page on an iPhone 15 in the home shell: 852 less the status
    // bar (59) and the dock's slot (78). Feed has no top bar.
    final l = resolve(393, 715, 1);
    expect(l.board, 357);
    expect(l.contentLeft, FeedLayout.boardGutter);
    expect(l.contentRight, 393 - FeedLayout.boardGutter);
    // The chart is the eval bar and the board, side to side: 20 + 357.
    expect(l.contentWidth, 377);
    // The rail: one 44pt target wide, on the board's right edge.
    expect(l.railLeft, 341);
    expect(l.leftColumnWidth, 325);
    expect(l.railCell, FeedLayout.railCellMin);
    // The rail's four cells and the backing's air set the zone: 4 x 44 +
    // 0 over + 8 under. The chart takes all of it over the scrub line.
    expect(l.zoneHeight, 184);
    expect(l.graphHeight, 140);
    expect(l.headerHeight, 44);
    // Stacked to the page's foot, the spare spread over it: framed as it
    // was before the foot kept its least (about 24 over, 19 between, 25
    // under), the rail well clear of the dock.
    expect(l.zoneBottom + l.foot, closeTo(715, 1e-9));
    expect(l.top, closeTo(23.52, 1e-9));
    expect(l.zoneSpace, closeTo(FeedLayout.zoneGap + 19.04, 1e-9));
    expect(l.foot, closeTo(FeedLayout.footGap + 13.44, 1e-9));
    expect(l.deckTop, closeTo(l.top + 44 + 24 + 4 + 357 + 4 + 24, 1e-9));
  });

  test(
    'where the board is bound by the height there is no spare to spread',
    () {
      // A short screen: the board gives way, the gaps stay at their least,
      // the foot's least among them, so the rail never sits on the dock.
      final l = resolve(393, 560, 1);
      expect(l.board, lessThan(393 - 2 * FeedLayout.boardGutter - 20));
      expect(l.top, FeedLayout.topGap);
      expect(l.zoneSpace, FeedLayout.zoneGap);
      expect(l.foot, FeedLayout.footGap);
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
        expect(l.foot, closeTo(FeedLayout.footGap, 1e-6));
      }
    }
  });

  test('the smallest phones keep the foot\'s least between the rail and '
      'the dock', () {
    // Feed's page on each phone in the home shell: the screen less the
    // status bar and the dock's slot (its gap under the capsule plus the
    // 56pt capsule): 360x640 Android with gesture navigation (24 + 24,
    // slot 80) and three-button navigation (24 + 48, slot 104), the
    // 375x667 iPhone SE (20, slot 12 + 56). The page ends at the capsule's
    // top, so the foot is the air between the rail and the dock.
    for (final (width, page) in [
      (360.0, 640.0 - 24 - 80),
      (360.0, 640.0 - 24 - 104),
      (375.0, 667.0 - 20 - 68),
    ]) {
      for (final scale in scales) {
        final l = resolve(width, page, scale);
        final why = '$width x $page at ${scale}x';
        expect(l.zoneBottom + l.foot, closeTo(page, 1e-6), reason: why);
        expect(
          page - l.zoneBottom,
          greaterThanOrEqualTo(FeedLayout.footGap - 1e-9),
          reason: why,
        );
      }
    }
  });

  test('a puzzle\'s status is level with the middle of the rail\'s marks',
      () {
    for (final scale in scales) {
      final l = resolve(393, 715, scale);
      final first = l.zoneTop + FeedLayout.railInsetTop;
      expect(
        l.railCellsMiddle,
        closeTo(first + l.railCell * FeedLayout.railCells / 2, 1e-9),
      );
      expect(
        l.railLastCellTop + l.railCell + FeedLayout.railInsetBottom,
        closeTo(l.zoneBottom, 1e-9),
      );
    }
  });

  test('the spread on its own: nothing for nothing, every point placed', () {
    // The foot's least is not spare: the spread places only what is over.
    expect(FeedLayout.spread(0), (top: 0.0, zone: 0.0, foot: 0.0));
    for (var spare = 1.0; spare < 400; spare += 3) {
      final s = FeedLayout.spread(spare);
      expect(s.top + s.zone + s.foot, closeTo(spare, 1e-9));
    }
  });
}
