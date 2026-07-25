import 'package:chessever2/screens/gamebase/utils/explorer_games_paging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The inline explorer games strip must behave like a page strip: every rest
/// position puts exactly one whole card against the panel's top edge — the
/// edge right under the board's bottom player row.

void main() {
  group('page metrics', () {
    // Card chrome and gap are passed explicitly so the maths is not tied to
    // whatever device ResponsiveHelper happens to be initialised with.
    const chrome = 70.0;
    const gap = 8.0;

    ExplorerGamesPageMetrics? metricsFor(double pageHeight) =>
        resolveExplorerGamesPageMetrics(
          pageHeight: pageHeight,
          navClearance: 110,
          preferredBoardSize: 124,
          minimumBoardSize: 84,
          chromeHeight: chrome,
          gap: gap,
        );

    test('keeps the preferred board when the panel is roomy', () {
      final metrics = metricsFor(400);
      expect(metrics, isNotNull);
      expect(metrics!.boardSize, 124);
      expect(metrics.cardHeight, 124 + chrome);
      expect(metrics.pageExtent, 124 + chrome + gap);
    });

    test('shrinks the board so one whole card still clears the nav', () {
      const pageHeight = 300.0;
      final metrics = metricsFor(pageHeight);
      expect(metrics, isNotNull);
      expect(metrics!.boardSize, lessThan(124));
      // The whole card sits above the translucent nav, with the gap to spare.
      expect(metrics.cardHeight, lessThanOrEqualTo(pageHeight - 110 - gap));
    });

    test('gives up rather than page to a card that cannot be seen whole', () {
      expect(metricsFor(240), isNull);
    });

    test('bottom reserve puts maxScrollExtent on the last aligned page', () {
      const pageHeight = 400.0;
      const cardCount = 5;
      final metrics = metricsFor(pageHeight)!;
      final padding = explorerGamesListBottomPadding(
        pageHeight: pageHeight,
        pageExtent: metrics.pageExtent,
        navClearance: 110,
      );

      // Content above the strip, then the strip itself, then the reserve.
      const above = 260.0;
      final content = above + cardCount * metrics.pageExtent + padding;
      final maxScrollExtent = content - pageHeight;

      expect(
        maxScrollExtent,
        closeTo(above + (cardCount - 1) * metrics.pageExtent, 0.001),
      );
    });
  });

  group('snap target', () {
    const anchor = 200.0;
    const extent = 180.0;

    double? target(double pixels, double velocity) => explorerGamesSnapTarget(
      pixels: pixels,
      velocity: velocity,
      velocityTolerance: 50,
      anchor: anchor,
      pageExtent: extent,
      pageCount: 5,
      minScrollExtent: 0,
      maxScrollExtent: anchor + 4 * extent,
    );

    test('a slow release falls back to the nearest card', () {
      expect(target(anchor + 40, 0), anchor);
      expect(target(anchor + 150, 0), anchor + extent);
    });

    test('a flick moves exactly one card, never several', () {
      expect(target(anchor + 10, 3000), anchor + extent);
      expect(target(anchor + extent - 10, -3000), anchor);
    });

    test('leaves the move table to ordinary list physics', () {
      expect(target(0, 0), isNull);
      expect(target(anchor - extent, -2000), isNull);
    });

    test('catches a fling that came out of the move table', () {
      // Just under the strip and moving into it — this one is ours.
      expect(target(anchor - 40, 2000), anchor);
    });

    test('never targets past the last card', () {
      expect(target(anchor + 4 * extent - 5, 3000), anchor + 4 * extent);
    });
  });

  group('the top of the list stays reachable', () {
    // A position with only a couple of moves puts the strip barely below the
    // top of the list. Snapping must not drag those rows out of reach.
    double? target(double pixels, double velocity) => explorerGamesSnapTarget(
      pixels: pixels,
      velocity: velocity,
      velocityTolerance: 50,
      anchor: 80,
      pageExtent: 180,
      pageCount: 3,
      minScrollExtent: 0,
      maxScrollExtent: 80 + 2 * 180,
    );

    test('a release near the top settles at the top, not on the first card', () {
      expect(target(0, 0), 0);
      expect(target(20, 0), 0);
    });

    test('past the halfway point the first card wins', () {
      expect(target(60, 0), 80);
    });

    test('a flick down still takes the first card', () {
      expect(target(10, 2000), 80);
    });
  });

  testWidgets('the list settles on a card boundary, never between two', (
    tester,
  ) async {
    const anchor = 200.0;
    const extent = 180.0;
    const cardCount = 5;
    const viewport = 300.0;

    final config =
        ExplorerGamesSnapConfig()..update(
          anchor: anchor,
          pageExtent: extent,
          pageCount: cardCount,
        );
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: viewport,
              child: ListView(
                controller: controller,
                physics: ExplorerGamesSnapPhysics(config: config),
                padding: const EdgeInsets.only(bottom: viewport - extent),
                children: [
                  // Stands in for the move table above the strip.
                  const SizedBox(height: anchor),
                  for (var i = 0; i < cardCount; i++)
                    const SizedBox(height: extent),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final grid = [for (var i = 0; i < cardCount; i++) anchor + i * extent];

    // A lazy list only *estimates* its extent from the children it has built,
    // so walk to the bottom before checking that the reserve lands the end of
    // the list exactly on the last card's aligned offset.
    for (var i = 0; i < cardCount; i++) {
      final before = controller.position.maxScrollExtent;
      controller.jumpTo(before);
      await tester.pumpAndSettle();
      if ((controller.position.maxScrollExtent - before).abs() < 0.5) break;
    }
    expect(controller.position.maxScrollExtent, closeTo(grid.last, 0.5));

    // A flick from a resting card lands on the next one.
    controller.jumpTo(anchor);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, -120), 900);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(anchor + extent, 0.5));

    // A short drag that is released without speed falls back to the card it
    // came from rather than resting part-way.
    await tester.drag(find.byType(ListView), const Offset(0, -35));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(anchor + extent, 0.5));

    // Backwards behaves the same.
    await tester.fling(find.byType(ListView), const Offset(0, 120), 900);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(anchor, 0.5));
  });

  // The strip is a plain Column, so nothing unmounts the cards the reader
  // cannot see. This window is what stops ten cards rating ten positions.
  group('eval window', () {
    const anchor = 200.0;
    const cardHeight = 200.0;
    const pageExtent = 208.0; // card + 8pt gap
    // Card tops: 0 → 200, 1 → 408, 2 → 616, 3 → 824.

    ExplorerGamesEvalWindow windowAt(
      double pixels, {
      double viewportHeight = 260,
      int cardCount = 4,
      bool settled = true,
      double? anchorOverride = anchor,
    }) => resolveExplorerGamesEvalWindow(
      anchor: anchorOverride,
      pixels: pixels,
      viewportHeight: viewportHeight,
      pageExtent: pageExtent,
      cardHeight: cardHeight,
      cardCount: cardCount,
      settled: settled,
    );

    test('a resting page evaluates that card alone', () {
      expect(
        windowAt(anchor),
        const ExplorerGamesEvalWindow(first: 0, last: 0, settled: true),
      );
      expect(
        windowAt(anchor + pageExtent),
        const ExplorerGamesEvalWindow(first: 1, last: 1, settled: true),
      );
    });

    test('the sliver of the next card peeking in does not evaluate', () {
      // Card 1 shows 52 of its 200pt under the resting card 0.
      expect(windowAt(anchor).contains(1), isFalse);
    });

    test('a taller panel evaluates every card it really shows', () {
      // 500pt of viewport: cards 0 and 1 whole, 84pt of card 2.
      expect(
        windowAt(anchor, viewportHeight: 500),
        const ExplorerGamesEvalWindow(first: 0, last: 1, settled: true),
      );
    });

    test('nothing evaluates while the reader is up in the move table', () {
      // The first card peeks 60pt above the bottom edge — not worth an engine.
      expect(windowAt(0).isEmpty, isTrue);
      expect(windowAt(0), const ExplorerGamesEvalWindow.none());
    });

    test('a panel shorter than half a card still rates the card it shows', () {
      final window = windowAt(anchor + 20, viewportHeight: 80);
      expect(window.contains(0), isTrue);
    });

    test('the window never runs past the cards that exist', () {
      final window = windowAt(anchor, viewportHeight: 5000, cardCount: 3);
      expect(window.last, 2);
    });

    test('no strip, no window', () {
      expect(windowAt(anchor, anchorOverride: null).isEmpty, isTrue);
      expect(windowAt(anchor, cardCount: 0).isEmpty, isTrue);
    });

    test('mid-scroll the window still resolves, but unsettled', () {
      final window = windowAt(anchor, settled: false);
      expect(window.contains(0), isTrue);
      expect(window.settled, isFalse);
    });
  });

  group('page resting at the top', () {
    const anchor = 400.0;
    const extent = 200.0;

    int? pageAt(double pixels, {int pageCount = 5}) => explorerGamesPageAtTop(
      pixels: pixels,
      anchor: anchor,
      pageExtent: extent,
      pageCount: pageCount,
    );

    test('reports the card the panel top is showing', () {
      expect(pageAt(anchor), 0);
      expect(pageAt(anchor + extent), 1);
      expect(pageAt(anchor + extent * 3), 3);
    });

    test('a card only just short of its page still counts as that card', () {
      // The pin fires while the card is a few points shy of flush; rounding up
      // to the next one here is exactly the bug this guards.
      expect(pageAt(anchor - 8), 0);
      expect(pageAt(anchor + extent - 8), 1);
    });

    test('offsets up in the move table belong to nobody', () {
      expect(pageAt(anchor - extent), isNull);
      expect(pageAt(anchor - extent / 2 - 1), isNull);
    });

    test('never names a card that does not exist', () {
      expect(pageAt(anchor + extent * 99, pageCount: 3), 2);
      expect(pageAt(anchor, pageCount: 0), isNull);
    });
  });
}
