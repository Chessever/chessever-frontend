import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'event_video_test.dart' show FakeVideoRepository, fixtureVideos;
import 'event_video_widgets_test.dart' show FakePlayer, harness, manyVideos;

void main() {
  testWidgets('selector minimizes without moving or reloading the player', (
    tester,
  ) async {
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
    );
    final player = FakePlayer();
    await tester.pumpWidget(harness(session, player));
    await tester.pump();
    final surface = find.byKey(const ValueKey('event_video_surface'));
    final flags = find.byKey(const ValueKey('event_video_flags'));
    final initialRect = tester.getRect(surface);
    final playerElement = player.viewKey.currentContext;
    final loads = player.loads;
    session.reportPlayback(true, session.playerRevision);

    await tester.pump(const Duration(seconds: 3));
    expect(tester.getRect(surface), initialRect);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(surface), initialRect);
    await tester.pumpAndSettle();
    expect(tester.getRect(surface), initialRect);
    expect(flags, findsOneWidget); // The chooser keeps its scroll state.
    expect(flags.hitTestable(), findsNothing);
    expect(find.byTooltip('Turn off the stream'), findsOneWidget);

    await tester.tap(find.byTooltip('Show stream selector'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(surface), initialRect);
    await tester.pumpAndSettle();
    expect(flags.hitTestable(), findsOneWidget);
    expect(player.viewKey.currentContext, same(playerElement));
    expect(player.loads, loads);
    expect(session.playing, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('minimizing preserves the chooser scroll position', (
    tester,
  ) async {
    final session = EventVideoSession(
      repository: FakeVideoRepository(manyVideos(20)),
    );
    await tester.pumpWidget(harness(session, FakePlayer()));
    await tester.pump();
    final flags = find.byKey(const ValueKey('event_video_flags'));
    final scrollable = find.descendant(
      of: flags,
      matching: find.byType(Scrollable),
    );
    await tester.drag(flags, const Offset(-400, 0));
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(scrollable).position;
    final offset = position.pixels;
    expect(offset, greaterThan(0));
    await tester.tap(find.byTooltip('Minimize stream selector'));
    await tester.pumpAndSettle();
    expect(flags.hitTestable(), findsNothing);
    await tester.tap(find.byTooltip('Show stream selector'));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scrollable).position, same(position));
    expect(position.pixels, offset);
    await tester.pumpWidget(const SizedBox());
  });

  for (final minimized in [false, true]) {
    testWidgets('close stops and remembers video, minimized=$minimized', (
      tester,
    ) async {
      bool? savedVisibility;
      final session = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
        saveVisibility: (value) async => savedVisibility = value,
      );
      await tester.pumpWidget(harness(session, FakePlayer()));
      await tester.pump();
      final selected = session.selected;
      session.reportPlayback(true, session.playerRevision);
      if (minimized) {
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
      }
      final close = find.byTooltip('Turn off the stream');
      expect(tester.getSize(close).shortestSide, greaterThanOrEqualTo(44));
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(savedVisibility, isFalse);
      expect(session.showVideo, isFalse);
      expect(session.playing, isFalse);
      expect(session.playRequested, isFalse);
      expect(session.selected, same(selected));
      expect(find.text('Player'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('toggle')));
      await tester.pumpAndSettle();
      expect(session.showVideo, isTrue);
      expect(session.selected, same(selected));
      expect(session.playRequested, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('narrow selector supports large text and reduced motion', (
    tester,
  ) async {
    final session = EventVideoSession(repository: null);
    session.streams = fixtureVideos();
    session.selected = session.streams.first;
    session.flagsVisible = true;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: EventVideoScope(
            session: session,
            player: null,
            child: const Scaffold(
              body: Center(
                child: SizedBox(width: 320, child: EventVideoFlagSlot()),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final crossFade = find.byType(AnimatedCrossFade);
    expect(tester.widget<AnimatedCrossFade>(crossFade).duration, Duration.zero);
    await tester.tap(find.byTooltip('Minimize stream selector'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('event_video_flags')).hitTestable(),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Show stream selector'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('event_video_flags')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('inactive game pages reserve the same selector space', (
    tester,
  ) async {
    final session = EventVideoSession(repository: null);
    session.streams = fixtureVideos();
    session.selected = session.streams.first;
    await tester.pumpWidget(
      MaterialApp(
        home: EventVideoScope(
          session: session,
          player: null,
          child: const Scaffold(
            body: Column(
              children: [
                EventVideoFlagSlot(key: ValueKey('active_selector')),
                EventVideoFlagSlot(
                  key: ValueKey('inactive_selector'),
                  active: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('inactive_selector'))).height,
      tester.getSize(find.byKey(const ValueKey('active_selector'))).height,
    );
    expect(find.byTooltip('Turn off the stream'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
