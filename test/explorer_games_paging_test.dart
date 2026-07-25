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
      // Every card carries its own trailing gap, so the strip is exactly
      // `cardCount * pageExtent` tall.
      const above = 260.0;
      final content = above + cardCount * metrics.pageExtent + padding;
      final maxScrollExtent = content - pageHeight;

      expect(
        maxScrollExtent,
        closeTo(above + (cardCount - 1) * metrics.pageExtent, 0.001),
      );
    });

    test('a single card still tops out flush under the player row', () {
      const pageHeight = 400.0;
      final metrics = metricsFor(pageHeight)!;
      final padding = explorerGamesListBottomPadding(
        pageHeight: pageHeight,
        pageExtent: metrics.pageExtent,
        navClearance: 110,
      );
      const above = 90.0;
      final maxScrollExtent =
          above + metrics.pageExtent + padding - pageHeight;
      expect(maxScrollExtent, closeTo(above, 0.001));
    });
  });

  group('settle page — the card a release lands on', () {
    const anchor = 200.0;
    const extent = 180.0;
    const pageCount = 5;

    int? pageFor({
      required double pixels,
      required double velocity,
      required int? restingPage,
    }) => explorerGamesSnapPage(
      pixels: pixels,
      velocity: velocity,
      velocityTolerance: 50,
      anchor: anchor,
      pageExtent: extent,
      pageCount: pageCount,
      restingPage: restingPage,
    );

    group('coming out of the move table', () {
      test('a flick down lands on the first card, whatever the speed', () {
        for (final velocity in [80.0, 400.0, 1500.0, 4000.0]) {
          expect(
            pageFor(pixels: anchor - 40, velocity: velocity, restingPage: null),
            0,
            reason: 'velocity $velocity',
          );
        }
      });

      test('a release already inside card 1 still lands on the first', () {
        // The repro: 2–3 move rows, so card 0 is painted high and a
        // normal-pace finger lets go well past it.
        expect(
          pageFor(
            pixels: anchor + extent * 0.7,
            velocity: 120,
            restingPage: null,
          ),
          0,
        );
        expect(
          pageFor(
            pixels: anchor + extent * 1.2,
            velocity: 3500,
            restingPage: null,
          ),
          0,
        );
      });

      test('a dead release past card 0 still falls back onto it', () {
        expect(
          pageFor(pixels: anchor + extent * 0.9, velocity: 0, restingPage: null),
          0,
        );
      });

      test('the last move rows stay readable just above the strip', () {
        // Released dead with card 0 still most of a card down: this is a rest
        // in the move table, not a half-hearted entry.
        expect(
          pageFor(pixels: anchor - extent * 0.6, velocity: 0, restingPage: null),
          isNull,
        );
        // Nearly there — the magnet takes it.
        expect(
          pageFor(pixels: anchor - extent * 0.1, velocity: 0, restingPage: null),
          0,
        );
      });

      test('flicking up goes back to ordinary list physics', () {
        expect(
          pageFor(pixels: anchor - 20, velocity: -2000, restingPage: null),
          isNull,
        );
      });
    });

    group('inside the strip', () {
      test('a flick is exactly one card, never several', () {
        expect(pageFor(pixels: anchor + 10, velocity: 3000, restingPage: 0), 1);
        expect(
          pageFor(pixels: anchor + extent * 2.4, velocity: 4000, restingPage: 1),
          2,
        );
        expect(
          pageFor(pixels: anchor + extent * 1.6, velocity: -3000, restingPage: 2),
          1,
        );
      });

      test('never past the last card', () {
        expect(
          pageFor(
            pixels: anchor + 4 * extent - 5,
            velocity: 3000,
            restingPage: 4,
          ),
          4,
        );
      });

      test('flicking up off the first card returns to the move table', () {
        expect(pageFor(pixels: anchor, velocity: -3000, restingPage: 0), isNull);
      });

      test('a dead release takes the card the finger left on top', () {
        expect(
          pageFor(pixels: anchor + extent * 1.1, velocity: 0, restingPage: 1),
          1,
        );
        expect(
          pageFor(pixels: anchor + extent * 1.6, velocity: 0, restingPage: 1),
          2,
        );
      });

      test('dragged clear above the first card, the move table takes over', () {
        expect(
          pageFor(pixels: anchor - extent * 0.7, velocity: 0, restingPage: 0),
          isNull,
        );
      });
    });

    test('no grid, no opinion', () {
      expect(
        explorerGamesSnapPage(
          pixels: 0,
          velocity: 0,
          velocityTolerance: 50,
          anchor: anchor,
          pageExtent: 0,
          pageCount: pageCount,
          restingPage: null,
        ),
        isNull,
      );
      expect(
        explorerGamesSnapPage(
          pixels: 0,
          velocity: 0,
          velocityTolerance: 50,
          anchor: anchor,
          pageExtent: extent,
          pageCount: 0,
          restingPage: null,
        ),
        isNull,
      );
    });
  });

  group('resting page — only a real standstill on a real card counts', () {
    const anchor = 200.0;
    const extent = 180.0;
    const pageCount = 5;
    final maxExtent = anchor + (pageCount - 1) * extent;

    int? restAt(double pixels, {double? maxScrollExtent}) =>
        explorerGamesRestingPage(
          pixels: pixels,
          anchor: anchor,
          pageExtent: extent,
          pageCount: pageCount,
          minScrollExtent: 0,
          maxScrollExtent: maxScrollExtent ?? maxExtent,
        );

    test('flush on a card is that card', () {
      expect(restAt(anchor), 0);
      expect(restAt(anchor + extent), 1);
      expect(restAt(anchor + 3 * extent), 3);
    });

    test('nearly card 0 is not card 0', () {
      // This is the one that used to open the gate: a settle that stopped
      // short of the anchor was called a rest, so the next flick stepped to
      // card 1 while card 0 had never been flush under the player row.
      expect(restAt(anchor - 30), isNull);
      expect(restAt(anchor + extent * 0.4), isNull);
    });

    test('a rest in the move table belongs to no card', () {
      expect(restAt(0), isNull);
    });

    test('the last card counts even when the pin pulls maxScrollExtent in', () {
      // Collapsing the engine PV grows this list's viewport, which shrinks
      // maxScrollExtent — the last card tops out short of its aligned offset
      // and is still a rest on the last card.
      final clamped = maxExtent - 40;
      expect(restAt(clamped, maxScrollExtent: clamped), pageCount - 1);
    });
  });

  group('config lifecycle', () {
    ExplorerGamesSnapConfig configFor() =>
        ExplorerGamesSnapConfig()
          ..update(anchor: 80, pageExtent: 180, pageCount: 4);

    test('a fresh strip owes the reader the first card', () {
      final config = configFor();
      expect(config.restingPage, isNull);
      expect(
        config.resolveSettlePage(
          pixels: 80 + 180 * 1.2,
          velocity: 3500,
          velocityTolerance: 50,
        ),
        0,
      );
    });

    test('the settle target is latched for the life of one settle', () {
      // A relayout restarts the in-flight ballistic; every restart must be
      // handed the same answer, not a fresh one derived from pixels that the
      // spring has already moved on.
      final config = configFor();
      final first = config.resolveSettlePage(
        pixels: 80 + 180 * 0.2,
        velocity: 3000,
        velocityTolerance: 50,
      );
      expect(first, 0);
      for (final pixels in [80 + 180 * 0.6, 80 + 180 * 1.1, 80 + 180 * 1.4]) {
        expect(
          config.resolveSettlePage(
            pixels: pixels,
            velocity: 1200,
            velocityTolerance: 50,
          ),
          0,
          reason: 'restart at $pixels must reuse the latched card',
        );
      }
    });

    test('a new gesture decides afresh, from the card actually rested on', () {
      final config = configFor();
      config.resolveSettlePage(
        pixels: 100,
        velocity: 3000,
        velocityTolerance: 50,
      );
      config.endGesture(pixels: 80, minScrollExtent: 0, maxScrollExtent: 800);
      expect(config.restingPage, 0);

      config.beginGesture();
      expect(
        config.resolveSettlePage(
          pixels: 90,
          velocity: 3000,
          velocityTolerance: 50,
        ),
        1,
      );
    });

    test('catching a flying list does not promote where it was caught', () {
      // Only endGesture records a rest, so grabbing mid-flight leaves the
      // reader "in the move table" and the next flick still owes them card 0.
      final config = configFor();
      config.beginGesture();
      expect(
        config.resolveSettlePage(
          pixels: 80 + 180 * 0.8,
          velocity: 2500,
          velocityTolerance: 50,
        ),
        0,
      );
    });

    test('a settle that stops short of card 0 is not a rest on it', () {
      final config = configFor();
      config.endGesture(
        pixels: 80 + 60,
        minScrollExtent: 0,
        maxScrollExtent: 800,
      );
      expect(config.restingPage, isNull);
    });

    test('scrolling back into the move table re-arms the entry rule', () {
      final config = configFor();
      config.endGesture(pixels: 80, minScrollExtent: 0, maxScrollExtent: 800);
      expect(config.restingPage, 0);
      config.endGesture(pixels: 0, minScrollExtent: 0, maxScrollExtent: 800);
      expect(config.restingPage, isNull);
    });

    test('a different strip resets paging, a re-measure does not', () {
      final config = configFor();
      config.endGesture(
        pixels: 80 + 180,
        minScrollExtent: 0,
        maxScrollExtent: 800,
      );
      expect(config.restingPage, 1);

      // Sub-pixel churn from re-measuring the same layout: if this reset the
      // paging state the strip could never leave card 0.
      config.update(anchor: 80.4, pageExtent: 180, pageCount: 4);
      expect(config.restingPage, 1);

      // A new position brings a new card count — that really is a new strip.
      config.update(anchor: 80.4, pageExtent: 180, pageCount: 6);
      expect(config.restingPage, isNull);
    });

    test('resetPaging puts the reader back at the entrance', () {
      final config = configFor();
      config.endGesture(
        pixels: 80 + 2 * 180,
        minScrollExtent: 0,
        maxScrollExtent: 800,
      );
      expect(config.restingPage, 2);
      config.resetPaging();
      expect(config.restingPage, isNull);
    });

    test('the strip is claimed as soon as a settle springs at a card', () {
      // The pin reads this to start collapsing the engine lines while the card
      // is still on its way, so the space opens as the card rises into it.
      const anchor = 80.0;
      const extent = 180.0;
      final config =
          ExplorerGamesSnapConfig()..update(
            anchor: anchor,
            pageExtent: extent,
            pageCount: 4,
          );
      expect(config.settleRunningToCard, isFalse);

      final physics = ExplorerGamesSnapPhysics(config: config);
      final metrics = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: anchor + 3 * extent,
        pixels: anchor - 60,
        viewportDimension: 300,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1,
      );
      expect(physics.createBallisticSimulation(metrics, 3000), isNotNull);
      expect(config.settleRunningToCard, isTrue);

      config.endGesture(
        pixels: anchor,
        minScrollExtent: 0,
        maxScrollExtent: anchor + 3 * extent,
      );
      expect(config.settleRunningToCard, isFalse);
    });

    test('a settle handed back to the move table claims nothing', () {
      const anchor = 400.0;
      const extent = 180.0;
      final config =
          ExplorerGamesSnapConfig()..update(
            anchor: anchor,
            pageExtent: extent,
            pageCount: 4,
          );
      final physics = ExplorerGamesSnapPhysics(config: config);
      final metrics = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: anchor + 3 * extent,
        pixels: 100,
        viewportDimension: 300,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1,
      );
      physics.createBallisticSimulation(metrics, -3000);
      expect(config.settleRunningToCard, isFalse);
    });

    test('the settle spring ends on the first card, not the second', () {
      const anchor = 200.0;
      const extent = 180.0;
      final config =
          ExplorerGamesSnapConfig()..update(
            anchor: anchor,
            pageExtent: extent,
            pageCount: 5,
          );
      final physics = ExplorerGamesSnapPhysics(config: config);
      final metrics = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: anchor + 4 * extent,
        pixels: anchor + extent * 0.9,
        viewportDimension: 300,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1,
      );
      final sim = physics.createBallisticSimulation(metrics, 3000);
      expect(sim, isNotNull);
      // Sampled far in the future — snapToEnd holds the end.
      expect(sim!.x(10), closeTo(anchor, 1.0));
    });

    test('a failed mid-layout measure keeps the last good geometry', () {
      final config = configFor();
      config.update(anchor: null, pageExtent: 0, pageCount: 0);
      expect(config.isActive, isTrue);
      expect(config.anchor, 80);
      expect(config.pageExtent, 180);
      expect(config.pageCount, 4);
    });
  });

  group('page offsets', () {
    const anchor = 400.0;
    const extent = 200.0;

    test('page offsets are pure content-space', () {
      expect(
        explorerGamesOffsetForPage(
          pageIndex: 2,
          anchor: anchor,
          pageExtent: extent,
          minScrollExtent: 0,
          maxScrollExtent: anchor + 4 * extent,
        ),
        anchor + 2 * extent,
      );
    });

    test('offsets stay inside the scrollable range', () {
      expect(
        explorerGamesOffsetForPage(
          pageIndex: 9,
          anchor: anchor,
          pageExtent: extent,
          minScrollExtent: 0,
          maxScrollExtent: anchor + 4 * extent,
        ),
        anchor + 4 * extent,
      );
    });

    test('page motion is a bounce-free motor spring', () {
      expect(kExplorerPageMotion.description.bounce, 0);
    });
  });

  group('live physics', () {
    const anchor = 80.0;
    const extent = 180.0;
    const cardCount = 4;
    const viewport = 300.0;

    Future<ScrollController> pumpStrip(
      WidgetTester tester,
      ExplorerGamesSnapConfig config, {
      double listAnchor = anchor,
    }) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: viewport,
                child: NotificationListener<ScrollNotification>(
                  // Same wiring as the panel: begin/end the gesture from the
                  // scroll notifications, nothing else.
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification) {
                      config.beginGesture();
                    } else if (notification is ScrollEndNotification) {
                      config.endGesture(
                        pixels: notification.metrics.pixels,
                        minScrollExtent: notification.metrics.minScrollExtent,
                        maxScrollExtent: notification.metrics.maxScrollExtent,
                      );
                    }
                    return false;
                  },
                  child: ListView(
                    controller: controller,
                    physics: ExplorerGamesSnapPhysics(config: config),
                    padding: const EdgeInsets.only(bottom: viewport - extent),
                    children: [
                      SizedBox(height: listAnchor),
                      for (var i = 0; i < cardCount; i++)
                        const SizedBox(height: extent),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return controller;
    }

    testWidgets('a hard fling out of a short move table lands on card 0', (
      tester,
    ) async {
      final config =
          ExplorerGamesSnapConfig()..update(
            anchor: anchor,
            pageExtent: extent,
            pageCount: cardCount,
          );
      final controller = await pumpStrip(tester, config);

      await tester.fling(find.byType(ListView), const Offset(0, -400), 3000);
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(anchor, 2.0));
      expect(config.restingPage, 0);
    });

    testWidgets('a normal-pace drag out of the move table lands on card 0', (
      tester,
    ) async {
      final config =
          ExplorerGamesSnapConfig()..update(
            anchor: anchor,
            pageExtent: extent,
            pageCount: cardCount,
          );
      final controller = await pumpStrip(tester, config);

      // Slow enough that the release velocity is nothing like a fling, far
      // enough that the finger ends well inside card 1.
      await tester.timedDrag(
        find.byType(ListView),
        const Offset(0, -240),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(anchor, 2.0));
      expect(config.restingPage, 0);
    });

    testWidgets('a relayout mid-settle cannot move the landing card', (
      tester,
    ) async {
      // Landing on card 0 pins the strip, which collapses the engine PV and
      // the move-column header. Both animate, so the viewport changes every
      // frame and restarts the in-flight ballistic — this is exactly the case
      // that used to skip to card 1.
      final config =
          ExplorerGamesSnapConfig()..update(
            anchor: anchor,
            pageExtent: extent,
            pageCount: cardCount,
          );
      final controller = await pumpStrip(tester, config);

      await tester.fling(find.byType(ListView), const Offset(0, -400), 3000);
      // Restart the ballistic repeatedly while it is in flight, the way a
      // shrinking viewport does.
      final position =
          controller.position as ScrollPositionWithSingleContext;
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        position.goBallistic(position.activity?.velocity ?? 0);
      }
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(anchor, 2.0));
    });

    testWidgets('after resting on card 0 the strip pages one card at a time', (
      tester,
    ) async {
      final config =
          ExplorerGamesSnapConfig()..update(
            anchor: anchor,
            pageExtent: extent,
            pageCount: cardCount,
          );
      final controller = await pumpStrip(tester, config);

      await tester.fling(find.byType(ListView), const Offset(0, -400), 3000);
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(anchor, 2.0));

      await tester.fling(find.byType(ListView), const Offset(0, -400), 3000);
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(anchor + extent, 2.0));
      expect(config.restingPage, 1);

      await tester.fling(find.byType(ListView), const Offset(0, 400), 3000);
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(anchor, 2.0));
      expect(config.restingPage, 0);
    });

    testWidgets('leaving the strip re-arms the first card for the next entry', (
      tester,
    ) async {
      const tallAnchor = 400.0;
      final config =
          ExplorerGamesSnapConfig()..update(
            anchor: tallAnchor,
            pageExtent: extent,
            pageCount: cardCount,
          );
      final controller = await pumpStrip(
        tester,
        config,
        listAnchor: tallAnchor,
      );

      controller.jumpTo(tallAnchor);
      await tester.pumpAndSettle();
      expect(config.restingPage, 0);

      // Back up into the move table.
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(config.restingPage, isNull);

      // Entering again owes the reader card 0, not card 1.
      await tester.fling(find.byType(ListView), const Offset(0, -600), 4000);
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(tallAnchor, 2.0));
    });

    testWidgets('the top of a short move table stays reachable', (
      tester,
    ) async {
      final config =
          ExplorerGamesSnapConfig()..update(
            anchor: anchor,
            pageExtent: extent,
            pageCount: cardCount,
          );
      final controller = await pumpStrip(tester, config);

      controller.jumpTo(anchor);
      await tester.pumpAndSettle();
      await tester.fling(find.byType(ListView), const Offset(0, 400), 3000);
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(0, 2.0));
    });

    testWidgets('the reserve lands the end of the list on the last card', (
      tester,
    ) async {
      final config =
          ExplorerGamesSnapConfig()..update(
            anchor: anchor,
            pageExtent: extent,
            pageCount: cardCount,
          );
      final controller = await pumpStrip(tester, config);

      // A lazy list only estimates its extent from the children it has built,
      // so walk to the bottom before asking where the bottom is.
      for (var i = 0; i < cardCount; i++) {
        final before = controller.position.maxScrollExtent;
        controller.jumpTo(before);
        await tester.pumpAndSettle();
        if ((controller.position.maxScrollExtent - before).abs() < 0.5) break;
      }
      expect(
        controller.position.maxScrollExtent,
        closeTo(anchor + (cardCount - 1) * extent, 8.0),
      );
    });
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

  group('pin decision', () {
    test('enters when the section reaches the sticky edge', () {
      expect(
        explorerGamesPinDecision(delta: 8, currentlyInGames: false),
        isTrue,
      );
      expect(
        explorerGamesPinDecision(delta: 9, currentlyInGames: false),
        isFalse,
      );
      expect(
        explorerGamesPinDecision(delta: 0, currentlyInGames: false),
        isTrue,
      );
    });

    test('exits only past the wider exit band', () {
      expect(
        explorerGamesPinDecision(delta: 12, currentlyInGames: true),
        isTrue,
      );
      expect(
        explorerGamesPinDecision(delta: 13, currentlyInGames: true),
        isFalse,
      );
      // Still deep in games — stay pinned.
      expect(
        explorerGamesPinDecision(delta: -200, currentlyInGames: true),
        isTrue,
      );
    });

    test('content-space delta matches anchor - pixels', () {
      // Card 0 flush: delta 0. A few px shy of flush (enter threshold): +8.
      expect(explorerGamesPinDelta(pixels: 400, anchor: 400), 0);
      expect(explorerGamesPinDelta(pixels: 392, anchor: 400), 8);
      // Past first card into the strip: negative.
      expect(explorerGamesPinDelta(pixels: 600, anchor: 400), -200);
    });

    test('the card landing flush is what pins it over the engine lines', () {
      // Pin drives `explorerInlineGamesPinnedProvider`, which collapses the
      // engine PV so the strip's top edge is the player row itself.
      const anchor = 400.0;
      expect(
        explorerGamesPinDecision(
          delta: explorerGamesPinDelta(pixels: anchor, anchor: anchor),
          currentlyInGames: false,
        ),
        isTrue,
      );
    });
  });
}
