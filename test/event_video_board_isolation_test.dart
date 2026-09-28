import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_widgets.dart';
import 'package:chessever2/screens/chessboard/widgets/rest_aware_opacity.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'event_video_test.dart' show FakeVideoRepository, fixtureVideos;
import 'event_video_widgets_test.dart' show FakePlayer;

/// The board screen keeps three game pages alive, each with the board,
/// notation and explorer. Video session churn must never rebuild them: that
/// is what made 35.0.0 lag while browsing moves with the stream turned off.
void main() {
  late EventVideoSession session;
  late int pageBuilds;
  late EventVideoLayout? layout;

  Future<void> pumpBoard(WidgetTester tester) async {
    session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
    );
    pageBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EventVideoHost(
          gameId: 'g1',
          tourId: 'tour',
          roundId: 'round',
          session: session,
          player: FakePlayer(),
          child: Builder(
            builder: (context) {
              pageBuilds++;
              layout = EventVideoLayoutScope.maybeOf(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> churn(WidgetTester tester) async {
    await session.refresh();
    await tester.pump();
    session.setForeground(false);
    await tester.pump();
    session.setForeground(true);
    await tester.pump();
    session.revealFlags();
    await tester.pump();
    // Flags stay visible while the stream is available.
    await tester.pump(const Duration(seconds: 4));
  }

  testWidgets('hidden video: session churn never rebuilds a game page', (
    tester,
  ) async {
    await pumpBoard(tester);
    expect(layout!.showVideo, isTrue);
    session.toggle();
    await tester.pump();
    expect(layout!.hasVideo, isTrue);
    expect(layout!.showVideo, isFalse);
    final builds = pageBuilds;

    await churn(tester);
    expect(pageBuilds, builds);

    session.toggle();
    await tester.pump();
    expect(pageBuilds, builds + 1);
    expect(layout!.watches('tour'), isTrue);
  });

  testWidgets('visible video: flags and polls rebuild only the video widgets', (
    tester,
  ) async {
    await pumpBoard(tester);
    final builds = pageBuilds;
    await churn(tester);
    expect(pageBuilds, builds);
  });

  testWidgets('an event without streams never changes the snapshot', (
    tester,
  ) async {
    await pumpBoard(tester);
    session.openGame(gameId: 'g2', tourId: 'no-stream', roundId: 'r');
    (session.repository! as FakeVideoRepository).streams = const [];
    await tester.pump();
    await session.refresh();
    await tester.pump();
    expect(layout!.hasVideo, isFalse);
    final builds = pageBuilds;

    session.openGame(gameId: 'g3', tourId: 'no-stream', roundId: 'r');
    await churn(tester);
    expect(pageBuilds, builds);
  });

  testWidgets('resting fade paints straight through without a layer', (
    tester,
  ) async {
    Future<RenderRestAwareOpacity> pumpAt(double opacity) async {
      await tester.pumpWidget(
        RestAwareOpacity(opacity: opacity, child: const SizedBox.expand()),
      );
      return tester.renderObject(find.byType(RestAwareOpacity));
    }

    var render = await pumpAt(1);
    expect(render.isRepaintBoundary, isFalse);
    expect(render.needsCompositing, isFalse);
    expect(render.debugLayer, isNull);

    render = await pumpAt(.5);
    expect(render.needsCompositing, isTrue);
    expect(render.debugLayer, isA<OpacityLayer>());
    expect((render.debugLayer! as OpacityLayer).alpha, 128);

    render = await pumpAt(1);
    expect(render.needsCompositing, isFalse);
    expect(render.debugLayer, isNull);
  });
}
