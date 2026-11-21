// Renders the Feed tab as the home shell holds it, to PNG, for a visual
// check of a post: the game post (at rest, at 1.3x text, with a six-figure
// like count), the puzzle post, the loading skeleton and a news post, in
// light and dark, on a tall iPhone and on the smallest phones Feed meets
// (360x640 Android with gesture or three-button navigation, the 375x667
// iPhone SE), each at 3x.
//
//   flutter test --no-pub --dart-define=FEED_PREVIEW_DIR=/tmp/out \
//     test/feed_polish_preview_test.dart
//
// Without FEED_PREVIEW_DIR every scene is skipped. Names on the player rows
// are raw RichText with no family, so they draw as the test host's box font.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/feed_shell_harness.dart';

const _outDir = String.fromEnvironment('FEED_PREVIEW_DIR');
const _capture = ValueKey('feed_preview_capture');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadFeedFonts);

  for (final shot in _shots) {
    for (final light in [false, true]) {
      final theme = light ? 'light' : 'dark';
      testWidgets('Feed ${shot.name}, $theme', (tester) async {
        SharedPreferences.setMockInitialValues(const {});
        await pumpFeedShell(
          tester,
          scene: shot.scene,
          phone: shot.device,
          light: light,
          textScale: shot.textScale,
          likes: shot.likes,
          captureKey: _capture,
        );
        await _shot(tester, '${shot.name}_$theme');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      }, skip: _outDir.isEmpty);
    }
  }
}

typedef _Shot = ({
  String name,
  FeedShellScene scene,
  FeedPhone device,
  double textScale,
  int likes,
});

const _bigLikes = 123456;

final List<_Shot> _shots = [
  for (final device in [feedIphone15]) ...[
    (
      name: 'game_${device.name}',
      scene: FeedShellScene.game,
      device: device,
      textScale: 1.0,
      likes: 128,
    ),
    (
      name: 'game_text130_${device.name}',
      scene: FeedShellScene.game,
      device: device,
      textScale: 1.3,
      likes: 128,
    ),
    (
      name: 'game_likes123456_text130_${device.name}',
      scene: FeedShellScene.game,
      device: device,
      textScale: 1.3,
      likes: _bigLikes,
    ),
    (
      name: 'puzzle_${device.name}',
      scene: FeedShellScene.puzzle,
      device: device,
      textScale: 1.0,
      likes: 0,
    ),
    (
      name: 'skeleton_${device.name}',
      scene: FeedShellScene.skeleton,
      device: device,
      textScale: 1.0,
      likes: 0,
    ),
    (
      name: 'news_${device.name}',
      scene: FeedShellScene.news,
      device: device,
      textScale: 1.0,
      likes: 0,
    ),
  ],
  for (final device in [
    feedAndroidGesture,
    feedAndroidButtons,
    feedIphoneSe,
  ]) ...[
    (
      name: 'game_${device.name}',
      scene: FeedShellScene.game,
      device: device,
      textScale: 1.0,
      likes: 128,
    ),
    (
      name: 'game_likes123456_text130_${device.name}',
      scene: FeedShellScene.game,
      device: device,
      textScale: 1.3,
      likes: _bigLikes,
    ),
    (
      name: 'puzzle_${device.name}',
      scene: FeedShellScene.puzzle,
      device: device,
      textScale: 1.0,
      likes: 0,
    ),
  ],
];

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(_outDir).create(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
