import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motor/motor.dart';
import 'package:chessever2/screens/chessboard/video/video_player.dart';
import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_stream.dart';
import 'package:chessever2/screens/chessboard/video/video_widgets.dart';
import 'event_video_test.dart' show FakeVideoRepository, fixtureVideos;

class FakePlayer extends EventVideoPlayer {
  int revision = -1;
  int loads = 0;
  bool disposed = false;
  final GlobalKey viewKey = GlobalKey();
  Widget? fullscreen;
  VoidCallback? onFullscreenHidden;
  @override
  bool get failed => false;
  @override
  Widget? get fullscreenView => fullscreen;
  @override
  void enterFullscreen(Widget view, VoidCallback onHidden) {
    fullscreen = view;
    onFullscreenHidden = onHidden;
    notifyListeners();
  }

  @override
  void exitFullscreen() {
    fullscreen = null;
    onFullscreenHidden = null;
    notifyListeners();
  }

  @override
  void closeFullscreen() => exitFullscreen();
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

/// A list long enough that the picker grid has to scroll on a phone.
List<EventVideoStream> manyVideos(int count) => [
  for (var i = 0; i < count; i++)
    EventVideoStream(
      id: 'stream-$i',
      label: 'Stream $i',
      source: VideoSource.parse('https://twitch.tv/channel$i'),
      countryCode: 'US',
      language: 'en',
    ),
];

/// Taps a picker tile and lets the entry fade finish.
Future<void> chooseStream(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('video_stream_$id')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

double playerOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(of: find.text('Player'), matching: find.byType(Opacity)),
    )
    .opacity;

void main() {
  testWidgets(
    'stream area is a picker until chosen, then the player fades in',
    (tester) async {
      tester.view.physicalSize = const Size(375, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      // The stream area holds the picker; no player or flag rail anywhere.
      expect(find.byKey(const ValueKey('event_video_picker')), findsOneWidget);
      expect(find.text('Player'), findsNothing);
      expect(find.byKey(const ValueKey('event_video_flags')), findsNothing);
      for (final id in [
        'english-main',
        'english-second',
        'german',
        'spanish',
      ]) {
        expect(find.byKey(ValueKey('video_stream_$id')), findsOneWidget);
      }
      // The ranked first stream is not drawn as a chosen tile.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('event_video_picker')),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.selected == true,
          ),
        ),
        findsNothing,
      );
      // The engine line sits below the stream area, picker included.
      expect(find.text('One engine line'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('One engine line')).dy,
        greaterThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('event_video_picker_slot')))
              .dy,
        ),
      );
      expect(session.playRequested, isFalse);
      // Choosing dismisses the picker and fades the player in.
      await tester.tap(
        find.byKey(const ValueKey('video_stream_english-main')),
      );
      await tester.pump();
      expect(previewActive, isFalse);
      expect(session.streamChosen, isTrue);
      expect(find.byKey(const ValueKey('event_video_picker')), findsNothing);
      expect(find.text('Player'), findsOneWidget);
      // The entry is a motor spring, not a fixed-duration tween.
      expect(find.byType(SingleMotionBuilder), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 80));
      final fading = playerOpacity(tester);
      expect(fading, greaterThan(0.0));
      expect(fading, lessThan(1.0));
      await tester.pumpAndSettle();
      expect(playerOpacity(tester), 1.0);
      // Choosing is the play gesture: the stream starts without a second tap
      // on the provider's own play button.
      expect(session.playRequested, isTrue);
      expect(
        tester.getTopLeft(find.text('One engine line')).dy,
        greaterThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('event_video_surface')))
              .dy,
        ),
      );
      // Notation sits under the engine lines, at a bounded height.
      expect(
        tester.getTopLeft(find.text('Notation 0')).dy,
        greaterThan(tester.getTopLeft(find.text('One engine line')).dy),
      );
      await tester.pumpWidget(const SizedBox());
      expect(player.disposed, isTrue);
    },
  );
  testWidgets('long stream lists scroll inside the picker grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = EventVideoSession(
      repository: FakeVideoRepository(manyVideos(30)),
    );
    await tester.pumpWidget(harness(session, FakePlayer()));
    await tester.pump();
    expect(find.byKey(const ValueKey('event_video_picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('video_stream_stream-0')), findsOneWidget);
    final last = find.byKey(const ValueKey('video_stream_stream-29'));
    expect(last, findsNothing);
    await tester.scrollUntilVisible(
      last,
      400,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('event_video_picker')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(last, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('one tap on the stream reveals provider controls once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
    );
    await tester.pumpWidget(harness(session, FakePlayer()));
    await tester.pump();
    await chooseStream(tester, 'english-main');
    expect(session.controlsVisible, isFalse);
    final revision = session.playerRevision;
    await tester.tap(find.text('Player'));
    await tester.pump();
    expect(session.controlsVisible, isTrue);
    expect(session.playerRevision, revision + 1);
    expect(session.playRequested, isTrue);
    // From now on the provider owns the taps; no second reload.
    await tester.tap(find.text('Player'));
    await tester.pump();
    expect(session.playerRevision, revision + 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('native fullscreen overlays the route and back exits it first', (
    tester,
  ) async {
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
    );
    final player = FakePlayer();
    await tester.pumpWidget(harness(session, player));
    await tester.pump();
    await chooseStream(tester, 'english-main');
    player.enterFullscreen(
      const ColoredBox(
        color: Colors.red,
        child: Center(child: Text('Native fullscreen')),
      ),
      () {},
    );
    await tester.pump();
    expect(find.text('Native fullscreen'), findsOneWidget);
    // Back closes the provider overlay, not the board behind it.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(player.fullscreen, isNull);
    expect(find.text('Native fullscreen'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'rotation in provider fullscreen keeps playing; exit to narrow stops',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
        savedCountry: 'DE',
      );
      final player = FakePlayer();
      await tester.pumpWidget(harness(session, player));
      await tester.pump();
      await chooseStream(tester, 'german');
      session.reportPlayback(true, session.playerRevision);
      player.enterFullscreen(const ColoredBox(color: Colors.black), () {});
      await tester.pump();
      expect(session.playing, isTrue);
      // Rotating while fullscreen must not stop the invisible inline view.
      tester.view.physicalSize = const Size(375, 700);
      await tester.pump();
      expect(session.playing, isTrue);
      // Leaving fullscreen onto a narrow inline Twitch view stops playback.
      player.exitFullscreen();
      await tester.pump();
      expect(session.playing, isFalse);
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
    await chooseStream(tester, 'english-main');
    session.reportPlayback(true, session.playerRevision);
    final revision = session.playerRevision;
    final loads = player.loads;
    await tester.pumpWidget(harness(session, player, game: 'g2'));
    await tester.pump();
    expect(session.streamChosen, isTrue);
    expect(session.playing, isTrue);
    expect(session.playerRevision, revision);
    expect(player.loads, loads);
    expect(find.text('Player'), findsOneWidget);
    await tester.pumpWidget(
      harness(session, player, game: 'g3', tour: 'another-tour'),
    );
    await tester.pump();
    expect(session.playing, isFalse);
    expect(session.playRequested, isFalse);
    expect(session.streamChosen, isFalse);
    expect(find.byKey(const ValueKey('event_video_picker')), findsOneWidget);
    expect(find.text('Player'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('short screens scroll to the engine line without overflow', (
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
    await chooseStream(tester, 'english-main');
    session.reportPlayback(true, session.playerRevision);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.drag(find.text('Board'), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.text('One engine line'), findsOneWidget);
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
      await chooseStream(tester, 'german');
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
    await chooseStream(tester, 'english-main');
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
      session.select('english-main');
      await tester.pump(const Duration(milliseconds: 400));
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
    await chooseStream(tester, 'german');
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
