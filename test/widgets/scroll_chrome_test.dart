import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A page with a 100px top bar over a long list, the shape every screen with
/// scroll chrome has.
class _Page extends StatefulWidget {
  const _Page({required this.onController, this.physics, this.itemCount});

  final ValueChanged<ScrollChromeController> onController;
  final ScrollPhysics? physics;

  /// The rows the list holds; 200 when null.
  final ValueNotifier<int>? itemCount;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> with SingleTickerProviderStateMixin {
  late final ScrollChromeController chrome = ScrollChromeController(
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    widget.onController(chrome);
  }

  @override
  void dispose() {
    chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        floatingActionButton: SlidingFabs(
          controller: chrome,
          child: SearchInkFab(onTap: () {}),
        ),
        body: Column(
          children: [
            CollapsingChrome(
              controller: chrome,
              child: const SizedBox(
                key: ValueKey('bar'),
                height: 100,
                width: double.infinity,
              ),
            ),
            Expanded(
              child: ScrollChromeRegion(
                controller: chrome,
                child: ValueListenableBuilder<int>(
                  valueListenable: widget.itemCount ?? ValueNotifier(200),
                  builder: (context, count, _) => ListView.builder(
                    physics: widget.physics,
                    itemCount: count,
                    itemExtent: 50,
                    itemBuilder: (context, i) =>
                        Text('row $i', key: ValueKey('row-$i')),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  setUp(() => ResponsiveHelper.initFromSize(const Size(393, 852)));

  double rowTop(WidgetTester tester, int i) =>
      tester.getTopLeft(find.byKey(ValueKey('row-$i'))).dy;

  for (final physics in <ScrollPhysics?>[
    null,
    const ClampingScrollPhysics(),
    // Bouncing physics never hands a drag to its parent: the chrome must
    // not depend on the physics chain.
    const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
  ]) {
    testWidgets('the bar follows the finger 1:1 '
        '(${physics?.runtimeType ?? 'default'} physics)', (tester) async {
      late ScrollChromeController chrome;
      await tester.pumpWidget(
        _Page(onController: (c) => chrome = c, physics: physics),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(200, 400));
      // Past the drag slop first, then the measured steps.
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      final afterSlop = rowTop(tester, 3);
      final barAfterSlop = chrome.value;

      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      // The content moved exactly as far as the finger did.
      expect(rowTop(tester, 3), moreOrLessEquals(afterSlop - 40, epsilon: 1));
      // And the bar gave up that much of its height.
      expect(chrome.value, moreOrLessEquals(barAfterSlop - 0.4, epsilon: 0.02));

      // Far enough to take the bar out entirely, then into the list.
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump();
      }
      expect(chrome.value, 0);
      // Every pixel after the drag took hold reached the content once.
      expect(
        rowTop(tester, 3),
        moreOrLessEquals(afterSlop - 190, epsilon: 1.5),
      );

      // Back up: the bar returns first, still with the finger.
      final before = rowTop(tester, 3);
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(rowTop(tester, 3), moreOrLessEquals(before + 30, epsilon: 1));
      expect(chrome.value, moreOrLessEquals(0.3, epsilon: 0.02));

      // Hold still before letting go, so the release is not a fling.
      await tester.pump(const Duration(milliseconds: 400));
      final atRelease = rowTop(tester, 3);
      await gesture.up();
      await tester.pumpAndSettle();
      // Let go nearer gone than shown: it settles gone, on the motor spring,
      // and the list holds still under it (the spring carries it).
      expect(chrome.value, 0);
      expect(rowTop(tester, 3), moreOrLessEquals(atRelease, epsilon: 1));
    });
  }

  testWidgets('a short list never moves the chrome', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      MaterialApp(home: _ShortList(onController: (c) => chrome = c)),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(chrome.value, 1);
  });

  testWidgets('the floating button slides away with the bar and takes no '
      'taps while away', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(_Page(onController: (c) => chrome = c));
    final fab = find.byType(SearchInkFab);
    final rest = tester.getTopLeft(fab).dy;
    chrome.hide(animate: false);
    await tester.pump();
    // Wholly off the bottom of the window, shadow and all: nothing peeks at
    // the rounded corner.
    final window =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getTopLeft(fab).dy, greaterThanOrEqualTo(window + 16));
    chrome.show(animate: false);
    await tester.pump();
    expect(tester.getTopLeft(fab).dy, rest);
  });

  testWidgets('a fling springs the bar away; the list never jumps back', (
    tester,
  ) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(_Page(onController: (c) => chrome = c));
    final list = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    // A short, fast flick: the finger lets go with the bar still part-way,
    // so the spring (not the finger) finishes taking it away.
    await tester.fling(find.byType(ListView), const Offset(0, -50), 2500);
    expect(chrome.value, greaterThan(0));
    expect(chrome.value, lessThan(1));
    // Where the list's first pixel sits on screen: the viewport's top (it
    // moves as the bar folds) less the scroll offset. Sampled frame by frame
    // while the spring takes the bar: the content only ever travels up, and
    // never by more than a fling frame's worth (no jolt the bar's height
    // long).
    double contentTop() =>
        tester.getTopLeft(find.byType(ListView)).dy - list.pixels;
    var last = contentTop();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = contentTop();
      expect(now, lessThanOrEqualTo(last + 0.5));
      expect(last - now, lessThan(60));
      last = now;
    }
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
  });

  testWidgets('the bounce back from a pull past the end keeps the bars '
      'away', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Page(
        onController: (c) => chrome = c,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
      ),
    );
    final list = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    // Read to the end with the bars gone.
    list.jumpTo(list.maxScrollExtent);
    chrome.hide(animate: false);
    await tester.pump();
    // Pull past the end and let go: the list springs back up, which is the
    // list settling, not the reader heading back.
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
  });

  testWidgets('a list that shrinks until it cannot scroll brings the bars '
      'back', (tester) async {
    late ScrollChromeController chrome;
    final count = ValueNotifier(200);
    addTearDown(count.dispose);
    await tester.pumpWidget(
      _Page(onController: (c) => chrome = c, itemCount: count),
    );
    await tester.fling(find.byType(ListView), const Offset(0, -600), 2000);
    await tester.pumpAndSettle();
    expect(chrome.value, 0);

    // A filter leaves three rows: nothing left to scroll up with.
    count.value = 3;
    await tester.pumpAndSettle();
    expect(chrome.value, 1);
  });

  testWidgets('a scroll to the top brings the chrome back', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(_Page(onController: (c) => chrome = c));
    await tester.fling(find.byType(ListView), const Offset(0, -600), 2000);
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(chrome.value, 1);
  });
}

class _ShortList extends StatefulWidget {
  const _ShortList({required this.onController});

  final ValueChanged<ScrollChromeController> onController;

  @override
  State<_ShortList> createState() => _ShortListState();
}

class _ShortListState extends State<_ShortList>
    with SingleTickerProviderStateMixin {
  late final ScrollChromeController chrome = ScrollChromeController(
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    widget.onController(chrome);
  }

  @override
  void dispose() {
    chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          CollapsingChrome(
            controller: chrome,
            child: const SizedBox(height: 100, width: double.infinity),
          ),
          Expanded(
            child: ScrollChromeRegion(
              controller: chrome,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: 3,
                itemExtent: 50,
                itemBuilder: (context, i) => Text('row $i'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
