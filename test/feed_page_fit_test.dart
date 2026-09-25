import 'dart:math' as math;

import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feed's pages are one post tall, so the next post peeks in under the
/// current one. Where that peek ends is part of the design: in a gap between
/// the next post's rows, or well into its board, never through a row and
/// never a sliver of squares along the screen's bottom edge.
void main() {
  // Phone and tablet widths, the Feed viewport heights they give (the screen
  // less the bar and the insets), and the text sizes Feed allows.
  const widths = [360.0, 375.0, 393.0, 402.0, 412.0, 430.0, 440.0, 820.0];
  const scales = [1.0, 1.12, 1.3, 1.4];

  test('the peek never ends through a row or a sliver into the next board', () {
    for (final width in widths) {
      final evalWidth = 20 * width / 393;
      for (final scale in scales) {
        final scaler = TextScaler.linear(scale);
        for (var viewport = 480.0; viewport <= 1200; viewport += 0.5) {
          final fit = FeedLayout.pageFit(
            width,
            viewport,
            scaler,
            evalWidth: evalWidth,
          );
          final natural = FeedLayout.naturalHeight(
            width,
            scaler,
            evalWidth: evalWidth,
          );
          final why = '$width x $viewport at ${scale}x';
          // The post itself is laid out exactly as before; the foot is the
          // only thing added, and only ever a little.
          expect(fit.foot, greaterThanOrEqualTo(0), reason: why);
          expect(
            fit.extent - fit.foot,
            closeTo(natural.clamp(viewport * 0.5, viewport), 1e-6),
            reason: why,
          );
          expect(fit.extent, lessThanOrEqualTo(viewport + 1e-6), reason: why);

          final peek = viewport - fit.extent;
          if (peek <= 0) continue;
          final next = FeedLayout.resolve(
            BoxConstraints(maxWidth: width, maxHeight: fit.extent - fit.foot),
            scaler,
            evalWidth: evalWidth,
          );
          // The board: none of it, or at least half a square.
          final shown = peek - next.boardTop;
          expect(
            shown <= 0 ||
                shown >= math.max(16.0, next.board / 16) - 1e-6 ||
                peek >= next.boardBottom,
            isTrue,
            reason: '$why: ${shown.toStringAsFixed(1)}pt of the next board',
          );
          // The player row over it: all of its names and flags, or none.
          final rowTop = FeedLayout.topGap + next.metaHeight + FeedLayout.gap;
          final inkTop = rowTop + 3;
          final inkBottom = rowTop + next.rowHeight - 3;
          expect(
            peek <= inkTop || peek >= inkBottom,
            isTrue,
            reason: '$why: the peek ends at $peek, through the player row',
          );
        }
      }
    }
  });

  test('on the 393x852 class the peek stops just above the next board', () {
    const scaler = TextScaler.noScaling;
    // The Feed viewport on an iPhone 15: 852 less the insets and the bar.
    final fit = FeedLayout.pageFit(393, 687, scaler);
    final next = FeedLayout.resolve(
      BoxConstraints(maxWidth: 393, maxHeight: fit.extent - fit.foot),
      scaler,
    );
    final peek = 687 - fit.extent;
    expect(peek, lessThan(next.boardTop));
    expect(peek, greaterThan(next.boardTop - FeedLayout.gap));
    // What that costs: a few points of foot under the scrub line.
    expect(fit.foot, lessThan(8));
  });

  test('a screen that shows a real piece of the next board keeps it', () {
    const scaler = TextScaler.noScaling;
    // Pro Max class: about one square of the next board shows.
    final fit = FeedLayout.pageFit(430, 764, scaler);
    expect(fit.foot, 0);
  });
}
