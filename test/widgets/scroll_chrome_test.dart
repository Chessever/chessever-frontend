import 'dart:async';

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
    testWidgets('the content follows the finger 1:1, and the bar does too '
        'once the finger has turned '
        '(${physics?.runtimeType ?? 'default'} physics)', (tester) async {
      late ScrollChromeController chrome;
      await tester.pumpWidget(
        _Page(onController: (c) => chrome = c, physics: physics),
      );
      await tester.pumpAndSettle();
      final list = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      // Mid-list: room above and below.
      list.jumpTo(1000);
      await tester.pumpAndSettle();
      expect(chrome.value, 1);

      final gesture = await tester.startGesture(const Offset(200, 400));
      // Past the drag slop, then past the turn: the bar starts to follow.
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      while (chrome.value == 1) {
        await gesture.moveBy(const Offset(0, -2));
        await tester.pump();
      }
      final start = rowTop(tester, 26);
      final barStart = chrome.value;

      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      // The content moved exactly as far as the finger did.
      expect(rowTop(tester, 26), moreOrLessEquals(start - 40, epsilon: 1));
      // And the bar gave up that much of its height.
      expect(chrome.value, moreOrLessEquals(barStart - 0.4, epsilon: 0.02));

      // Far enough to take the bar out entirely, then into the list.
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump();
      }
      expect(chrome.value, 0);
      // Every pixel after the drag took hold reached the content once.
      expect(rowTop(tester, 26), moreOrLessEquals(start - 190, epsilon: 1.5));

      // Back up, short of the turn: the list scrolls back, the bar waits.
      var before = rowTop(tester, 26);
      await gesture.moveBy(
        const Offset(0, ScrollChromeController.listTurn - 4),
      );
      await tester.pump();
      expect(
        rowTop(tester, 26),
        moreOrLessEquals(before + ScrollChromeController.listTurn - 4),
      );
      expect(chrome.value, 0);

      // Past the turn: the bar returns with the finger.
      before = rowTop(tester, 26);
      await gesture.moveBy(const Offset(0, 34));
      await tester.pump();
      expect(rowTop(tester, 26), moreOrLessEquals(before + 34, epsilon: 1));
      expect(chrome.value, moreOrLessEquals(0.3, epsilon: 0.02));

      // Hold still before letting go, so the release is not a fling.
      await tester.pump(const Duration(milliseconds: 400));
      final atRelease = rowTop(tester, 26);
      await gesture.up();
      await tester.pumpAndSettle();
      // Let go heading back up: it settles shown, the way the reader was
      // heading (not the nearer side), on the motor spring, and the list
      // holds still under it (the spring carries it).
      expect(chrome.value, 1);
      expect(rowTop(tester, 26), moreOrLessEquals(atRelease, epsilon: 1));
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

    // A filter leaves three rows: nothing left to scroll up with. Not at
    // once (a list that empties for a moment never flashes the bars), but
    // once it has stayed that way.
    count.value = 3;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(chrome.value, 0);
    await tester.pump(ScrollChromeController.shortGrace);
    await tester.pumpAndSettle();
    expect(chrome.value, 1);
  });

  testWidgets('a list that empties for a moment never flashes the bars', (
    tester,
  ) async {
    late ScrollChromeController chrome;
    final count = ValueNotifier(200);
    addTearDown(count.dispose);
    await tester.pumpWidget(
      _Page(onController: (c) => chrome = c, itemCount: count),
    );
    // The reader has read the bars away right at the top of the list.
    chrome.hide(animate: false);
    await tester.pump();
    expect(chrome.value, 0);

    // A skeleton swapped in and out: short for two frames.
    count.value = 3;
    await tester.pump(const Duration(milliseconds: 16));
    count.value = 200;
    final values = <double>[];
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      values.add(chrome.value);
    }
    expect(values.every((v) => v == 0), isTrue, reason: '$values');
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

  testWidgets('a top bar that changes height part-way out never moves the '
      'content under the finger (S4)', (tester) async {
    late ScrollChromeController chrome;
    final barHeight = ValueNotifier<double>(100);
    await tester.pumpWidget(
      _ResizingPage(onController: (c) => chrome = c, barHeight: barHeight),
    );
    await tester.pumpAndSettle();
    final list = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    list.jumpTo(1000);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    while (chrome.value > 0.6) {
      await gesture.moveBy(const Offset(0, -4));
      await tester.pump();
    }
    expect(chrome.value, inExclusiveRange(0, 1));
    final value = chrome.value;
    final before = rowTop(tester, 26);

    // A row grows in under the bar's title, then goes again.
    barHeight.value = 140;
    await tester.pump();
    expect(chrome.value, value);
    expect(rowTop(tester, 26), closeTo(before, 0.5));
    barHeight.value = 100;
    await tester.pump();
    expect(rowTop(tester, 26), closeTo(before, 0.5));

    // The finger still drives the bar and the list 1:1 after it.
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    expect(rowTop(tester, 26), closeTo(before - 10, 0.5));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a top bar that changes height while shown moves the content '
      'as any header would', (tester) async {
    late ScrollChromeController chrome;
    final barHeight = ValueNotifier<double>(100);
    await tester.pumpWidget(
      _ResizingPage(onController: (c) => chrome = c, barHeight: barHeight),
    );
    await tester.pumpAndSettle();
    final before = rowTop(tester, 3);
    barHeight.value = 140;
    await tester.pump();
    expect(chrome.value, 1);
    expect(rowTop(tester, 3), closeTo(before + 40, 0.5));
  });

  group('stability', stabilityTests);
  group('paged', pagedTests);
  group('dock', dockTests);
}

/// [_Page] with a top bar whose height follows [barHeight].
class _ResizingPage extends StatefulWidget {
  const _ResizingPage({required this.onController, required this.barHeight});

  final ValueChanged<ScrollChromeController> onController;
  final ValueNotifier<double> barHeight;

  @override
  State<_ResizingPage> createState() => _ResizingPageState();
}

class _ResizingPageState extends State<_ResizingPage>
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
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            CollapsingChrome(
              controller: chrome,
              child: ValueListenableBuilder<double>(
                valueListenable: widget.barHeight,
                builder: (context, height, _) =>
                    SizedBox(height: height, width: double.infinity),
              ),
            ),
            Expanded(
              child: ScrollChromeRegion(
                controller: chrome,
                child: ListView.builder(
                  itemCount: 200,
                  itemExtent: 50,
                  itemBuilder: (context, i) =>
                      Text('row $i', key: ValueKey('row-$i')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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

/// A screen shaped like a root in the home shell: a [top]-tall bar folding
/// away at the top, a 60px bottom bar, a floating button, and [body] in the
/// region. [media] adjusts the window (reduced motion, a screen reader).
class _Shell extends StatefulWidget {
  const _Shell({
    super.key,
    required this.onController,
    required this.body,
    this.paged = false,
    this.media,
  });

  final ValueChanged<ScrollChromeController> onController;
  final Widget body;
  final bool paged;
  final MediaQueryData Function(MediaQueryData)? media;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with SingleTickerProviderStateMixin {
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
    final region = ScrollChromeRegion(
      controller: chrome,
      paged: widget.paged,
      child: widget.body,
    );
    return MaterialApp(
      builder: (context, child) => widget.media == null
          ? child!
          : MediaQuery(
              data: widget.media!(MediaQuery.of(context)),
              child: child!,
            ),
      home: Scaffold(
        extendBody: widget.paged,
        floatingActionButton: SlidingFabs(
          controller: chrome,
          child: SearchInkFab(onTap: () {}),
        ),
        bottomNavigationBar: CollapsingChrome(
          controller: chrome,
          edge: VerticalDirection.down,
          overlay: widget.paged,
          child: const SizedBox(
            key: ValueKey('bottom-bar'),
            height: 60,
            width: double.infinity,
          ),
        ),
        body: widget.paged
            ? Stack(
                fit: StackFit.expand,
                children: [
                  region,
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: CollapsingChrome(
                      controller: chrome,
                      child: const SizedBox(
                        key: ValueKey('top-bar'),
                        height: 100,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  CollapsingChrome(
                    controller: chrome,
                    child: const SizedBox(
                      key: ValueKey('top-bar'),
                      height: 100,
                      width: double.infinity,
                    ),
                  ),
                  Expanded(child: region),
                ],
              ),
      ),
    );
  }
}

Widget _longList({Widget? first, ScrollPhysics? physics}) => ListView.builder(
  key: const ValueKey('list'),
  physics: physics,
  itemCount: 200,
  itemExtent: first == null ? 50 : null,
  itemBuilder: (context, i) => i == 0 && first != null
      ? first
      : SizedBox(height: 50, child: Text('row $i', key: ValueKey('row-$i'))),
);

/// Pumps frame by frame until [settled] or [frames] run out, recording the
/// chrome's value after each frame.
Future<List<double>> _record(
  WidgetTester tester,
  ScrollChromeController chrome, {
  int frames = 90,
}) async {
  final values = <double>[];
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    values.add(chrome.value);
  }
  return values;
}

void stabilityTests() {
  testWidgets('a horizontal rail inside the list never moves the bars', (
    tester,
  ) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Shell(
        onController: (c) => chrome = c,
        body: _longList(
          first: SizedBox(
            height: 120,
            child: ListView.builder(
              key: const ValueKey('rail'),
              scrollDirection: Axis.horizontal,
              itemCount: 40,
              itemExtent: 120,
              itemBuilder: (context, i) => Text('card $i'),
            ),
          ),
        ),
      ),
    );
    await tester.fling(
      find.byKey(const ValueKey('rail')),
      const Offset(-300, -10),
      2000,
    );
    final values = await _record(tester, chrome);
    expect(values.every((v) => v == 1), isTrue);
  });

  testWidgets('a vertical list nested in the page never moves the bars, '
      'and its size never brings them back', (tester) async {
    late ScrollChromeController chrome;
    final innerCount = ValueNotifier(30);
    addTearDown(innerCount.dispose);
    await tester.pumpWidget(
      _Shell(
        onController: (c) => chrome = c,
        body: _longList(
          first: SizedBox(
            height: 200,
            child: ValueListenableBuilder<int>(
              valueListenable: innerCount,
              builder: (context, count, _) => ListView.builder(
                key: const ValueKey('inner'),
                itemCount: count,
                itemExtent: 40,
                itemBuilder: (context, i) => Text('inner $i'),
              ),
            ),
          ),
        ),
      ),
    );
    // Scrolling the inner list leaves the bars where they are.
    await tester.drag(
      find.byKey(const ValueKey('inner')),
      const Offset(0, -150),
    );
    await tester.pumpAndSettle();
    expect(chrome.value, 1);

    // Read on with the page: the bars go.
    await tester.flingFrom(const Offset(400, 450), const Offset(0, -500), 2000);
    await tester.pumpAndSettle();
    expect(chrome.value, 0);

    // The inner list shrinking to nothing to scroll is not the page.
    innerCount.value = 1;
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
  });

  for (final physics in <ScrollPhysics>[
    const ClampingScrollPhysics(),
    const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
  ]) {
    testWidgets('a pull at the top never flickers the bars '
        '(${physics.parent?.runtimeType ?? physics.runtimeType})', (
      tester,
    ) async {
      late ScrollChromeController chrome;
      await tester.pumpWidget(
        _Shell(
          onController: (c) => chrome = c,
          body: _longList(physics: physics),
        ),
      );
      final gesture = await tester.startGesture(const Offset(200, 400));
      final values = <double>[];
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(0, 25));
        await tester.pump(const Duration(milliseconds: 16));
        values.add(chrome.value);
      }
      await gesture.up();
      values.addAll(await _record(tester, chrome, frames: 60));
      expect(values.every((v) => v == 1), isTrue, reason: '$values');
    });
  }

  testWidgets('the bounce at the end never brings the bars back part-way', (
    tester,
  ) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Shell(
        onController: (c) => chrome = c,
        body: _longList(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
        ),
      ),
    );
    final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
    list.position.jumpTo(list.position.maxScrollExtent);
    chrome.hide(animate: false);
    await tester.pump();
    // Pull past the end, turn round inside the bounce, let go.
    final gesture = await tester.startGesture(const Offset(200, 500));
    final values = <double>[];
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
      values.add(chrome.value);
    }
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
      values.add(chrome.value);
    }
    await gesture.up();
    values.addAll(await _record(tester, chrome, frames: 60));
    expect(values.every((v) => v == 0), isTrue, reason: '$values');
  });

  for (final (distance, speed) in [
    (-40.0, 400.0),
    (-60.0, 2500.0),
    (-90.0, 900.0),
    (-140.0, 4000.0),
    (40.0, 1500.0),
  ]) {
    testWidgets('a fling of $distance at $speed settles fully shown or '
        'fully gone', (tester) async {
      late ScrollChromeController chrome;
      await tester.pumpWidget(
        _Shell(onController: (c) => chrome = c, body: _longList()),
      );
      final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
      if (distance > 0) {
        // Heading back up from mid-list with the bars gone.
        list.position.jumpTo(2000);
        await tester.pumpAndSettle();
        chrome.hide(animate: false);
        await tester.pump();
      }
      await tester.fling(find.byType(ListView), Offset(0, distance), speed);
      await tester.pumpAndSettle();
      expect(chrome.value, anyOf(0.0, 1.0));
    });
  }

  testWidgets('the app moving the list any real distance brings the bars '
      'back; its small nudges do not', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Shell(onController: (c) => chrome = c, body: _longList()),
    );
    await tester.fling(find.byType(ListView), const Offset(0, -600), 2000);
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
    final list = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;

    // A field kept in view, a row holding its place: a few pixels.
    list.jumpTo(list.pixels + 12);
    await tester.pumpAndSettle();
    expect(chrome.value, 0);

    // A jump to a round further down.
    list.jumpTo(list.pixels + 1500);
    await tester.pumpAndSettle();
    expect(chrome.value, 1);

    // Away again, then the app's scroll to the top.
    await tester.fling(find.byType(ListView), const Offset(0, -600), 2000);
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
    unawaited(
      list.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
      ),
    );
    await tester.pumpAndSettle();
    expect(chrome.value, 1);
  });

  testWidgets('a focused field in the region holds the bars while the '
      'keyboard is up', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Shell(
        onController: (c) => chrome = c,
        body: _longList(
          first: const SizedBox(
            height: 50,
            child: TextField(key: ValueKey('field')),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pump();
    await tester.fling(
      find.byKey(const ValueKey('row-8')),
      const Offset(0, -400),
      2000,
    );
    await tester.pumpAndSettle();
    expect(chrome.value, 1);

    // The keyboard goes: reading moves the bars again.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.fling(find.byType(ListView), const Offset(0, -400), 2000);
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
  });

  testWidgets('the top bar, the bottom bar and the floating button move as '
      'one', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Shell(onController: (c) => chrome = c, body: _longList()),
    );
    final window =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    Finder chromeOf(String key) => find.ancestor(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(CollapsingChrome),
    );
    final fab = find.byType(SearchInkFab);
    final fabRest = tester.getTopLeft(fab).dy;
    final gesture = await tester.startGesture(const Offset(200, 400));
    // Past the slop, then past the turn.
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -ScrollChromeController.listTurn));
    await tester.pump();
    var lastFab = fabRest;
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, -12));
      await tester.pump();
      final v = chrome.value;
      expect(v, inExclusiveRange(0, 1));
      // Both bars show the same share of their height.
      final topShown = tester.getSize(chromeOf('top-bar')).height / 100;
      final bottomShown =
          (window -
              tester.getTopLeft(find.byKey(const ValueKey('bottom-bar'))).dy) /
          60;
      expect(topShown, moreOrLessEquals(v, epsilon: 0.01));
      expect(bottomShown, moreOrLessEquals(v, epsilon: 0.01));
      // The button leaves with them.
      final fabTop = tester.getTopLeft(fab).dy;
      expect(fabTop, greaterThan(lastFab));
      lastFab = fabTop;
    }
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(chrome.value, anyOf(0.0, 1.0));
    if (chrome.value == 0) {
      expect(tester.getTopLeft(fab).dy, greaterThanOrEqualTo(window));
    } else {
      expect(tester.getTopLeft(fab).dy, fabRest);
    }
  });

  for (final (name, media) in [
    (
      'reduced motion',
      (MediaQueryData data) => data.copyWith(disableAnimations: true),
    ),
    (
      'a screen reader',
      (MediaQueryData data) => data.copyWith(accessibleNavigation: true),
    ),
  ]) {
    testWidgets('with $name the bars stay shown', (tester) async {
      late ScrollChromeController chrome;
      await tester.pumpWidget(
        _Shell(
          onController: (c) => chrome = c,
          body: _longList(),
          media: media,
        ),
      );
      await tester.fling(find.byType(ListView), const Offset(0, -600), 2000);
      await tester.pumpAndSettle();
      expect(chrome.value, 1);
      chrome.hide();
      await tester.pumpAndSettle();
      expect(chrome.value, 1);
    });
  }

  testWidgets('a bar inside a CollapsingChrome knows it is enclosed', (
    tester,
  ) async {
    late ScrollChromeController chrome;
    late bool inside;
    late bool outside;
    await tester.pumpWidget(
      _Shell(
        onController: (c) => chrome = c,
        body: Builder(
          builder: (context) {
            outside = CollapsingChrome.encloses(context);
            return CollapsingChrome(
              controller: chrome,
              child: Builder(
                builder: (context) {
                  inside = CollapsingChrome.encloses(context);
                  return const SizedBox(height: 10);
                },
              ),
            );
          },
        ),
      ),
    );
    expect(outside, isFalse);
    expect(inside, isTrue);
  });
}

