import 'package:chessever2/screens/feed/widgets/feed_page_viewport.dart';
import 'package:chessever2/screens/feed/widgets/feed_pull_refresh.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  PageController pages, {
  Future<void> Function()? onRefresh,
  ScrollPhysics physics = feedPagePhysics,
  Size size = const Size(852, 393),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: FeedPullRefresh(
              onRefresh: onRefresh ?? () async {},
              child: PageView.builder(
                controller: pages,
                physics: physics,
                scrollDirection: Axis.vertical,
                itemCount: 2,
                itemBuilder: (context, index) => FeedPageViewport(
                  key: ValueKey('post-$index'),
                  builder: (context, constraints) => ColoredBox(
                    color: index == 0 ? Colors.black : Colors.white,
                    child: Column(
                      children: [
                        Text('Post $index start'),
                        const Spacer(),
                        Text('Post $index end'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
}

ScrollPosition _content(WidgetTester tester, int index) {
  final finder = find.descendant(
    of: find.byKey(ValueKey('post-$index')),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(finder).position;
}

Future<void> _drag(WidgetTester tester, double distance) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final gesture = await tester.startGesture(size.center(Offset.zero));
  for (var i = 0; i < 18; i++) {
    await gesture.moveBy(Offset(0, distance / 18));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'rail-reduced folded landscape scrolls before handing off a post',
    (tester) async {
      final pages = PageController();
      addTearDown(pages.dispose);
      // 678x466 minus navigation, safe edge and the page's top bar.
      await _pump(tester, pages, size: const Size(486, 380));
      final first = _content(tester, 0);
      await _drag(tester, -150);
      expect(first.pixels, greaterThan(0));
      expect(pages.page, closeTo(0, 0.01));
      first.jumpTo(first.maxScrollExtent);
      await tester.pump();
      await _drag(tester, -250);
      expect(pages.page, closeTo(1, 0.01));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'landscape content scrolls, then hands its edge to next/previous post',
    (tester) async {
      final pages = PageController();
      addTearDown(pages.dispose);
      await _pump(tester, pages);
      final first = _content(tester, 0);

      // A drag inside the post first reveals its lower controls.
      await _drag(tester, -150);
      expect(first.pixels, greaterThan(0));
      expect(pages.page, closeTo(0, 0.01));

      // From the lower edge the SAME pointer movement drives PageScrollPhysics.
      first.jumpTo(first.maxScrollExtent);
      await tester.pump();
      await _drag(tester, -250);
      expect(pages.page, closeTo(1, 0.01));

      // Pulling from the next post's top edge returns to the previous post.
      await _drag(tester, 250);
      expect(pages.page, closeTo(0, 0.01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reversing a handed-off drag cancels the page change', (
    tester,
  ) async {
    final pages = PageController();
    addTearDown(pages.dispose);
    await _pump(tester, pages);
    final first = _content(tester, 0);
    first.jumpTo(first.maxScrollExtent);
    await tester.pump();
    final gesture = await tester.startGesture(const Offset(425, 230));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, -15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pages.page, greaterThan(0));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(pages.page, closeTo(0, 0.01));
    expect(first.pixels, first.maxScrollExtent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape first-post pull reaches Feed refresh', (tester) async {
    final pages = PageController();
    addTearDown(pages.dispose);
    var refreshed = 0;
    await _pump(tester, pages, onRefresh: () async => refreshed++);
    await _drag(tester, 300);
    expect(refreshed, 1);
    expect(pages.page, closeTo(0, 0.01));
    expect(_content(tester, 0).pixels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape handoff respects a locked enclosing PageView', (
    tester,
  ) async {
    final pages = PageController();
    addTearDown(pages.dispose);
    await _pump(tester, pages, physics: const NeverScrollableScrollPhysics());
    final first = _content(tester, 0);
    first.jumpTo(first.maxScrollExtent);
    await tester.pump();
    await _drag(tester, -250);
    expect(pages.page, closeTo(0, 0.01));
    expect(tester.takeException(), isNull);
  });
}
