import 'package:chessever2/providers/engine_settings_provider.dart';
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

void main() {
  testWidgets(
    'bottom bar replaces only swap with show/hide and preserves other controls',
    (tester) async {
      var flips = 0, toggles = 0, next = 0;
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
  testWidgets(
    'camera tooltip auto-shows every time a live stream opens',
    (tester) async {
      var toggles = 0;
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
                ),
              );
            },
          ),
        ),
      );

      // No stream: no camera, no bubble.
      await tester.pumpWidget(app(hasVideo: false, visible: false));
      await tester.pump();
      expect(find.text('Turn off the live stream'), findsNothing);

      // Stream metadata arrives with video showing: bubble points at camera.
      await tester.pumpWidget(app(hasVideo: true, visible: true));
      await tester.pump();
      expect(find.text('Turn off the live stream'), findsOneWidget);

      // Tapping the camera toggles and clears the bubble.
      await tester.tap(find.byKey(const ValueKey('board_video_toggle')));
      await tester.pumpAndSettle();
      expect(toggles, 1);
      expect(find.text('Turn off the live stream'), findsNothing);

      // Hiding the stream pops nothing; re-opening it bubbles again.
      await tester.pumpWidget(app(hasVideo: true, visible: false));
      await tester.pump();
      expect(find.text('Turn on the live stream'), findsNothing);
      await tester.pumpWidget(app(hasVideo: true, visible: true));
      await tester.pump();
      expect(find.text('Turn off the live stream'), findsOneWidget);

      // Off-screen pages never pop the bubble, even on a fresh mount with
      // the stream open; swiping to the page pops it.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(
        app(hasVideo: true, visible: true, isActivePage: false),
      );
      await tester.pump();
      expect(find.text('Turn off the live stream'), findsNothing);
      await tester.pumpWidget(app(hasVideo: true, visible: true));
      await tester.pump();
      expect(find.text('Turn off the live stream'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'shared phone/tablet menu offers swap while video is visible or hidden',
    (tester) async {
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
        // Same circular refresh mark as the bottom-bar flip control.
        expect(flipIcon(), findsOneWidget);
        expect(find.byIcon(Icons.swap_vert), findsNothing);
        await tester.tap(find.text('Flip board'));
        await tester.pumpAndSettle();
        expect(selected, 'flip_board');
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
