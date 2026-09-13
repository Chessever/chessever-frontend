import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  testWidgets(
    'iPhone fullscreen shows one landscape player without restarting it',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
      );
      final player = FakePlayer();
      await tester.pumpWidget(harness(session, player));
      await tester.pump();
      await chooseStream(tester, 'english-main');
      session.reportPlayback(true, session.playerRevision);
      final loads = player.loads;
      final surface = tester.getRect(
        find.byKey(const ValueKey('event_video_surface')),
      );
      final button = tester.getRect(find.byTooltip('Fullscreen video'));
      expect(surface.right - button.right, inInclusiveRange(4, 12));
      expect(surface.bottom - button.bottom, inInclusiveRange(4, 12));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byTooltip('Fullscreen video'), findsNothing);
      await tester.tap(find.text('Player'));
      await tester.pump();
      expect(find.byTooltip('Fullscreen video'), findsOneWidget);
      // Revealing the fullscreen button keeps the playing embed intact.
      expect(session.playing, isTrue);
      expect(player.loads, loads);
      await tester.tap(find.byTooltip('Fullscreen video'));
      await tester.pump();
      expect(session.expanded, isTrue);
      expect(session.playing, isTrue);
      expect(player.loads, loads);
      expect(find.text('Player'), findsOneWidget);
      final size = tester.getSize(find.byKey(player.viewKey));
      expect(size.width, greaterThan(size.height));
      await tester.tap(find.byKey(const ValueKey('video_close_expanded')));
      await tester.pump();
      expect(session.expanded, isFalse);
      expect(find.byTooltip('Fullscreen video'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('flags appear above paused video, dismiss and return on tap', (
    tester,
  ) async {
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
    );
    final player = FakePlayer();
    await tester.pumpWidget(harness(session, player));
    await tester.pump();
    expect(find.text('Player'), findsOneWidget);
    expect(session.playRequested, isFalse);
    final flags = find.byKey(const ValueKey('event_video_flags'));
    expect(
      tester.getBottomLeft(flags).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const ValueKey('event_video_surface'))).dy,
      ),
    );
    final order = session.streams.map((s) => s.id).toList();
    await chooseStream(tester, 'english-second');
    expect(session.playRequested, isFalse);
    expect(session.streams.map((s) => s.id), order);
    await tester.pump(const Duration(seconds: 3));
    expect(flags, findsNothing);
    await tester.pumpWidget(harness(session, player, game: 'g2'));
    await tester.pump();
    expect(flags, findsNothing);
    await tester.tap(find.text('Player'));
    await tester.pump();
    expect(flags, findsOneWidget);
    session.setScrolling(true);
    await tester.pump(const Duration(seconds: 4));
    expect(flags, findsOneWidget);
    session.setScrolling(false);
    await tester.pump(const Duration(seconds: 2));
    await chooseStream(tester, 'english-main');
    await tester.pump(const Duration(seconds: 2));
    expect(flags, findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(flags, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('taps on the stream belong to the provider: no reload', (
    tester,
  ) async {
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
    );
    final player = FakePlayer();
    await tester.pumpWidget(harness(session, player));
    await tester.pump();
    await chooseStream(tester, 'english-main');
    final revision = session.playerRevision;
    final loads = player.loads;
    await tester.tap(find.text('Player'));
    await tester.pump();
    expect(session.playerRevision, revision);
    expect(player.loads, loads);
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
  testWidgets('inset-only churn never stops a narrow Twitch stream', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
      savedCountry: 'DE',
    );
    final player = FakePlayer();
    await tester.pumpWidget(harness(session, player));
    await tester.pump();
    await chooseStream(tester, 'german');
    session.reportPlayback(true, session.playerRevision);
    // Android hides the status bar while provider fullscreen opens: the
    // padding-only metrics event must not be read as a rotation to narrow.
    tester.view.viewPadding = const FakeViewPadding(top: 24);
    await tester.pump();
    expect(session.playing, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
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
    expect(find.byKey(const ValueKey('event_video_flags')), findsOneWidget);
    expect(find.text('Player'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'short screens show notation below engine lines and scroll without overflow',
    (tester) async {
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
      expect(find.text('Notation 0').hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Notation 0')).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.text('One engine line')).dy,
        ),
      );
      await tester.drag(find.text('Notation 0'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(find.text('Notation 19').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
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
    // Tablets keep the notation/explorer panel under the engine lines.
    expect(find.text('Notation 0'), findsOneWidget);
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
  testWidgets('swiping games keeps one visible player and stable video slots', (
    tester,
  ) async {
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
            body: PageView(
              onPageChanged:
                  (index) => session.openGame(
                    gameId: 'g${index + 1}',
                    tourId: 'tour',
                    roundId: 'round',
                  ),
              children: [
                for (final id in ['g1', 'g2'])
                  Builder(
                    builder: (context) {
                      final current = EventVideoScope.maybeOf(context)!.session;
                      return EventVideoGameLayout(
                        active: current.isActive(id),
                        board: SizedBox(height: 100, child: Text('Board $id')),
                        engine: const SizedBox(height: 44),
                        analysis: const Text('Notation'),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    session.reportPlayback(true, session.playerRevision);
    final element = player.viewKey.currentContext;
    final loads = player.loads;
    await tester.drag(find.text('Board g1'), const Offset(-700, 0));
    await tester.pump();
    expect(session.gameId, 'g2');
    expect(find.text('Player'), findsOneWidget);
    expect(player.viewKey.currentContext, same(element));
    expect(
      find.ancestor(of: find.text('Player'), matching: find.byType(Opacity)),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(session.playing, isTrue);
    expect(player.loads, loads);
    await tester.pumpWidget(const SizedBox());
  });

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
