import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/utils/live_stream_coachmark.dart';
import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_widgets.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_navbar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'event_video_test.dart' show fixtureVideos;

class _Settings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();
}

class _CoachmarkStore implements LiveStreamCoachmarkStore {
  _CoachmarkStore({this.seen = false});

  bool seen;

  @override
  Future<bool> hasSeen() async => seen;

  @override
  Future<void> markSeen() async => seen = true;
}

void main() {
  test('camera coachmark remains seen across tracker instances', () async {
    final store = _CoachmarkStore();
    final firstLifetime = LiveStreamCoachmarkTracker(store);
    expect(await firstLifetime.claim(), isTrue);
    await firstLifetime.markShown();

    final nextLifetime = LiveStreamCoachmarkTracker(store);
    expect(await nextLifetime.claim(), isFalse);
  });

  testWidgets(
    'bottom bar replaces only swap with show/hide and preserves other controls',
    (tester) async {
      var flips = 0, toggles = 0, next = 0;
      final coachmarkTracker = LiveStreamCoachmarkTracker(
        _CoachmarkStore(seen: true),
      );
      Widget app(bool hasVideo, bool visible) => ProviderScope(
        overrides: [
          engineSettingsProviderNew.overrideWith(_Settings.new),
          engineDepthStatusProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                bottomNavigationBar: ChessBoardBottomNavBar(
                  gameIndex: 0,
                  onLeftMove: () {},
                  onRightMove: () => next++,
                  onFlip: () => flips++,
                  onVideoToggle: hasVideo ? () => toggles++ : null,
                  videoVisible: visible,
                  canMoveForward: true,
                  canMoveBackward: true,
                  showEngineAnalysis: true,
                  showUnseenMoveBadge: false,
                  liveStreamCoachmarkTracker: coachmarkTracker,
                ),
              );
            },
          ),
        ),
      );
      Finder flip() => find.byWidgetPredicate(
        (w) => w is ChessSvgBottomNavbar && w.svgPath == SvgAsset.refresh,
      );
      await tester.pumpWidget(app(false, false));
      await tester.pump();
      expect(flip(), findsOneWidget);
      expect(find.byKey(const ValueKey('board_video_toggle')), findsNothing);
      await tester.tap(flip());
      expect(flips, 1);
      await tester.pumpWidget(app(true, true));
      await tester.pump();
      expect(flip(), findsNothing);
      expect(find.byTooltip('Turn off the live stream'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_off_outlined), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.videocam_off_outlined)).color,
        Colors.white,
      );
      await tester.tap(find.byTooltip('Turn off the live stream'));
      expect(toggles, 1);
      expect(flips, 1);
      final forward = find.byWidgetPredicate(
        (w) =>
            w is ChessSvgBottomNavbarWithLongPress &&
            w.svgPath == SvgAsset.right_arrow,
      );
      await tester.tap(forward);
      expect(next, 1);
      await tester.pumpWidget(app(true, false));
      await tester.pump();
      expect(find.byTooltip('Turn on the live stream'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.videocam_outlined)).color,
        Colors.white,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('camera coachmark points at the icon only once', (tester) async {
    var toggles = 0;
    final store = _CoachmarkStore();
    final tracker = LiveStreamCoachmarkTracker(store);
    Widget app({
      required bool hasVideo,
      required bool visible,
      bool isActivePage = true,
    }) => ProviderScope(
      overrides: [
        engineSettingsProviderNew.overrideWith(_Settings.new),
        engineDepthStatusProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              bottomNavigationBar: ChessBoardBottomNavBar(
                gameIndex: 0,
                onLeftMove: () {},
                onRightMove: () {},
                onFlip: () {},
                onVideoToggle: hasVideo ? () => toggles++ : null,
                videoVisible: visible,
                isActivePage: isActivePage,
                canMoveForward: true,
                canMoveBackward: true,
                showEngineAnalysis: false,
                showUnseenMoveBadge: false,
                liveStreamCoachmarkTracker: tracker,
              ),
            );
          },
        ),
      ),
    );

    // No stream: no camera, no bubble.
    await tester.pumpWidget(app(hasVideo: false, visible: false));
    await tester.pump();
    expect(
      find.text('Turn off the stream by clicking camera icon.'),
      findsNothing,
    );

    // Stream metadata arrives with video showing: bubble points at camera.
    await tester.pumpWidget(app(hasVideo: true, visible: true));
    await tester.pump();
    expect(
      find.text('Turn off the stream by clicking camera icon.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('live_stream_toggle_coachmark_arrow')),
      findsOneWidget,
    );
    final coachmarkRect = tester.getRect(
      find.byKey(const ValueKey('live_stream_toggle_coachmark')),
    );
    final arrowRect = tester.getRect(
      find.byKey(const ValueKey('live_stream_toggle_coachmark_arrow')),
    );
    final cameraRect = tester.getRect(
      find.byKey(const ValueKey('board_video_toggle')),
    );
    final appRect = tester.getRect(find.byType(MaterialApp));
    expect(coachmarkRect.left, greaterThanOrEqualTo(appRect.left + 16));
    expect(coachmarkRect.right, lessThanOrEqualTo(appRect.right - 16));
    expect(arrowRect.center.dx, closeTo(cameraRect.center.dx, 0.1));
    expect(
      tester.widget<Icon>(find.byIcon(Icons.videocam_off_outlined)).color,
      kPrimaryColor,
    );
    // The hint uses the app's dark raised surface and readable light text.
    final bubbleDecoration =
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('live_stream_toggle_coachmark')),
                )
                .decoration!
            as BoxDecoration;
    expect(bubbleDecoration.color, kBlack3Color);
    final bubbleLabel = tester.widget<Text>(
      find.text('Turn off the stream by clicking camera icon.'),
    );
    expect(bubbleLabel.style?.color, kWhiteColor);
    expect(store.seen, isTrue);

    // Tapping the camera toggles and clears the bubble.
    await tester.tap(find.byKey(const ValueKey('board_video_toggle')));
    await tester.pumpAndSettle();
    expect(toggles, 1);
    expect(
      find.text('Turn off the stream by clicking camera icon.'),
      findsNothing,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.videocam_off_outlined)).color,
      Colors.white,
    );

    // Hiding and re-opening the stream never repeats the lifetime hint.
    await tester.pumpWidget(app(hasVideo: true, visible: false));
    await tester.pump();
    expect(find.text('Turn on the live stream'), findsNothing);
    await tester.pumpWidget(app(hasVideo: true, visible: true));
    await tester.pump();
    expect(
      find.text('Turn off the stream by clicking camera icon.'),
      findsNothing,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.videocam_off_outlined)).color,
      Colors.white,
    );

    // A fresh tracker models a fresh install. Off-screen pages do not claim
    // the hint; it appears only when that page becomes active.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final freshTracker = LiveStreamCoachmarkTracker(_CoachmarkStore());
    var backgroundTaps = 0;
    Widget freshApp(bool isActivePage) => ProviderScope(
      overrides: [
        engineSettingsProviderNew.overrideWith(_Settings.new),
        engineDepthStatusProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => backgroundTaps++,
                child: const SizedBox.expand(),
              ),
              bottomNavigationBar: ChessBoardBottomNavBar(
                gameIndex: 0,
                onLeftMove: () {},
                onRightMove: () {},
                onFlip: () {},
                onVideoToggle: () {},
                videoVisible: true,
                isActivePage: isActivePage,
                canMoveForward: true,
                canMoveBackward: true,
                showEngineAnalysis: false,
                showUnseenMoveBadge: false,
                liveStreamCoachmarkTracker: freshTracker,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpWidget(freshApp(false));
    await tester.pump();
    expect(
      find.text('Turn off the stream by clicking camera icon.'),
      findsNothing,
    );
    await tester.pumpWidget(freshApp(true));
    await tester.pump();
    expect(
      find.text('Turn off the stream by clicking camera icon.'),
      findsOneWidget,
    );

    // The coachmark has no timer and remains until explicitly dismissed.
    await tester.pump(const Duration(minutes: 1));
    expect(
      find.text('Turn off the stream by clicking camera icon.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('close_live_stream_coachmark')));
    await tester.pump();
    expect(
      find.text('Turn off the stream by clicking camera icon.'),
      findsNothing,
    );
    expect(backgroundTaps, 0);

    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('shared phone/tablet menu toggles video visibility', (
    tester,
  ) async {
    final session = EventVideoSession(repository: null);
    addTearDown(session.dispose);
    var selected = '';
    Widget app() => MaterialApp(
      home: Scaffold(
        body: PopupMenuButton<String>(
          onSelected: (value) => selected = value,
          itemBuilder:
              (context) => [
                ...eventVideoBoardMenuItems(context, session),
                const PopupMenuItem(
                  value: 'settings',
                  child: Text('Board Settings'),
                ),
              ],
        ),
      ),
    );
    Finder flipIcon() => find.byWidgetPredicate(
      (w) => w is SvgWidget && w.path == SvgAsset.refresh,
    );
    await tester.pumpWidget(app());
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Flip board'), findsNothing);
    await tester.tap(find.text('Board Settings'));
    await tester.pumpAndSettle();
    session.streams = fixtureVideos();
    session.selected = session.streams.first;
    for (final visible in [true, false]) {
      session.visible = visible;
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Flip board'), findsOneWidget);
      expect(
        find.text(visible ? 'Disable Video' : 'Enable Video'),
        findsOneWidget,
      );
      // Same circular refresh mark as the bottom-bar flip control.
      expect(flipIcon(), findsOneWidget);
      expect(find.byIcon(Icons.swap_vert), findsNothing);
      await tester.tap(find.text('Flip board'));
      await tester.pumpAndSettle();
      expect(selected, 'flip_board');
    }

    session.visible = true;
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disable Video'));
    await tester.pumpAndSettle();
    expect(selected, 'disable_video');
    expect(session.visible, isFalse);

    // The option remains available and changes to the inverse action.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Enable Video'), findsOneWidget);
    await tester.tap(find.text('Enable Video'));
    await tester.pumpAndSettle();
    expect(selected, 'enable_video');
    expect(session.visible, isTrue);
    await tester.pump(const Duration(seconds: 3));

    await tester.pumpWidget(const SizedBox());
  });
}