void pagedTests() {
  Widget pages({PageController? controller}) => PageView.builder(
    key: const ValueKey('pages'),
    controller: controller,
    scrollDirection: Axis.vertical,
    itemCount: 10,
    itemBuilder: (context, i) =>
        Center(child: Text('page $i', key: ValueKey('page-$i'))),
  );

  testWidgets('paging on sends the bars away and paging back brings them, '
      'while the pages keep one size and page exactly', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Shell(onController: (c) => chrome = c, paged: true, body: pages()),
    );
    final size = tester.getSize(find.byKey(const ValueKey('pages')));
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;

    await tester.fling(
      find.byKey(const ValueKey('pages')),
      const Offset(0, -300),
      1500,
    );
    final values = <double>[];
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      values.add(chrome.value);
      // The page never changes size while the bars move.
      expect(tester.getSize(find.byKey(const ValueKey('pages'))), size);
    }
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
    // Never part-way back: the bars only ever leave.
    for (var i = 1; i < values.length; i++) {
      expect(values[i], lessThanOrEqualTo(values[i - 1] + 1e-9));
    }
    // Paging is exact: the drag was never spent on the bars.
    expect(position.pixels, moreOrLessEquals(size.height, epsilon: 0.01));

    await tester.fling(
      find.byKey(const ValueKey('pages')),
      const Offset(0, 300),
      1500,
    );
    await tester.pumpAndSettle();
    expect(chrome.value, 1);
    expect(position.pixels, moreOrLessEquals(0, epsilon: 0.01));
  });

  testWidgets('a swipe on that gives up before the page turns leaves the '
      'bars shown', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Shell(onController: (c) => chrome = c, paged: true, body: pages()),
    );
    final gesture = await tester.startGesture(const Offset(200, 400));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(chrome.value, 1);
  });

  /// Pages on [turns] pages with flings, the bars going with the first.
  Future<ScrollPosition> pageOn(
    WidgetTester tester,
    ScrollChromeController chrome,
    int turns,
  ) async {
    for (var i = 0; i < turns; i++) {
      await tester.fling(
        find.byKey(const ValueKey('pages')),
        const Offset(0, -300),
        1500,
      );
      await tester.pumpAndSettle();
    }
    expect(chrome.value, 0);
    return tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
  }

  testWidgets('a drag back brings the bars back at once, even when the page '
      'springs back to the post', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Shell(onController: (c) => chrome = c, paged: true, body: pages()),
    );
    final position = await pageOn(tester, chrome, 3);
    final viewport = position.viewportDimension;
    expect(position.pixels, moreOrLessEquals(3 * viewport, epsilon: 0.01));

    // A short pull back, far from turning the page: the bars come back
    // while the finger is still down.
    final gesture = await tester.startGesture(const Offset(200, 300));
    await gesture.moveBy(const Offset(0, 20));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final values = await _record(tester, chrome, frames: 30);
    expect(chrome.value, 1);
    // Straight home, never back the other way.
    for (var i = 1; i < values.length; i++) {
      expect(values[i], greaterThanOrEqualTo(values[i - 1] - 1e-9));
    }

    // Let go: the post springs back into place under the bars.
    await gesture.up();
    await tester.pumpAndSettle();
    expect(position.pixels, moreOrLessEquals(3 * viewport, epsilon: 0.01));
    expect(chrome.value, 1);

    // And reading on sends them away again.
    await tester.fling(
      find.byKey(const ValueKey('pages')),
      const Offset(0, -300),
      1500,
    );
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
    expect(position.pixels, moreOrLessEquals(4 * viewport, epsilon: 0.01));
  });

  testWidgets('a finger wobbling on the halfway line never moves the bars', (
    tester,
  ) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Shell(onController: (c) => chrome = c, paged: true, body: pages()),
    );
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final half = position.viewportDimension / 2;
    final gesture = await tester.startGesture(const Offset(200, 500));
    await gesture.moveBy(const Offset(0, -20));
    while (position.pixels < half) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final values = <double>[];
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(Offset(0, i.isEven ? 10 : -10));
      await tester.pump(const Duration(milliseconds: 16));
      values.add(chrome.value);
    }
    values.addAll(await _record(tester, chrome, frames: 20));
    expect(values.every((v) => v == 1), isTrue, reason: '$values');
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('past the commit line the bars go, and a wobble there never '
      'brings them part-way back', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Shell(onController: (c) => chrome = c, paged: true, body: pages()),
    );
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final line =
        position.viewportDimension * ScrollChromeController.pagedCommit;
    final gesture = await tester.startGesture(const Offset(200, 560));
    await gesture.moveBy(const Offset(0, -20));
    while (position.pixels < line + 10) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final values = <double>[];
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(Offset(0, i.isEven ? 10 : -10));
      await tester.pump(const Duration(milliseconds: 16));
      values.add(chrome.value);
    }
    values.addAll(await _record(tester, chrome, frames: 30));
    // Only ever leaving, and all the way, with the finger still down.
    for (var i = 1; i < values.length; i++) {
      expect(values[i], lessThanOrEqualTo(values[i - 1] + 1e-9));
    }
    expect(values.last, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
  });

  testWidgets('hidden bars brought back by a drag stay while the finger '
      'wobbles', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Shell(onController: (c) => chrome = c, paged: true, body: pages()),
    );
    await pageOn(tester, chrome, 1);
    final gesture = await tester.startGesture(const Offset(200, 200));
    await gesture.moveBy(const Offset(0, 20));
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final values = <double>[];
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(Offset(0, i.isEven ? -10 : 10));
      await tester.pump(const Duration(milliseconds: 16));
      values.add(chrome.value);
    }
    values.addAll(await _record(tester, chrome, frames: 30));
    for (var i = 1; i < values.length; i++) {
      expect(values[i], greaterThanOrEqualTo(values[i - 1] - 1e-9));
    }
    expect(values.last, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(chrome.value, 1);
  });

  testWidgets('a quick fling back from a short drag brings the bars with the '
      'page before', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Shell(onController: (c) => chrome = c, paged: true, body: pages()),
    );
    final position = await pageOn(tester, chrome, 2);
    final viewport = position.viewportDimension;
    // Under the turn distance, but fast enough to turn the page: the
    // finger alone never counts as heading back, the fling into the page
    // before does.
    final gesture = await tester.startGesture(const Offset(200, 300));
    var t = 0;
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(
        const Offset(0, 4),
        timeStamp: Duration(milliseconds: t += 4),
      );
    }
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(
        const Offset(0, 2),
        timeStamp: Duration(milliseconds: t += 2),
      );
    }
    await tester.pump();
    expect(
      2 * viewport - position.pixels,
      lessThan(ScrollChromeController.pagedTurn),
    );
    expect(chrome.value, 0);
    await gesture.up(timeStamp: Duration(milliseconds: t += 2));
    await tester.pumpAndSettle();
    expect(position.pixels, moreOrLessEquals(viewport, epsilon: 0.01));
    expect(chrome.value, 1);
  });

  testWidgets('a swipe on that gives up springs back without bringing '
      'hidden bars', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Shell(onController: (c) => chrome = c, paged: true, body: pages()),
    );
    final position = await pageOn(tester, chrome, 2);
    final viewport = position.viewportDimension;
    // On, well short of the commit line, then let go: the page springs back
    // on its own, which is not the reader heading back.
    final gesture = await tester.startGesture(const Offset(200, 500));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, -15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    final values = await _record(tester, chrome, frames: 60);
    expect(values.every((v) => v == 0), isTrue, reason: '$values');
    expect(position.pixels, moreOrLessEquals(2 * viewport, epsilon: 0.01));
  });

  testWidgets('the app turning a page on its own leaves the bars; going back '
      'to the first page shows them', (tester) async {
    late ScrollChromeController chrome;
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _Shell(
        onController: (c) => chrome = c,
        paged: true,
        body: pages(controller: controller),
      ),
    );
    unawaited(
      controller.animateToPage(
        1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
      ),
    );
    await tester.pumpAndSettle();
    expect(chrome.value, 1);

    await tester.fling(
      find.byKey(const ValueKey('pages')),
      const Offset(0, -300),
      1500,
    );
    await tester.pumpAndSettle();
    expect(chrome.value, 0);

    controller.jumpToPage(0);
    await tester.pumpAndSettle();
    expect(chrome.value, 1);
  });

  testWidgets('an overlay bar keeps its place in the layout while it '
      'slides away', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Shell(onController: (c) => chrome = c, paged: true, body: pages()),
    );
    final bar = find.byKey(const ValueKey('bottom-bar'));
    final slot = find.ancestor(
      of: bar,
      matching: find.byType(CollapsingChrome),
    );
    final rest = tester.getTopLeft(bar).dy;
    final size = tester.getSize(slot);
    chrome.hide(animate: false);
    await tester.pump();
    expect(tester.getSize(slot), size);
    expect(tester.getTopLeft(bar).dy, rest + 60);
  });
}

