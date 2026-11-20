import 'package:chessever2/screens/search/search_carousel.dart';
import 'package:chessever2/screens/search/search_page_sections.dart'
    show searchPageGutter;
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Search tab's rows ([SearchCarousel]): a swipe moves on one card, a
/// fling may move several, and every row comes to rest with a card's
/// leading edge on the page's gutter, so every card (the first, each one in
/// the middle, the last and See more) can be read whole. The same on iOS,
/// where the row bounces at its ends, and on Android, where it clamps.
void main() {
  final platforms = TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
  });

  testWidgets('a gentle swipe moves exactly one card, onto the gutter, '
      'through every card to See more and back', (tester) async {
    final row = await _pumpRow(tester, cards: 6);
    final slots = row.slots;
    expect(slots, 7, reason: 'six cards and See more');

    // Forward one card a swipe: each card in the middle comes to rest whole,
    // its leading edge on the gutter; See more ends the row, whole.
    for (var card = 1; card < slots; card++) {
      await row.swipe(-120, speed: 1500);
      expect(row.restingCard, closeTo(card, 1e-6), reason: 'card $card');
      expect(row.pixels, closeTo(row.offsetOf(card), 0.01));
      row.expectWhole(card);
      if (row.offsetOf(card) < row.max) row.expectOnGutter(card);
    }
    expect(row.pixels, closeTo(row.max, 0.01));
    expect(find.byKey(const ValueKey('search-test-see-more')), findsOneWidget);
    // Past the end (a bounce on iOS, a clamp on Android): back to See more.
    await row.swipe(-120, speed: 1500);
    expect(row.pixels, closeTo(row.max, 0.01));

    // And back, one card a swipe, to the first.
    for (var card = slots - 2; card >= 0; card--) {
      await row.swipe(120, speed: 1500);
      expect(row.pixels, closeTo(row.offsetOf(card), 0.01), reason: '$card');
      row.expectOnGutter(card);
    }
    // Past the start: back to the first card.
    await row.swipe(120, speed: 1500);
    expect(row.pixels, closeTo(0, 0.01));
    row.expectOnGutter(0);
    expect(tester.takeException(), isNull);
  }, variant: platforms);

  testWidgets('two cards to a phone\'s row (News): still one card a swipe, '
      'each onto the gutter, to the end', (tester) async {
    final row = await _pumpRow(tester, cards: 7, phoneColumns: 2);
    var card = 0;
    while (row.pixels < row.max - 0.01) {
      card++;
      await row.swipe(-80, speed: 1500);
      expect(row.pixels, closeTo(row.offsetOf(card), 0.01), reason: '$card');
      if (row.offsetOf(card) < row.max) row.expectOnGutter(card);
    }
    // The last card and See more, both whole.
    expect(card, row.slots - 2);
    row.expectWhole(row.slots - 2);
    row.expectWhole(row.slots - 1);
  }, variant: platforms);

  testWidgets('a quicker swipe still moves one card; only a real fling '
      'moves several, and it too rests a card on the gutter', (tester) async {
    final row = await _pumpRow(tester, cards: 12);
    for (final speed in [600.0, 1000.0, 2000.0, 3000.0, 4000.0]) {
      row.position.jumpTo(row.offsetOf(2));
      await tester.pump();
      await row.swipe(-100, speed: speed);
      expect(row.restingCard, closeTo(3, 1e-6), reason: 'forward at $speed');
      await row.swipe(100, speed: speed);
      expect(row.restingCard, closeTo(2, 1e-6), reason: 'back at $speed');
    }

    row.position.jumpTo(0);
    await tester.pump();
    await row.swipe(-200, speed: 7000);
    final card = row.restingCard;
    expect(card, closeTo(card.roundToDouble(), 1e-6));
    expect(card, inInclusiveRange(2, 4));
    row.expectOnGutter(card.round());
  }, variant: platforms);

  testWidgets('a slow drag (no fling) rests on the nearer card', (
    tester,
  ) async {
    final row = await _pumpRow(tester, cards: 6);
    await tester.timedDrag(
      row.cardFinder(0),
      Offset(-row.slot * 0.4, 0),
      const Duration(seconds: 3),
    );
    await tester.pumpAndSettle();
    expect(row.pixels, closeTo(0, 0.01));

    await tester.timedDrag(
      row.cardFinder(0),
      Offset(-row.slot * 0.6, 0),
      const Duration(seconds: 3),
    );
    await tester.pumpAndSettle();
    expect(row.pixels, closeTo(row.offsetOf(1), 0.01));
  }, variant: platforms);

  testWidgets('swiping again while the row is still settling moves one more '
      'card, never more: no momentum carried from swipe to swipe', (
    tester,
  ) async {
    final row = await _pumpRow(tester, cards: 12);
    await row.fling(-120, speed: 2500);
    // Caught still settling, swiped on: on from the card it was arriving at.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(row.restingCard, inExclusiveRange(0.3, 1));
    await row.fling(-120, speed: 2500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(row.restingCard, inExclusiveRange(1.3, 2));
    // Caught before it has moved at all, twice: still one card a swipe.
    await row.fling(-120, speed: 2500);
    await row.fling(-120, speed: 2500);
    await tester.pumpAndSettle();
    expect(row.restingCard, closeTo(4, 1e-6));
    row.expectOnGutter(4);
  }, variant: platforms);

  testWidgets('a settle the row\'s length changes under (a page landing) '
      'still rests on the card it set out for', (tester) async {
    final count = ValueNotifier(6);
    addTearDown(count.dispose);
    final row = await _pumpRow(tester, count: count);
    await row.fling(-120, speed: 1500);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      count.value += 3;
    }
    await tester.pumpAndSettle();
    expect(row.restingCard, closeTo(1, 1e-6));
    row.expectOnGutter(1);
  }, variant: platforms);

  test('a settle that restarts keeps the card it promised', () {
    final snap = SearchCarouselSnap()..slot = 300;
    final physics = SearchCarouselPhysics(snap);
    ScrollMetrics at(double pixels) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 3000,
      pixels: pixels,
      viewportDimension: 393,
      axisDirection: AxisDirection.right,
      devicePixelRatio: 3,
    );
    double end(Simulation? simulation) => simulation!.x(10);

    snap.grabbed(0);
    expect(end(physics.createBallisticSimulation(at(100), 1500)), 300);
    // Restarted near its end, still moving on: the same card, not the next.
    expect(end(physics.createBallisticSimulation(at(299), 150)), 300);
    expect(physics.createBallisticSimulation(at(300), 0), isNull);
    // At rest: the next swipe decides afresh.
    snap.rested();
    snap.grabbed(300);
    expect(end(physics.createBallisticSimulation(at(380), 1500)), 600);
  });
}

