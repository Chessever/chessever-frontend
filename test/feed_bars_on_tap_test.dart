import 'package:chessever2/screens/feed/widgets/feed_bars_on_tap.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tap on a Feed post brings the bars back ([FeedBarsOnTap]); a press held
/// past the long-press timeout, a drag, and a tap on a part that answers taps
/// of its own ([FeedKeepsBars]: the board, the chart, the rail) do not.
void main() {
  late ScrollChromeController chrome;
  late int railTaps;

  setUp(() {
    chrome = ScrollChromeController(vsync: const TestVSync());
    railTaps = 0;
  });

  tearDown(() => chrome.dispose());

  Future<void> pumpPost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FeedBarsOnTap(
          chrome: chrome,
          child: Column(
            children: [
              // A part of the post that answers no tap: hit, but idle.
              const ColoredBox(
                key: ValueKey('caption'),
                color: Colors.transparent,
                child: SizedBox(height: 200, width: double.infinity),
              ),
              FeedKeepsBars(
                child: GestureDetector(
                  key: const ValueKey('rail'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => railTaps++,
                  child: const SizedBox(height: 200, width: double.infinity),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    chrome.hide(animate: false);
    await tester.pump();
  }

  Offset centerOf(WidgetTester tester, String key) =>
      tester.getCenter(find.byKey(ValueKey(key)));

  testWidgets('a tap brings the bars back', (tester) async {
    await pumpPost(tester);
    await tester.tapAt(centerOf(tester, 'caption'));
    await tester.pumpAndSettle();
    expect(chrome.value, 1);
  });

  testWidgets('a press held past the long-press timeout leaves them', (
    tester,
  ) async {
    await pumpPost(tester);
    await tester.longPressAt(centerOf(tester, 'caption'));
    await tester.pumpAndSettle();
    expect(chrome.value, 0);

    // The next tap is a tap again.
    await tester.tapAt(centerOf(tester, 'caption'));
    await tester.pumpAndSettle();
    expect(chrome.value, 1);
  });

  testWidgets('a drag past the touch slop leaves them', (tester) async {
    await pumpPost(tester);
    final gesture = await tester.startGesture(centerOf(tester, 'caption'));
    await gesture.moveBy(const Offset(0, 40));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(chrome.value, 0);
  });

  testWidgets('a tap on a part that keeps the bars leaves them', (
    tester,
  ) async {
    await pumpPost(tester);
    await tester.tapAt(centerOf(tester, 'rail'));
    await tester.pumpAndSettle();
    expect(railTaps, 1, reason: 'the part keeps its own tap');
    expect(chrome.value, 0);
  });
}