/// A root over a dock: a 100px top bar folding away over a long list, and
/// at the bottom a dock that only changes shape with the chrome (56 tall
/// shown, 44 away) and never leaves, so it reports nothing. The floating
/// button rides above it by [ride].
class _Dock extends StatefulWidget {
  const _Dock({super.key, required this.onController, this.ride, this.onTap});

  final ValueChanged<ScrollChromeController> onController;
  final double? ride;
  final VoidCallback? onTap;

  @override
  State<_Dock> createState() => _DockState();
}

class _DockState extends State<_Dock> with SingleTickerProviderStateMixin {
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
    final ride = widget.ride;
    return MaterialApp(
      home: Scaffold(
        extendBody: true,
        floatingActionButtonLocation: ride == null
            ? null
            : RidingFabLocation(ride),
        floatingActionButton: SlidingFabs(
          controller: chrome,
          ride: ride,
          child: SearchInkFab(onTap: widget.onTap),
        ),
        bottomNavigationBar: SizedBox(
          height: 78,
          child: AnimatedBuilder(
            animation: chrome,
            builder: (context, _) => Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                key: const ValueKey('capsule'),
                height: 44 + 12 * chrome.value,
                width: 200,
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            CollapsingChrome(
              controller: chrome,
              child: const SizedBox(height: 100, width: double.infinity),
            ),
            Expanded(
              child: ScrollChromeRegion(controller: chrome, child: _longList()),
            ),
          ],
        ),
      ),
    );
  }
}

