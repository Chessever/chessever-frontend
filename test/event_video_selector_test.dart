import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'event_video_test.dart' show FakeVideoRepository, fixtureVideos;
import 'event_video_widgets_test.dart' show FakePlayer, harness;

void main() {
  testWidgets('selector stays visible while the stream plays', (tester) async {
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
    );
    final player = FakePlayer();
    await tester.pumpWidget(harness(session, player));
    await tester.pump();
    final surface = find.byKey(const ValueKey('event_video_surface'));
    final flags = find.byKey(const ValueKey('event_video_flags'));
    final top = tester.getTopLeft(surface).dy;
    final playerElement = player.viewKey.currentContext;
    final loads = player.loads;
    session.reportPlayback(true, session.playerRevision);
    await tester.pump(const Duration(seconds: 3));
    expect(flags, findsOneWidget);
    expect(find.byKey(const ValueKey('event_video_selector')), findsNothing);
    expect(find.byTooltip('Show stream selector'), findsNothing);
    expect(tester.getTopLeft(surface).dy, closeTo(top, .1));
    await tester.tap(find.text('Player'));
    await tester.pump();
    expect(flags, findsOneWidget);
    expect(tester.getTopLeft(surface).dy, closeTo(top, .1));
    expect(player.viewKey.currentContext, same(playerElement));
    expect(player.loads, loads);
    expect(session.playing, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('selector supports large text without clipped controls', (
    tester,
  ) async {
    final session = EventVideoSession(repository: null);
    session.streams = fixtureVideos();
    session.selected = session.streams.first;
    session.flagsVisible = true;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
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
    expect(find.byKey(const ValueKey('event_video_flags')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('inactive pages keep no permanent space above video', (
    tester,
  ) async {
    final session = EventVideoSession(repository: null);
    session.streams = fixtureVideos();
    session.selected = session.streams.first;
    session.flagsVisible = false;
    await tester.pumpWidget(
      MaterialApp(
        home: EventVideoScope(
          session: session,
          player: null,
          child: const Scaffold(
            body: Column(
              children: [
                EventVideoFlagSlot(key: ValueKey('active')),
                EventVideoFlagSlot(key: ValueKey('inactive'), active: false),
              ],
            ),
          ),
        ),
      ),
    );
    for (final key in ['active', 'inactive']) {
      expect(tester.getSize(find.byKey(ValueKey(key))).height, 0);
    }
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
