import 'dart:async';

import 'package:chessever2/screens/feed/widgets/feed_pull_refresh.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Future<void> Function() onRefresh,
  bool enabled = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: FeedPullRefresh(
          onRefresh: onRefresh,
          enabled: enabled,
          child: PageView.builder(
            key: const ValueKey('pages'),
            scrollDirection: Axis.vertical,
            physics: feedPagePhysics,
            itemCount: 3,
            itemBuilder: (_, i) => Center(child: Text('page $i')),
          ),
        ),
      ),
    ),
  );
}

double _pageTop(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const ValueKey('pages'))).dy;

void main() {
  testWidgets('a long pull refreshes; the page springs home after', (
    tester,
  ) async {
    var calls = 0;
    await _pump(tester, onRefresh: () async => calls++);
    final rest = _pageTop(tester);

    final gesture = await tester.startGesture(const Offset(200, 200));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // The page follows the finger, with friction.
    final pulled = _pageTop(tester) - rest;
    expect(pulled, greaterThan(64));
    expect(pulled, lessThan(400));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(_pageTop(tester), moreOrLessEquals(rest, epsilon: 0.5));
  });

  testWidgets('a short pull only springs back', (tester) async {
    var calls = 0;
    await _pump(tester, onRefresh: () async => calls++);
    final rest = _pageTop(tester);
    final gesture = await tester.startGesture(const Offset(200, 200));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(_pageTop(tester), moreOrLessEquals(rest, epsilon: 0.5));
  });

  testWidgets('a slow refresh holds the page, then lets go', (tester) async {
    final done = Completer<void>();
    await _pump(tester, onRefresh: () => done.future);
    final rest = _pageTop(tester);
    final gesture = await tester.startGesture(const Offset(200, 200));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_pageTop(tester) - rest, moreOrLessEquals(56, epsilon: 2));
    expect(find.bySemanticsLabel('Refreshing Feed'), findsOneWidget);

    done.complete();
    await tester.pumpAndSettle();
    expect(_pageTop(tester), moreOrLessEquals(rest, epsilon: 0.5));
  });

  testWidgets('no pull while something on the page holds the finger', (
    tester,
  ) async {
    var calls = 0;
    await _pump(tester, onRefresh: () async => calls++, enabled: false);
    final rest = _pageTop(tester);
    final gesture = await tester.startGesture(const Offset(200, 200));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_pageTop(tester), rest);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('a ready refresh never holds: the page rises straight home', (
    tester,
  ) async {
    await _pump(tester, onRefresh: () async {});
    final rest = _pageTop(tester);
    final gesture = await tester.startGesture(const Offset(200, 200));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    var last = _pageTop(tester) - rest;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.bySemanticsLabel('Refreshing Feed'), findsNothing);
      final now = _pageTop(tester) - rest;
      // Only ever on its way home (a spring may overshoot by a hair).
      expect(now, lessThanOrEqualTo(last + 0.5));
      last = now;
    }
    await tester.pumpAndSettle();
    expect(_pageTop(tester), moreOrLessEquals(rest, epsilon: 0.5));
  });
}
