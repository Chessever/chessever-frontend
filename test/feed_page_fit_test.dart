import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every Feed page is the whole screen, one post to a page, so nothing of
/// the next post shows under it. The height a post does not need is spread
/// through it, never left as one empty band.
void main() {
  // Phone and tablet widths, the Feed viewport heights they give (the screen
  // less the bar and the insets), and the text sizes Feed allows.
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
          // Everything stacked, the scrub row and the foot under it: the
          // page, to the point, with nothing hanging over.
          final bottom = l.scrubTop + FeedLayout.scrubHeight + l.foot;
          if (l.board > FeedLayout.minBoard) {
            expect(bottom, closeTo(height, 1e-6), reason: why);
          }
          // Every gap at least its least.
          expect(l.top, greaterThanOrEqualTo(FeedLayout.topGap), reason: why);
          expect(
            l.infoSpace,
            greaterThanOrEqualTo(FeedLayout.infoGap),
            reason: why,
          );
          expect(
            l.actionsSpace,
            greaterThanOrEqualTo(FeedLayout.actionsGap),
            reason: why,
          );
          expect(
            l.scrubSpace,
            greaterThanOrEqualTo(FeedLayout.minSpacer),
            reason: why,
          );
          expect(l.foot, greaterThanOrEqualTo(0), reason: why);
          // The header and the board stay one block, whatever the spare.
          expect(
            l.boardTop - l.top - l.metaHeight,
            closeTo(FeedLayout.gap + l.rowHeight + FeedLayout.gap, 1e-9),
            reason: why,
          );
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
            l.infoSpace - FeedLayout.infoGap,
            lessThanOrEqualTo(30.001),
            reason: why,
          );
          expect(
            l.actionsSpace - FeedLayout.actionsGap,
            lessThanOrEqualTo(18.001),
            reason: why,
          );
          expect(
            l.scrubSpace - FeedLayout.minSpacer,
            lessThanOrEqualTo(36.001),
            reason: why,
          );
          // Past every cap the post stands centred: what is over goes
          // evenly above the header and under the scrub line.
          if (l.foot > 0) {
            final spare =
                (l.top - FeedLayout.topGap) +
                (l.infoSpace - FeedLayout.infoGap) +
                (l.actionsSpace - FeedLayout.actionsGap) +
                (l.scrubSpace - FeedLayout.minSpacer) +
                l.foot;
            final share = (spare * 0.30).clamp(0.0, 36.0);
            expect(
              l.top - FeedLayout.topGap - share,
              closeTo(l.foot, 1e-6),
              reason: why,
            );
          }
        }
      }
    }
  });

  test('the spread keeps its shape: top, strip, actions, scrub line', () {
    // The Feed viewport on an iPhone 15: 852 less the insets and the bar.
    final l = resolve(393, 687, 1);
    final spare = 687 - FeedLayout.naturalHeight(393, TextScaler.noScaling);
    expect(spare, greaterThan(40));
    // Every point of it is used, none of it past the scrub line.
    expect(l.foot, 0);
    expect(l.top - FeedLayout.topGap, closeTo(spare * 0.30, 1e-6));
    expect(l.infoSpace - FeedLayout.infoGap, closeTo(spare * 0.25, 1e-6));
    expect(l.actionsSpace - FeedLayout.actionsGap, closeTo(spare * 0.15, 1e-6));
    expect(l.scrubSpace - FeedLayout.minSpacer, closeTo(spare * 0.30, 1e-6));
    // The strip and the actions stay closer to each other than to anything
    // else: they are one group.
    expect(l.actionsSpace, lessThan(l.infoSpace));
    expect(l.actionsSpace, lessThan(l.scrubSpace));
  });

  test(
    'where the board is bound by the height there is no spare to spread',
    () {
      // A short screen: the board gives way, the gaps stay at their least.
      final l = resolve(393, 560, 1);
      expect(l.board, lessThan(393 - 2 * FeedLayout.sidePadding - 20));
      expect(l.top, FeedLayout.topGap);
      expect(l.infoSpace, FeedLayout.infoGap);
      expect(l.actionsSpace, FeedLayout.actionsGap);
      expect(l.scrubSpace, FeedLayout.minSpacer);
      expect(l.foot, 0);
    },
  );

  test('a puzzle, with no scrub line, fills its page too: no band under its '
      'buttons, and they end where a game post ends', () {
    for (final width in widths) {
      for (final scale in scales) {
        for (var height = 480.0; height <= 1200; height += 7.5) {
          final l = resolve(width, height, scale);
          if (l.board <= FeedLayout.minBoard) continue;
          final why = '$width x $height at ${scale}x';
          // The puzzle page, top to bottom, as feed_puzzle.dart stacks it.
          final actionsBottom =
              l.scrublessTop +
              l.metaHeight +
              FeedLayout.gap +
              l.rowHeight +
              FeedLayout.gap +
              l.board +
              FeedLayout.gap +
              l.rowHeight +
              l.scrublessInfoSpace +
              l.infoHeight +
              l.scrublessActionsSpace +
              l.actionsHeight;
          expect(
            actionsBottom + l.scrublessFoot,
            closeTo(height, 1e-6),
            reason: why,
          );
          // What is left under the buttons is the part of a game page's
          // scrub row under its line, never the line's whole room.
          expect(l.scrublessFoot - l.foot, lessThan(10), reason: why);
          // The room goes above the post and between its rows, never
          // taking a gap under its least.
          expect(l.scrublessTop, greaterThan(l.top), reason: why);
          expect(l.scrublessInfoSpace, greaterThan(l.infoSpace), reason: why);
          expect(
            l.scrublessActionsSpace,
            greaterThan(l.actionsSpace),
            reason: why,
          );
        }
      }
    }
  });

  test('the spread on its own: nothing for nothing, every point placed', () {
    expect(FeedLayout.spread(0), (
      top: 0.0,
      info: 0.0,
      actions: 0.0,
      scrub: 0.0,
      foot: 0.0,
    ));
    for (var spare = 1.0; spare < 400; spare += 3) {
      final s = FeedLayout.spread(spare);
      expect(
        s.top + s.info + s.actions + s.scrub + s.foot,
        closeTo(spare, 1e-9),
      );
    }
  });
}
