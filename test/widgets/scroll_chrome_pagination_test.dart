// The scroll chrome around pagination and the edges of a list: every failure
// the chrome audit proved (F1-F7, F9) pinned as it must behave now. The
// list pages itself the way the app's lists do: it asks for the next page
// near its end, the page lands on a timer, and its footer changes height
// between idle, loading and the end.

import 'dart:async';

import 'package:chessever2/screens/favorites/widgets/settling_scroll_controller.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

const double _row = 50;

/// The bouncing physics Favorites, Countrymen, Today and others set, and
/// the clamping physics Android lists get by default.
final Map<String, ScrollPhysics?> _physics = {
  'clamping': null,
  'bouncing': const AlwaysScrollableScrollPhysics(
    parent: BouncingScrollPhysics(),
  ),
};

/// A list that pages itself: [threshold] from its end it asks for the next
/// page, which lands [delay] later. Its footer is [footerIdle] tall while
/// more may come, [footerLoading] while a page loads, [footerEnd] at the
/// end.
class _Feed extends StatefulWidget {
  const _Feed({
    required this.physics,
    this.delay = const Duration(milliseconds: 150),
    this.onState,
  });

  final ScrollPhysics? physics;
  final Duration delay;
  final ValueChanged<_FeedState>? onState;

  static const int firstPage = 40;
  static const int pageSize = 30;
  static const int maxPages = 5;
  static const double threshold = 400;
  static const double footerIdle = 60;
  static const double footerLoading = 72;
  static const double footerEnd = 48;

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> {
  final ScrollController controller = ScrollController();
  int count = _Feed.firstPage;
  bool loading = false;
  bool hasMore = true;
  int pages = 1;
  bool autoLoad = true;
  int landed = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onScroll);
    widget.onState?.call(this);
  }

  void _onScroll() {
    if (!autoLoad) return;
    final p = controller.position;
    if (p.maxScrollExtent - p.pixels <= _Feed.threshold &&
        !loading &&
        hasMore) {
      loadMore();
    }
  }

  void loadMore() {
    setState(() => loading = true);
    _timer = Timer(widget.delay, land);
  }

  void land() {
    if (!mounted) return;
    setState(() {
      count += _Feed.pageSize;
      loading = false;
      pages++;
      landed++;
      hasMore = pages < _Feed.maxPages;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      physics: widget.physics,
      itemCount: count + 1,
      itemBuilder: (context, i) {
        if (i == count) {
          final h = loading
              ? _Feed.footerLoading
              : hasMore
              ? _Feed.footerIdle
              : _Feed.footerEnd;
          return SizedBox(height: h, key: const ValueKey('footer'));
        }
        return SizedBox(
          height: _row,
          child: Text('row $i', key: ValueKey('row-$i')),
        );
      },
    );
  }
}

/// A root in the home shell: a 100px top bar and a 60px bottom bar, both
/// folding out of the layout, over [body].
class _Shell extends StatefulWidget {
  const _Shell({required this.onController, required this.body});