class _Row {
  _Row(this.tester);

  final WidgetTester tester;

  ScrollPosition get position => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(const PageStorageKey<String>('search-carousel-test')),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  SearchCarouselPhysics get physics =>
      position.physics as SearchCarouselPhysics;

  double get slot => physics.slot;
  double get pixels => position.pixels;
  double get max => position.maxScrollExtent;

  /// Slots in the row: its cards and the one ending it.
  int get slots =>
      ((max + position.viewportDimension - searchPageGutter * 2) / slot)
          .round();

  /// The row's offset, in cards.
  double get restingCard {
    final at = pixels;
    // At the end the row rests on its last slot, whole on the screen.
    if ((at - max).abs() < 0.01 && max % slot > 0.01) return slots - 1;
    return at / slot;
  }

  double offsetOf(int card) => (card * slot).clamp(0.0, max);

  Finder cardFinder(int card) => find.byKey(ValueKey('card-$card'));

  Rect rectOf(int card) {
    final slotFinder = card < slots - 1
        ? cardFinder(card)
        : find.byKey(const ValueKey('search-test-see-more'));
    return tester.getRect(slotFinder);
  }

  void expectOnGutter(int card) {
    expect(
      rectOf(card).left,
      closeTo(searchPageGutter, 0.01),
      reason: 'card $card on the gutter',
    );
  }

  void expectWhole(int card) {
    final rect = rectOf(card);
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(rect.left, greaterThanOrEqualTo(-0.01), reason: 'card $card');
    expect(rect.right, lessThanOrEqualTo(width + 0.01), reason: 'card $card');
  }

  /// Flings the row from the middle of the screen and leaves it running.
  Future<void> fling(double dx, {required double speed}) async {
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    await tester.flingFrom(Offset(width / 2, 300), Offset(dx, 0), speed);
  }

  /// Flings the row and lets it come to rest.
  Future<void> swipe(double dx, {required double speed}) async {
    await fling(dx, speed: speed);
    await tester.pumpAndSettle();
  }
}

Future<_Row> _pumpRow(
  WidgetTester tester, {
  int cards = 6,
  int phoneColumns = 1,
  ValueNotifier<int>? count,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393, 852) * 3;
  addTearDown(tester.view.reset);
  final items = count ?? ValueNotifier(cards);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: Align(
              alignment: const Alignment(0, -0.3),
              child: ValueListenableBuilder<int>(
                valueListenable: items,
                builder: (context, itemCount, _) => SearchCarousel(
                  section: 'test',
                  title: 'Test',
                  itemCount: itemCount,
                  itemBuilder: (context, i) => ColoredBox(
                    key: ValueKey('card-$i'),
                    color: Color(0xFF203040 + i * 0x101010),
                  ),
                  sizing: SearchCarouselSizing.fixed(
                    (_, _) => 120,
                    phoneColumns: phoneColumns,
                  ),
                  onSeeMore: () {},
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  final row = _Row(tester);
  // The row sits across y = 300.
  final top = tester.getRect(row.cardFinder(0));
  expect(top.top, lessThan(300));
  expect(top.bottom, greaterThan(300));
  return row;
}