void dockTests() {
  testWidgets('riding buttons ride down with the chrome and back, in view, '
      'announced and tappable the whole way', (tester) async {
    late ScrollChromeController chrome;
    var taps = 0;
    await tester.pumpWidget(
      _Dock(onController: (c) => chrome = c, ride: 12, onTap: () => taps++),
    );
    final fab = find.byType(SearchInkFab);
    final capsule = find.byKey(const ValueKey('capsule'));
    final rest = tester.getRect(fab);
    final restGap = tester.getRect(capsule).top - rest.bottom;

    chrome.hide();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final mid = tester.getRect(fab);
    expect(mid.top, inExclusiveRange(rest.top, rest.top + 12));
    await tester.tapAt(mid.bottomCenter - const Offset(0, 2));
    expect(taps, 1);

    await tester.pumpAndSettle();
    expect(chrome.value, 0);
    final away = tester.getRect(fab);
    expect(away.top, moreOrLessEquals(rest.top + 12));
    expect(away.size, rest.size);
    // Its foot, below where it rested, still takes the tap.
    await tester.tapAt(away.bottomCenter - const Offset(0, 2));
    expect(taps, 2);
    expect(
      find.ancestor(
        of: fab,
        matching: find.byWidgetPredicate(
          (w) =>
              (w is IgnorePointer && w.ignoring) ||
              (w is ExcludeSemantics && w.excluding),
        ),
      ),
      findsNothing,
    );
    // The dock shrank under it by as much and stayed: the same gap.
    expect(tester.getSize(capsule).height, 44);
    expect(
      tester.getRect(capsule).top - away.bottom,
      moreOrLessEquals(restGap),
    );

    chrome.show();
    await tester.pumpAndSettle();
    expect(tester.getRect(fab), rest);
  });

  testWidgets('a riding slot rests the buttons where the end-float corner '
      'puts them', (tester) async {
    await tester.pumpWidget(
      _Dock(key: const ValueKey('plain'), onController: (_) {}),
    );
    final plain = tester.getRect(find.byType(SearchInkFab));
    await tester.pumpWidget(
      _Dock(key: const ValueKey('riding'), onController: (_) {}, ride: 12),
    );
    expect(tester.getRect(find.byType(SearchInkFab)), plain);
    expect(const RidingFabLocation(12), const RidingFabLocation(12));
    expect(const RidingFabLocation(12), isNot(const RidingFabLocation(8)));
  });

  testWidgets('only bars that fold out of the layout count toward the room '
      'a list needs', (tester) async {
    late ScrollChromeController chrome;
    // A bottom bar that folds: both bars' travel, and room to spare.
    await tester.pumpWidget(
      _Shell(
        key: const ValueKey('fold'),
        onController: (c) => chrome = c,
        body: _longList(),
      ),
    );
    expect(chrome.minRange, 100 + 60 + 48);
    // A bottom bar sliding over the content: the top bar's alone.
    await tester.pumpWidget(
      _Shell(
        key: const ValueKey('overlay'),
        onController: (c) => chrome = c,
        paged: true,
        body: _longList(),
      ),
    );
    expect(chrome.minRange, ScrollChromeController.minScrollRange);
    // A dock that never leaves reports nothing; the chrome still moves with
    // the top bar.
    await tester.pumpWidget(
      _Dock(key: const ValueKey('dock'), onController: (c) => chrome = c),
    );
    expect(chrome.minRange, ScrollChromeController.minScrollRange);
    await tester.fling(find.byType(ListView), const Offset(0, -600), 2000);
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
  });

  for (final reports in [true, false]) {
    testWidgets('a lone bottom bar that ${reports ? 'reports' : 'does not '
                  'report'} its height ${reports ? 'leaves' : 'stays'} as the '
        'list scrolls', (tester) async {
      late ScrollChromeController chrome;
      await tester.pumpWidget(
        _BottomOnly(onController: (c) => chrome = c, reports: reports),
      );
      await tester.fling(find.byType(ListView), const Offset(0, -600), 2000);
      await tester.pumpAndSettle();
      expect(chrome.value, reports ? 0 : 1);
    });
  }
}

/// A list under a lone bottom bar sliding over it, with no top bar.
class _BottomOnly extends StatefulWidget {
  const _BottomOnly({required this.onController, required this.reports});

  final ValueChanged<ScrollChromeController> onController;
  final bool reports;

  @override
  State<_BottomOnly> createState() => _BottomOnlyState();
}

class _BottomOnlyState extends State<_BottomOnly>
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
    return MaterialApp(
      home: Scaffold(
        extendBody: true,
        bottomNavigationBar: CollapsingChrome(
          controller: chrome,
          edge: VerticalDirection.down,
          overlay: true,
          reportsExtent: widget.reports,
          child: const SizedBox(height: 60, width: double.infinity),
        ),
        body: ScrollChromeRegion(controller: chrome, child: _longList()),
      ),
    );
  }
}