  final ValueChanged<ScrollChromeController> onController;
  final Widget body;

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
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: CollapsingChrome(
          controller: chrome,
          edge: VerticalDirection.down,
          child: const SizedBox(height: 60, width: double.infinity),
        ),
        body: Column(
          children: [
            CollapsingChrome(
              controller: chrome,
              child: const SizedBox(height: 100, width: double.infinity),
            ),
            Expanded(
              child: ScrollChromeRegion(controller: chrome, child: widget.body),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pumps [frames] frames of 16ms, recording the chrome's value after each.
Future<List<double>> _record(
  WidgetTester tester,
  ScrollChromeController chrome, {
  int frames = 90,
  void Function()? each,
}) async {
  final values = <double>[];
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    values.add(chrome.value);
    each?.call();
  }
  return values;
}

/// The bars only ever left (or only ever came), never turned round.
void _expectOneWay(List<double> values, {required bool leaving}) {
  for (var i = 1; i < values.length; i++) {
    if (leaving) {
      expect(values[i], lessThanOrEqualTo(values[i - 1] + 1e-9), reason: '$i');
    } else {
      expect(
        values[i],
        greaterThanOrEqualTo(values[i - 1] - 1e-9),
        reason: '$i',
      );
    }
  }
}

void main() {
  setUp(() => ResponsiveHelper.initFromSize(const Size(393, 852)));

  Future<(ScrollChromeController, _FeedState)> pumpFeed(
    WidgetTester tester, {
    required ScrollPhysics? physics,
    Duration delay = const Duration(milliseconds: 150),
    bool autoLoad = true,
  }) async {
    late ScrollChromeController chrome;
    late _FeedState feed;
    await tester.pumpWidget(
      _Shell(
        onController: (c) => chrome = c,
        body: _Feed(physics: physics, delay: delay, onState: (s) => feed = s),
      ),
    );
    feed.autoLoad = autoLoad;
    return (chrome, feed);
  }

  for (final MapEntry(key: name, value: physics) in _physics.entries) {
    group(name, () {
      testWidgets('F1: a short, slow first scroll from the top is never '
          'undone', (tester) async {
        final (chrome, feed) = await pumpFeed(
          tester,
          physics: physics,
          autoLoad: false,
        );
        final pos = feed.controller.position;
        final gesture = await tester.startGesture(const Offset(200, 400));
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
        for (var i = 0; i < 7; i++) {
          await gesture.moveBy(const Offset(0, -10));
          await tester.pump(const Duration(milliseconds: 16));
        }
        // Held still: the let-go is no fling.
        await tester.pump(const Duration(milliseconds: 300));
        expect(chrome.value, inExclusiveRange(0, 1));
        final row = find.byKey(const ValueKey('row-3'));
        var lastY = tester.getTopLeft(row).dy;
        await gesture.up();
        final values = await _record(
          tester,
          chrome,
          frames: 50,
          each: () {
            // Never pushed above its first row, so nothing springs back.
            expect(pos.pixels, greaterThanOrEqualTo(pos.minScrollExtent));
            // The content goes up with the reader, never back down.
            final y = tester.getTopLeft(row).dy;
            expect(y, lessThanOrEqualTo(lastY + 0.01));
            lastY = y;
          },
        );
        // Settled away, the way the reader was heading.
        _expectOneWay(values, leaving: true);
        expect(values.last, 0);

        // A page landing under it now changes nothing.
        feed.land();
        await tester.pumpAndSettle();
        expect(chrome.value, 0);
        expect(pos.pixels, greaterThanOrEqualTo(pos.minScrollExtent));
      });

      testWidgets('F4: a let-go settles the way the finger was heading, '
          'not on the nearer side', (tester) async {
        final (chrome, feed) = await pumpFeed(
          tester,
          physics: physics,
          autoLoad: false,
        );
        final pos = feed.controller.position;
        pos.jumpTo(800);
        await tester.pumpAndSettle();
        expect(chrome.value, 1);

        // On by 45: the bars are still more than half shown at the let-go.
        var gesture = await tester.startGesture(const Offset(200, 400));
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
        for (var i = 0; i < 9; i++) {
          await gesture.moveBy(const Offset(0, -5));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 300));
        expect(chrome.value, greaterThan(0.5));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(chrome.value, 0);

        // Back by 45: the bars are still more than half away.
        gesture = await tester.startGesture(const Offset(200, 300));
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
        for (var i = 0; i < 9; i++) {
          await gesture.moveBy(const Offset(0, 5));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 300));
        expect(chrome.value, lessThan(0.5));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(chrome.value, 1);

        // On, then a wobble back short of the turn: still on.
        gesture = await tester.startGesture(const Offset(200, 400));
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
        for (var i = 0; i < 6; i++) {
          await gesture.moveBy(const Offset(0, -10));
          await tester.pump(const Duration(milliseconds: 16));
        }
        final before = chrome.value;
        await gesture.moveBy(
          const Offset(0, ScrollChromeController.listTurn - 6),
        );
        await tester.pump(const Duration(milliseconds: 16));
        // The wobble never moved the bars back.
        expect(chrome.value, before);
        await tester.pump(const Duration(milliseconds: 300));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(chrome.value, 0);
      });

      for (final delayMs in [40, 120, 250, 700]) {
        testWidgets('a fling into the end of a page, the next page landing '
            '${delayMs}ms in: the bars only ever leave', (tester) async {
          final (chrome, feed) = await pumpFeed(
            tester,
            physics: physics,
            delay: Duration(milliseconds: delayMs),
          );
          final pos = feed.controller.position;
          pos.jumpTo(pos.maxScrollExtent - 900);
          await tester.pumpAndSettle();
          chrome.show(animate: false);
          await tester.pump();
          await tester.fling(
            find.byType(ListView),
            const Offset(0, -300),
            3000,
          );
          final values = await _record(tester, chrome);
          await tester.pumpAndSettle();
          expect(feed.landed, greaterThan(0));
          _expectOneWay(values, leaving: true);
          expect(chrome.value, 0);
        });

        testWidgets('a quick flick near the end, the bars part-way at the '
            'let-go, the page landing ${delayMs}ms in: they leave and '
            'stay away', (tester) async {
          final (chrome, feed) = await pumpFeed(
            tester,
            physics: physics,
            delay: Duration(milliseconds: delayMs),
          );
          final pos = feed.controller.position;
          pos.jumpTo(pos.maxScrollExtent - 150);
          await tester.pumpAndSettle();
          chrome.show(animate: false);
          await tester.pump();
          await tester.fling(find.byType(ListView), const Offset(0, -60), 2500);
          final values = await _record(tester, chrome, frames: 70);
          await tester.pumpAndSettle();
          _expectOneWay(values, leaving: true);
          expect(chrome.value, 0);
        });

        testWidgets('with the bars away, a fling into the end and the page '
            'landing ${delayMs}ms in never bring them back', (tester) async {
          final (chrome, feed) = await pumpFeed(
            tester,
            physics: physics,
            delay: Duration(milliseconds: delayMs),
          );
          final pos = feed.controller.position;
          pos.jumpTo(pos.maxScrollExtent - 900);
          await tester.pumpAndSettle();
          chrome.hide(animate: false);
          await tester.pump();
          await tester.fling(
            find.byType(ListView),
            const Offset(0, -300),
            3000,
          );
          final values = await _record(tester, chrome);
          await tester.pumpAndSettle();
          expect(values.every((v) => v == 0), isTrue, reason: '$values');
          expect(chrome.value, 0);
        });
      }

      testWidgets('F5: the app nudging the list never brings the bars '
          'back', (tester) async {
        final (chrome, feed) = await pumpFeed(
          tester,
          physics: physics,
          autoLoad: false,
        );
        final pos = feed.controller.position;
        pos.jumpTo(1200);
        await tester.pumpAndSettle();
        chrome.hide(animate: false);
        await tester.pump();

        // Rows arrived above: the screen keeps the reader's place.
        pos.jumpTo(pos.pixels + 150);
        await tester.pumpAndSettle();
        expect(chrome.value, 0);
        // A nudge up.
        pos.jumpTo(pos.pixels - 2);
        await tester.pumpAndSettle();
        expect(chrome.value, 0);
        // An edit grid scrolling under a lifted card, a step a frame.
        final values = <double>[];
        for (var i = 0; i < 20; i++) {
          pos.jumpTo(pos.pixels - 16);
          await tester.pump(const Duration(milliseconds: 16));
          values.add(chrome.value);
        }
        expect(values.every((v) => v == 0), isTrue, reason: '$values');
      });
    });
  }

  testWidgets('F2: at the end of a page a push for more sends the bars away '
      'on let-go, and the list stays at its end (clamping)', (tester) async {
    final (chrome, feed) = await pumpFeed(
      tester,
      physics: const ClampingScrollPhysics(),
      autoLoad: false,
    );
    final pos = feed.controller.position;
    pos.jumpTo(pos.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(chrome.value, 1);

    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    final pushing = <double>[];
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump();
      pushing.add(chrome.value);
    }
    // A finger past the end never moves the bars.
    expect(
      pushing.every((v) => v == pushing.first),
      isTrue,
      reason: '$pushing',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    final values = await _record(tester, chrome, frames: 40);
    _expectOneWay(values, leaving: true);
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
    // At its end, with nothing to spring back.
    expect(pos.pixels, moreOrLessEquals(pos.maxScrollExtent, epsilon: 0.5));
    final settled = pos.pixels;
    await tester.pump(const Duration(milliseconds: 500));
    expect(pos.pixels, settled);
  });

  testWidgets('F2: near the end a drag past it holds the bars where they are '
      'and the let-go sends them away (bouncing)', (tester) async {
    final (chrome, feed) = await pumpFeed(
      tester,
      physics: _physics['bouncing'],
      autoLoad: false,
    );
    final pos = feed.controller.position;
    pos.jumpTo(pos.maxScrollExtent - 40);
    await tester.pumpAndSettle();
    expect(chrome.value, 1);

    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    final pushing = <double>[];
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump();
      pushing.add(chrome.value);
    }
    _expectOneWay(pushing, leaving: true);
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    final values = await _record(tester, chrome, frames: 60);
    // Never snapped back to shown.
    _expectOneWay([pushing.last, ...values], leaving: true);
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
  });

  testWidgets('F3: a flick back up out of the end bounce brings the bars '
      '(bouncing)', (tester) async {
    final (chrome, feed) = await pumpFeed(
      tester,
      physics: _physics['bouncing'],
      autoLoad: false,
    );
    final pos = feed.controller.position;
    pos.jumpTo(pos.maxScrollExtent);
    await tester.pumpAndSettle();
    chrome.hide(animate: false);
    await tester.pump();

    var ts = Duration.zero;
    final gesture = await tester.startGesture(const Offset(200, 300));
    // Past the end...
    for (var i = 0; i < 6; i++) {
      ts += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(0, -15), timeStamp: ts);
      await tester.pump(const Duration(milliseconds: 16));
    }
    // ...then round, and a fast flick up.
    for (var i = 0; i < 6; i++) {
      ts += const Duration(milliseconds: 8);
      await gesture.moveBy(const Offset(0, 25), timeStamp: ts);
      await tester.pump(const Duration(milliseconds: 8));
    }
    await gesture.up(timeStamp: ts + const Duration(milliseconds: 4));
    final values = await _record(tester, chrome, frames: 24);
    _expectOneWay(values, leaving: false);
    // Home on the bars' own spring while the fling still runs: not frozen
    // until the list comes to rest.
    expect(values.last, 1);
    final before = pos.pixels;
    await tester.pump(const Duration(milliseconds: 16));
    expect(pos.pixels, lessThan(before));
    await tester.pumpAndSettle();
    expect(chrome.value, 1);
  });

