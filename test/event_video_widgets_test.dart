import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/screens/chessboard/video/video_player.dart';
import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_widgets.dart';
import 'event_video_test.dart' show FakeVideoRepository, fixtureVideos;

class FakePlayer extends EventVideoPlayer {
  int revision = -1;
  int loads = 0;
  bool disposed = false;
  final GlobalKey viewKey = GlobalKey();
  @override
  bool get failed => false;
  @override
  void synchronize(EventVideoSession session) {
    if (revision != session.playerRevision) {
      revision = session.playerRevision;
      loads++;
    }
  }

  @override
  Widget buildView() => Container(
    key: viewKey,
    color: Colors.black,
    child: const Center(
      child: Text('Player', style: TextStyle(color: Colors.white)),
    ),
  );
  @override
  void retry() {}
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

Widget harness(
  EventVideoSession session,
  FakePlayer player, {
  String game = 'g1',
  String tour = 'tour',
  bool sideBySide = false,
  VoidCallback? onVideoInteraction,
}) => MaterialApp(
  home: EventVideoHost(
    gameId: game,
    tourId: tour,
    roundId: 'round',
    session: session,
    player: player,
    onVideoInteraction: onVideoInteraction,
    child: Scaffold(
      body: Builder(
        builder: (context) {
          final session = EventVideoScope.maybeOf(context)!.session;
          return Column(
            children: [
              Row(
                children: [
                  TextButton(
                    key: const ValueKey('toggle'),
                    onPressed: session.toggle,
                    child: Text(session.visible ? 'Hide' : 'Show'),
                  ),
                ],
              ),
              Expanded(
                child:
                    session.showVideo
                        ? EventVideoGameLayout(
                          sideBySide: sideBySide,
                          board: const SizedBox(
                            height: 250,
                            child: Center(child: Text('Board')),
                          ),
                          engine: const SizedBox(
                            height: 44,
                            child: Text('One engine line'),
                          ),
                          analysis: ListView(
                            children: List.generate(
                              20,
                              (i) => Text('Notation $i'),
                            ),
                          ),
                        )
                        : const Text('Normal engine lines'),
              ),
            ],
          );
        },
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'initial flags, three-second dismissal, taps do not consume player input',
    (tester) async {
      final session = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
      );
      final player = FakePlayer();
      var previewActive = true;
      await tester.pumpWidget(
        harness(
          session,
          player,
          onVideoInteraction: () => previewActive = false,
        ),
      );
      await tester.pump();
      expect(session.playRequested, isFalse);
      expect(find.byKey(const ValueKey('event_video_flags')), findsOneWidget);
      expect(find.text('One engine line'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('event_video_flags')), findsNothing);
      expect(find.text('One engine line'), findsOneWidget);
      await tester.tap(find.text('Player'));
      await tester.pump();
      expect(previewActive, isFalse);
      expect(find.byKey(const ValueKey('event_video_flags')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(
        find.byKey(const ValueKey('video_stream_english-second')),
      );
      await tester.pump();
      expect(session.selected!.id, 'english-second');
      expect(session.playRequested, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(session.flagsVisible, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(session.flagsVisible, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(player.disposed, isTrue);
    },
  );
  testWidgets(
    'flag scroll suspends timeout and dismisses three seconds after use',
    (tester) async {
      tester.view.physicalSize = const Size(375, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
      );
      await tester.pumpWidget(harness(session, FakePlayer()));
      await tester.pump();
      final rail = find.byKey(const ValueKey('event_video_flags'));
      final gesture = await tester.startGesture(tester.getCenter(rail));
      await gesture.moveBy(const Offset(-100, 0));
      await tester.pump();
      await tester.pump(const Duration(seconds: 7));
      expect(session.flagsVisible, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(session.flagsVisible, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'video order, repeated flags, hide restores normal engine and show stays paused',
    (tester) async {
      final session = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
      );
      await tester.pumpWidget(harness(session, FakePlayer()));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('video_stream_english-main')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('video_stream_english-second')),
        findsOneWidget,
      );
      final railY =
          tester.getTopLeft(find.byKey(const ValueKey('event_video_flags'))).dy;
      final playerY =
          tester
              .getTopLeft(find.byKey(const ValueKey('event_video_surface')))
              .dy;
      final notationY = tester.getTopLeft(find.text('Notation 0')).dy;
      expect(railY, lessThan(playerY));
      expect(playerY, lessThan(notationY));
      session.reportPlayback(true, session.playerRevision);
      await tester.tap(find.byKey(const ValueKey('toggle')));
      await tester.pump();
      expect(find.text('Normal engine lines'), findsOneWidget);
      expect(find.text('Player'), findsNothing);
      expect(session.playing, isFalse);
      await tester.tap(find.byKey(const ValueKey('toggle')));
      await tester.pump();
      expect(session.playRequested, isFalse);
      expect(find.text('Player'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('same-event game change keeps one player and playback revision', (
    tester,
  ) async {
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
    );
    final player = FakePlayer();
    await tester.pumpWidget(harness(session, player));
    await tester.pump();
    session.reportPlayback(true, session.playerRevision);
    final revision = session.playerRevision;
    final loads = player.loads;
    await tester.pumpWidget(harness(session, player, game: 'g2'));
    await tester.pump();
    expect(session.playing, isTrue);
    expect(session.playerRevision, revision);
    expect(player.loads, loads);
    expect(find.text('Player'), findsOneWidget);
    expect(session.flagsVisible, isTrue);
    await tester.pumpWidget(
      harness(session, player, game: 'g3', tour: 'another-tour'),
    );
    await tester.pump();
    expect(session.playing, isFalse);
    expect(session.playRequested, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('short screens scroll to notation without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
    );
    await tester.pumpWidget(harness(session, FakePlayer()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byKey(const ValueKey('video_game_scroll')),
      const Offset(0, -450),
    );
    await tester.pumpAndSettle();
    expect(find.text('Notation 0').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'narrow Twitch opens a single in-app landscape player and closes paused',
    (tester) async {
      tester.view.physicalSize = const Size(375, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
        savedCountry: 'DE',
      );
      await tester.pumpWidget(harness(session, FakePlayer()));
      await tester.pump();
      expect(find.text('Player'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('video_expand_twitch')));
      await tester.pump();
      expect(session.expanded, isTrue);
      expect(find.text('Player'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('event_video_surface'))).width,
        greaterThanOrEqualTo(400),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('event_video_surface')))
            .height,
        greaterThanOrEqualTo(300),
      );
      session.reportPlayback(true, session.playerRevision);
      await tester.tap(find.byKey(const ValueKey('video_close_expanded')));
      await tester.pump();
      expect(session.expanded, isFalse);
      expect(session.selected!.id, 'german');
      expect(session.playing, isFalse);
      expect(find.text('Player'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('tablet landscape places video in the analysis column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
    );
    await tester.pumpWidget(harness(session, FakePlayer(), sideBySide: true));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('event_video_surface'))).dx,
      greaterThan(tester.getTopLeft(find.text('Board')).dx),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'native view identity survives moving between active page slots',
    (tester) async {
      final session = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
      );
      final player = FakePlayer();
      await tester.pumpWidget(
        MaterialApp(
          home: EventVideoHost(
            gameId: 'g1',
            tourId: 'tour',
            roundId: 'round',
            session: session,
            player: player,
            child: Scaffold(
              body: Row(
                children: [
                  for (final id in ['g1', 'g2'])
                    Expanded(
                      key: ValueKey(id),
                      child: Builder(
                        builder: (context) {
                          final current =
                              EventVideoScope.maybeOf(context)!.session;
                          return current.isActive(id) && current.showVideo
                              ? const EventVideoSurface()
                              : const SizedBox.shrink();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final element = player.viewKey.currentContext;
      session.reportPlayback(true, session.playerRevision);
      final loads = player.loads;
      session.openGame(gameId: 'g2', tourId: 'tour', roundId: 'round');
      await tester.pump();
      expect(player.viewKey.currentContext, same(element));
      expect(find.text('Player'), findsOneWidget);
      expect(player.loads, loads);
      expect(session.playing, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('rotation to a narrow Twitch layout stops invisible playback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
      savedCountry: 'DE',
    );
    await tester.pumpWidget(harness(session, FakePlayer()));
    await tester.pump();
    expect(find.text('Player'), findsOneWidget);
    session.reportPlayback(true, session.playerRevision);
    tester.view.physicalSize = const Size(375, 700);
    await tester.pump();
    expect(find.text('Player'), findsNothing);
    expect(find.byKey(const ValueKey('video_expand_twitch')), findsOneWidget);
    expect(session.playing, isFalse);
    expect(session.playRequested, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
