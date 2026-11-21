import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/screens/feed/widgets/feed_live_board.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/feed_shell_harness.dart';

/// In the home shell, with the dock shown, every Feed post keeps
/// [FeedLayout.footGap] of air between its rail and the dock's capsule, on
/// the tallest and the shortest phones Feed meets (360x640 Android with
/// gesture and three-button navigation, the iPhone SE), at the reading size
/// and at a large text size. The frosted backing stands only where a chart
/// is under the rail: on a game post at rest, not on a puzzle, the skeleton
/// or a game post while the viewer's own line stands in the chart's place.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadFeedFonts);

  for (final phone in feedPhones) {
    for (final scene in [
      FeedShellScene.game,
      FeedShellScene.puzzle,
      FeedShellScene.skeleton,
    ]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('${scene.name} on ${phone.name} at ${scale}x keeps its '
            'air over the dock', (tester) async {
          SharedPreferences.setMockInitialValues(const {});
          await pumpFeedShell(
            tester,
            scene: scene,
            phone: phone,
            textScale: scale,
            likes: 123456,
            play: false,
          );
          expect(tester.takeException(), isNull);
          final capsule = tester.getRect(
            find.byKey(const ValueKey('home-nav-capsule')),
          );
          final glass = _onScreen(
            tester,
            find.byKey(const ValueKey('feed_rail_glass')),
            phone.size,
          );
          expect(
            capsule.top - glass.bottom,
            greaterThanOrEqualTo(FeedLayout.footGap - 0.5),
            reason: 'rail $glass, dock $capsule',
          );
          final last = _onScreen(
            tester,
            find.byKey(
              ValueKey(
                scene == FeedShellScene.puzzle
                    ? 'feed_puzzle_next'
                    : scene == FeedShellScene.game
                    ? 'feed_like_button'
                    : 'feed_rail_glass',
              ),
            ),
            phone.size,
          );
          expect(last.bottom, lessThanOrEqualTo(capsule.top - 0.5));
          final backing = tester
              .widgetList<FeedRailGlass>(find.byType(FeedRailGlass))
              .first;
          expect(backing.shown, scene == FeedShellScene.game);
          if (scene == FeedShellScene.game) {
            // Whole and compact under the heart.
            expect(find.text('123K'), findsWidgets);
            expect(find.textContaining('123,'), findsNothing);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
        });
      }
    }
  }

  testWidgets('a game post lets its backing go while the viewer\'s line '
      'stands in the chart\'s place, and takes it back with the chart', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    await pumpFeedShell(
      tester,
      scene: FeedShellScene.game,
      phone: feedIphone15,
      play: false,
    );
    BackdropFilter backdrop() => tester.widget<BackdropFilter>(
      find
          .descendant(
            of: find.byType(FeedRailGlass),
            matching: find.byType(BackdropFilter),
          )
          .first,
    );
    expect(backdrop().enabled, isTrue);
    final cell = tester.getRect(
      find.byKey(const ValueKey('feed_like_button')).first,
    );

    tester
        .widget<FeedLiveBoard>(find.byType(FeedLiveBoard).first)
        .onMove(NormalMove(from: Square.e2, to: Square.e3));
    await tester.pump();
    expect(find.text('Your line'), findsOneWidget);
    expect(
      tester.widgetList<FeedRailGlass>(find.byType(FeedRailGlass)).first.shown,
      isFalse,
    );
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Faded all the way: no backdrop layer is left behind the marks, and
    // they have not moved.
    expect(backdrop().enabled, isFalse);
    expect(
      tester.getRect(find.byKey(const ValueKey('feed_like_button')).first),
      cell,
    );

    await tester.tap(find.byKey(const ValueKey('feed_back_to_game')));
    await tester.pump();
    expect(
      tester.widgetList<FeedRailGlass>(find.byType(FeedRailGlass)).first.shown,
      isTrue,
    );
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(backdrop().enabled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

/// The rect of the one widget [finder] matches that is on the screen of
/// [size] (the pages around the current one are built off screen).
Rect _onScreen(WidgetTester tester, Finder finder, Size size) {
  for (final element in finder.evaluate()) {
    final box = element.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.top >= 0 && rect.bottom <= size.height) return rect;
  }
  fail('nothing of $finder on screen');
}