  testWidgets('a list thrown far past its end springs back to its end, '
      'never past its top, while the bars leave (bouncing)', (tester) async {
    final (chrome, feed) = await pumpFeed(
      tester,
      physics: _physics['bouncing'],
      autoLoad: false,
    );
    final pos = feed.controller.position;
    // One move far past the end: the bounce comes back fast.
    await tester.drag(find.byType(ListView), const Offset(0, -12000));
    expect(pos.pixels, greaterThan(pos.maxScrollExtent));
    final values = await _record(
      tester,
      chrome,
      frames: 120,
      each: () => expect(pos.pixels, greaterThanOrEqualTo(pos.minScrollExtent)),
    );
    _expectOneWay(values, leaving: true);
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
    expect(pos.pixels, moreOrLessEquals(pos.maxScrollExtent, epsilon: 0.5));
  });

  testWidgets('F9: a page landing during the end bounce never moves the '
      'bars (bouncing)', (tester) async {
    final (chrome, feed) = await pumpFeed(
      tester,
      physics: _physics['bouncing'],
      delay: const Duration(milliseconds: 250),
    );
    final pos = feed.controller.position;
    pos.jumpTo(pos.maxScrollExtent - 300);
    await tester.pumpAndSettle();
    chrome.hide(animate: false);
    await tester.pump();
    await tester.fling(find.byType(ListView), const Offset(0, -300), 3000);
    final values = await _record(tester, chrome);
    expect(feed.landed, greaterThan(0));
    expect(values.every((v) => v == 0), isTrue, reason: '$values');
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
  });

