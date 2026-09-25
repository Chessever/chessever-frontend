import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show discoveryGridCardWidth;
import 'package:chessever2/screens/my_space/widgets/space_rail.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A rail of [count] plain cards on a 390 phone, asking [onLoadMore] for
/// more while [hasMore]. Each card is [heightOf] its width tall (80 by
/// default).
Future<void> _pumpRail(
  WidgetTester tester, {
  required ValueNotifier<int> count,
  required ValueNotifier<bool> hasMore,
  required VoidCallback onLoadMore,
  double Function(int index, double width)? heightOf,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gamesListViewModeProvider.overrideWithValue(
          GamesListViewMode.chessBoardGrid,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: ListenableBuilder(
                  listenable: Listenable.merge([count, hasMore]),
                  builder: (context, _) => SpaceRail(
                    storageId: 'test',
                    gutter: 16,
                    hasMore: hasMore.value,
                    onLoadMore: onLoadMore,
                    items: [
                      for (var i = 0; i < count.value; i++)
                        SpaceRailItem(
                          id: 'card:$i',
                          slot: SpaceRailSlot.wide,
                          builder: (context, width) => SizedBox(
                            key: ValueKey<String>('box:$i'),
                            width: width,
                            height: heightOf?.call(i, width) ?? 80,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('a rail asks for its next page once it nears its end, not '
      'before, once per approach, and never past the last page', (
    tester,
  ) async {
    final count = ValueNotifier(kSpaceRailPage);
    final hasMore = ValueNotifier(true);
    var asked = 0;
    await _pumpRail(
      tester,
      count: count,
      hasMore: hasMore,
      onLoadMore: () => asked++,
    );
    expect(asked, 0, reason: 'a full first page waits for the reader');

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    final first = tester.getRect(find.byKey(const ValueKey('box:0')));
    final card = first.width;
    final gutter = first.left;
    final gap = tester.getRect(find.byKey(const ValueKey('box:1'))).left -
        first.right;
    // After the last real card: its gap, the trailing plate and the gutter.
    // None of it counts towards the load-ahead distance.
    final tail = gap + card + gutter;
    // The scroll offset at which the last real card's right edge stands
    // [cards] card widths past the rail's right edge.
    double at(double cards) =>
        position.maxScrollExtent - tail - cards * card;

    // Two cards from the last real one: nothing yet.
    position.jumpTo(at(kSpaceRailLoadAhead + 0.5));
    await tester.pump();
    expect(asked, 0, reason: 'the trailing plate is not a card to read');

    // Within one and a half: one request, while a real card is still to
    // come (the plate never shows before the next page is asked for).
    position.jumpTo(at(kSpaceRailLoadAhead - 0.25));
    await tester.pump();
    expect(asked, 1);
    // Still waiting on that page: no second request.
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(asked, 1);

    // The page lands; the rail is far from its new end again.
    count.value = 2 * kSpaceRailPage;
    await tester.pump();
    await tester.pump();
    expect(asked, 1);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(asked, 2);

    // The last page: nothing more is asked, and the trailing plate goes.
    count.value = 3 * kSpaceRailPage;
    hasMore.value = false;
    await tester.pump();
    await tester.pump();
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(asked, 2);
    expect(find.byType(SpaceRailSkeleton), findsNothing);
  });

  testWidgets('a first page too short to fill the rail asks for the next at '
      'once, and a loading page shows one trailing plate', (tester) async {
    final count = ValueNotifier(1);
    final hasMore = ValueNotifier(true);
    var asked = 0;
    await _pumpRail(
      tester,
      count: count,
      hasMore: hasMore,
      onLoadMore: () => asked++,
    );
    expect(asked, 1);
    expect(find.byType(SpaceRailSkeleton), findsOneWidget);
  });

  testWidgets('a rail is as tall as the items it holds now: it shrinks '
      'back when a lone card gets company or its tallest card leaves', (
    tester,
  ) async {
    // Cards as tall as they are wide (a board card), card 0 taller still.
    final count = ValueNotifier(2);
    final hasMore = ValueNotifier(false);
    double tallest = 0;
    await _pumpRail(
      tester,
      count: count,
      hasMore: hasMore,
      onLoadMore: () {},
      heightOf: (i, width) => i == 0 ? width + tallest : width,
    );
    double rail() =>
        tester.getSize(find.byType(ListView)).height - 2 * kSpaceRailAir;
    double width(int i) =>
        tester.getSize(find.byKey(ValueKey('box:$i'))).width;

    await tester.pump();
    final two = rail();
    expect(two, closeTo(width(0), 0.5));

    // One card: it takes the whole line, and the rail its height.
    count.value = 1;
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(width(0), greaterThan(two + 1));
    expect(rail(), closeTo(width(0), 0.5));

    // Company again: back to the pair's height, no empty band under them.
    count.value = 2;
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(rail(), closeTo(two, 0.5));

    // The first card grows taller than the second, then leaves: the rail
    // follows it up, then back down to what it holds.
    tallest = 60;
    count.value = 3;
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(rail(), closeTo(width(0) + 60, 0.5));
    tallest = 0;
    count.value = 2;
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(rail(), closeTo(two, 0.5));
  });

  for (final phone in const [Size(375, 667), Size(393, 852), Size(430, 932)]) {
    testWidgets('on a ${phone.width.toInt()} phone a grid rail narrows its '
        'cards just enough that the next one peeks, and keeps the grid '
        'width when its games all fit', (tester) async {
      tester.view.physicalSize = phone * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      late SpaceRailMetrics more;
      late SpaceRailMetrics two;
      late double natural;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              natural = discoveryGridCardWidth(context);
              more = SpaceRailMetrics.of(
                context,
                viewport: phone.width,
                gutter: 16,
                mode: GamesListViewMode.chessBoardGrid,
              );
              two = SpaceRailMetrics.of(
                context,
                viewport: phone.width,
                gutter: 16,
                mode: GamesListViewMode.chessBoardGrid,
                gameCount: 2,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      final gap = more.gapBefore(SpaceRailSlot.game, SpaceRailSlot.game);
      expect(gap, more.gap, reason: 'the rail\'s own gap, never widened');
      // Two whole cards, then a real part of the third: never a sliver,
      // never nothing at all.
      final shown = phone.width - (16 + 2 * more.game + 2 * gap);
      expect(more.game, lessThan(natural));
      expect(
        shown,
        greaterThanOrEqualTo(
          [more.game * kSpaceRailPeek, kSpaceRailPeekMax].reduce(
                (a, b) => a < b ? a : b,
              ) -
              0.01,
        ),
      );
      expect(shown, lessThanOrEqualTo(more.game * (1 - kSpaceRailPeek)));
      // A little narrower than Discovery's grid card, never a shrunk one.
      expect(more.game, greaterThan(natural * 0.85));
      // Two games and nothing more: gutter to gutter, at the grid's width
      // where two fit, a hair narrower where they nearly do.
      expect(
        16 + 2 * two.game + gap,
        lessThanOrEqualTo(phone.width - 16 + 0.01),
      );
      expect(two.game, greaterThanOrEqualTo(natural * kSpaceRailFitWhole));
      if (2 * natural + gap <= phone.width - 32) expect(two.game, natural);
    });
  }

  test('a rail that may not add a whole card keeps its width and shows '
      'more of the next, but still never a sliver', () {
    const gap = 12.0;
    // 580 on a 1024 screen: a whole card and three quarters of the next.
    expect(
      spaceRailPeekWidth(
        viewport: 1024,
        gutter: 32,
        gap: gap,
        natural: 580,
        addWhole: false,
      ),
      isNull,
    );
    expect(
      spaceRailPeekWidth(viewport: 1024, gutter: 32, gap: gap, natural: 580),
      lessThan(580),
    );
    // A sliver still narrows the card.
    final width = spaceRailPeekWidth(
      viewport: 393,
      gutter: 16,
      gap: gap,
      natural: 350,
      addWhole: false,
    )!;
    expect(393 - (16 + width + gap), closeTo(kSpaceRailPeekMax, 0.01));
  });

  testWidgets('a group\'s leading card holds at the gutter while the group '
      'scrolls under it, and leaves with the group\'s end', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget group(String id, double width) => SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SpaceRailStickyLead(
            width: 200,
            child: SizedBox(
              key: ValueKey<String>('lead:$id'),
              width: 200,
              height: 40,
              child: const ColoredBox(color: Color(0xFF202020)),
            ),
          ),
          SizedBox(width: width, height: 100),
        ],
      ),
    );
    var taps = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SpaceRail(
                    storageId: 'sticky',
                    gutter: 16,
                    items: [
                      for (final id in ['a', 'b'])
                        SpaceRailItem(
                          id: id,
                          slot: SpaceRailSlot.group,
                          widthFor: (_) => 800,
                          builder: (context, width) => GestureDetector(
                            onTap: () => taps++,
                            child: group(id, width),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    Rect lead(String id) =>
        tester.getRect(find.byKey(ValueKey<String>('lead:$id')));
    expect(lead('a').left, 16);

    // Half way through the first group: its card holds at the gutter.
    position.jumpTo(300);
    await tester.pump();
    expect(lead('a').left, closeTo(16, 0.01));
    // The card still answers where it is drawn.
    await tester.tapAt(lead('a').center);
    await tester.pump(const Duration(milliseconds: 500));
    expect(taps, 1);

    // Near the group's end the card leaves with it, flush with its end.
    position.jumpTo(700);
    await tester.pump();
    final group0 = 16.0 - 700;
    expect(lead('a').right, closeTo(group0 + 800, 0.01));
    expect(lead('a').left, lessThan(16));
    // The second group's card has not started to hold yet.
    expect(lead('b').left, closeTo(group0 + 800 + 12, 0.5));
  });

  testWidgets('a rail in a page column narrower than the screen fades out '
      'across its gutters; a rail to the screen\'s edge does not', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> pumpAt(double width) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: width,
                      child: SpaceRail(
                        storageId: 'fade',
                        gutter: 32,
                        items: [
                          for (var i = 0; i < 6; i++)
                            SpaceRailItem(
                              id: 'c$i',
                              slot: SpaceRailSlot.wide,
                              builder: (context, w) =>
                                  SizedBox(width: w, height: 60),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpAt(1200);
    expect(
      find.byKey(const ValueKey<String>('space_rail_edge_fade')),
      findsOneWidget,
    );
    await pumpAt(1366);
    expect(
      find.byKey(const ValueKey<String>('space_rail_edge_fade')),
      findsNothing,
    );
  });

  test('a rail always ends on part of the next item, never a sliver', () {
    const gap = 12.0;
    for (var viewport = 320.0; viewport <= 440; viewport += 1) {
      for (final gutter in [16.0, 24.0]) {
        final content = viewport - 2 * gutter;
        for (final natural in [content * 0.86, viewport / 2 - 24, 80.0]) {
          final width =
              spaceRailPeekWidth(
                viewport: viewport,
                gutter: gutter,
                gap: gap,
                natural: natural,
              ) ??
              natural;
          final span = viewport - gutter;
          final whole = ((span + gap) / (width + gap)).floor();
          final shown = span - whole * (width + gap);
          final least = [
            width * kSpaceRailPeek,
            kSpaceRailPeekMax,
          ].reduce((a, b) => a < b ? a : b);
          expect(
            shown,
            greaterThanOrEqualTo(least - 0.01),
            reason: 'viewport $viewport, natural $natural: $shown shown',
          );
          expect(
            shown,
            lessThanOrEqualTo(width * (1 - kSpaceRailPeek) + 0.01),
            reason: 'viewport $viewport, natural $natural: nearly whole',
          );
        }
      }
    }
  });
}
