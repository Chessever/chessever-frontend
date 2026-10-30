import 'dart:async';

import 'package:chessever2/screens/feed/news/news_pull_next.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Future<void> Function()? onNext,
  bool reducedMotion = false,
  bool light = false,
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      builder: (context, child) {
        ResponsiveHelper.init(context);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        );
      },
      home: Scaffold(
        body: NewsPullNext(
          onNext: onNext,
          builder: (context, footer) => CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            slivers: [
              const SliverToBoxAdapter(
                child: SizedBox(height: 1800, child: Text('Article body')),
              ),
              SliverToBoxAdapter(child: footer),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

Future<void> _bottom(WidgetTester tester) async {
  _position(tester).jumpTo(_position(tester).maxScrollExtent);
  await tester.pumpAndSettle();
}

Future<TestGesture> _pull(WidgetTester tester, {int steps = 12}) async {
  final gesture = await tester.startGesture(const Offset(160, 520));
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump(const Duration(milliseconds: 16));
  }
  return gesture;
}

void main() {
  testWidgets(
    'long pull arms progressively and release requests exactly one page',
    (tester) async {
      var calls = 0;
      await _pump(tester, onNext: () async => calls++);
      await _bottom(tester);
      final gesture = await _pull(tester);
      expect(find.text('Release for next article'), findsOneWidget);
      expect(calls, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  testWidgets('short pull settles without changing article', (tester) async {
    var calls = 0;
    await _pump(tester, onNext: () async => calls++);
    await _bottom(tester);
    final gesture = await _pull(tester, steps: 3);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      inExclusiveRange(0, 1),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('cancel and reversing an armed pull keep the current article', (
    tester,
  ) async {
    var calls = 0;
    await _pump(tester, onNext: () async => calls++);
    await _bottom(tester);
    final cancelled = await _pull(tester);
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final reversed = await _pull(tester);
    await reversed.moveBy(const Offset(0, 60));
    await tester.pump();
    await reversed.up();
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets(
    'ordinary scrolling and momentum arriving at the bottom never arm',
    (tester) async {
      var calls = 0;
      await _pump(tester, onNext: () async => calls++);
      final gesture = await _pull(tester);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, 0);
      _position(tester).jumpTo(_position(tester).maxScrollExtent - 350);
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -100),
        4000,
      );
      await tester.pumpAndSettle();
      expect(_position(tester).extentAfter, 0);
      expect(calls, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'a drag reaching the bottom counts only the remaining finger travel',
    (tester) async {
      var calls = 0;
      await _pump(tester, onNext: () async => calls++);
      _position(tester).jumpTo(_position(tester).maxScrollExtent - 250);
      await tester.pumpAndSettle();
      final gesture = await _pull(tester, steps: 15);
      expect(find.text('Release for next article'), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, 0);
      final next = await _pull(tester);
      await next.up();
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  testWidgets(
    'tap is accessible and repeated taps cannot stack a pending load',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var calls = 0;
      final done = Completer<void>();
      await _pump(
        tester,
        onNext: () {
          calls++;
          return done.future;
        },
      );
      await _bottom(tester);
      expect(find.bySemanticsLabel('Next article'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('news_next')));
      await tester.pump();
      expect(find.text('Opening next article…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('news_next')));
      await tester.pump();
      expect(calls, 1);
      done.complete();
      await tester.pumpAndSettle();
      expect(find.text('Pull up for next article'), findsOneWidget);
      semantics.dispose();
    },
  );

  for (final light in [false, true]) {
    testWidgets(
      'large text footer stays whole with reduced motion in ${light ? 'light' : 'dark'}',
      (tester) async {
        var calls = 0;
        await _pump(
          tester,
          onNext: () async => calls++,
          reducedMotion: true,
          light: light,
          scale: 2,
        );
        await _bottom(tester);
        final gesture = await _pull(tester);
        expect(find.text('Release for next article'), findsOneWidget);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('final article has no next action or pull response', (
    tester,
  ) async {
    await _pump(tester, onNext: null);
    await _bottom(tester);
    final gesture = await _pull(tester);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('news_next')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