  testWidgets('F6: a list rebuilt at its top brings the bars back', (
    tester,
  ) async {
    late ScrollChromeController chrome;
    final key = ValueNotifier(0);
    addTearDown(key.dispose);
    await tester.pumpWidget(
      _Shell(
        onController: (c) => chrome = c,
        body: ValueListenableBuilder<int>(
          valueListenable: key,
          builder: (context, k, _) => ListView.builder(
            key: ValueKey('list-$k'),
            itemCount: 100,
            itemExtent: _row,
            itemBuilder: (context, i) => Text('row $i'),
          ),
        ),
      ),
    );
    await tester.fling(find.byType(ListView), const Offset(0, -600), 2000);
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
    // A filter, a search or a reload rebuilds the list from its top.
    key.value = 1;
    await tester.pumpAndSettle();
    final pos = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(pos.pixels, 0);
    expect(chrome.value, 1);
  });

  testWidgets('a list rebuilt while the bars still settle over it never '
      'breaks the settle', (tester) async {
    late ScrollChromeController chrome;
    final key = ValueNotifier(0);
    addTearDown(key.dispose);
    await tester.pumpWidget(
      _Shell(
        onController: (c) => chrome = c,
        body: ValueListenableBuilder<int>(
          valueListenable: key,
          builder: (context, k, _) => ScrollablePositionedList.builder(
            key: ValueKey('list-$k'),
            itemCount: 200,
            initialScrollIndex: 20,
            initialAlignment: 0.2,
            itemBuilder: (context, i) =>
                SizedBox(height: 60, child: Text('$i')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Reading on, then a let-go: the bars spring away, carrying the list.
    final gesture = await tester.startGesture(const Offset(200, 400));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(chrome.value, inExclusiveRange(0, 1));
    // A reload swaps the list mid-spring.
    key.value = 1;
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(chrome.value, 0);
  });

  testWidgets('F6: a list the app puts back at its top without a scroll '
      'brings the bars back', (tester) async {
    late ScrollChromeController chrome;
    final controller = SettlingScrollController();
    addTearDown(controller.dispose);
    final count = ValueNotifier(120);
    addTearDown(count.dispose);
    await tester.pumpWidget(
      _Shell(
        onController: (c) => chrome = c,
        body: ValueListenableBuilder<int>(
          valueListenable: count,
          // The games change: the rows are laid out again.
          builder: (context, n, _) => ListView.builder(
            controller: controller,
            itemCount: n,
            itemExtent: n == 120 ? _row : _row + 4,
            itemBuilder: (context, i) => Text('row $i'),
          ),
        ),
      ),
    );
    final pos = controller.position;
    pos.jumpTo(1500);
    await tester.pumpAndSettle();
    chrome.hide(animate: false);
    await tester.pump();
    expect(chrome.value, 0);

    // A filter lands: the games change and the list settles at its top in
    // the same layout, with no scroll.
    controller.settleAt(0);
    count.value = 100;
    await tester.pumpAndSettle();
    expect(pos.pixels, 0);
    expect(chrome.value, 1);
  });

  for (final alignment in [0.0, 0.1, 0.4]) {
    testWidgets('F7: an anchored list (alignment $alignment) follows the '
        'finger exactly while the bars fold', (tester) async {
      late ScrollChromeController chrome;
      await tester.pumpWidget(
        _Shell(
          onController: (c) => chrome = c,
          body: ScrollablePositionedList.builder(
            itemCount: 200,
            initialScrollIndex: 40,
            initialAlignment: alignment,
            itemBuilder: (context, i) => SizedBox(
              height: 60,
              child: Text('spl $i', key: ValueKey('spl-$i')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ref = find.byKey(const ValueKey('spl-42'));
      final rest = tester.getTopLeft(ref).dy;
      final gesture = await tester.startGesture(const Offset(200, 400));
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 16));
      final start = tester.getTopLeft(ref).dy;
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -10));
        await tester.pump(const Duration(milliseconds: 16));
        // Step by step, not only in total.
        expect(
          tester.getTopLeft(ref).dy,
          moreOrLessEquals(start - 10.0 * (i + 1), epsilon: 1),
        );
      }
      // The bars took the content's travel past the turn.
      final travel = rest - tester.getTopLeft(ref).dy;
      expect(
        chrome.value,
        moreOrLessEquals(
          1 - (travel - ScrollChromeController.listTurn) / 100,
          epsilon: 0.02,
        ),
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });
  }

  testWidgets('a list that scrolls less than the bars need never moves '
      'them', (tester) async {
    late ScrollChromeController chrome;
    await tester.pumpWidget(
      _Shell(
        onController: (c) => chrome = c,
        // 180 of range with the bars shown: above the old floor, short of
        // the bars' 160 of fold and room to spare.
        body: LayoutBuilder(
          builder: (context, box) =>
              ListView(children: [SizedBox(height: box.maxHeight + 180)]),
        ),
      ),
    );
    final pos = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(
      pos.maxScrollExtent,
      inExclusiveRange(ScrollChromeController.minScrollRange, chrome.minRange),
    );
    expect(chrome.minRange, 100 + 60 + 48);
    await tester.fling(find.byType(ListView), const Offset(0, -300), 2000);
    await tester.pumpAndSettle();
    expect(chrome.value, 1);
  });
}
