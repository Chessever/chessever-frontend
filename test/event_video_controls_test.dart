import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_widgets.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_navbar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
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
      expect(find.byTooltip('Hide video'), findsOneWidget);
      await tester.tap(find.byTooltip('Hide video'));
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
      expect(find.byTooltip('Show video'), findsOneWidget);
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
                (_) => [
                  ...eventVideoBoardMenuItems(session),
                  const PopupMenuItem(
                    value: 'settings',
                    child: Text('Board Settings'),
                  ),
                ],
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Swap board'), findsNothing);
      await tester.tap(find.text('Board Settings'));
      await tester.pumpAndSettle();
      session.streams = fixtureVideos();
      session.selected = session.streams.first;
      for (final visible in [true, false]) {
        session.visible = visible;
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        expect(find.text('Swap board'), findsOneWidget);
        await tester.tap(find.text('Swap board'));
        await tester.pumpAndSettle();
        expect(selected, 'flip_board');
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
