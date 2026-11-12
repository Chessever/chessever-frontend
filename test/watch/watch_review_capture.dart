import 'dart:io';
import 'dart:ui' as ui;
import 'package:chessever2/watch/ui/watch_board.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// `--dart-define=WATCH_REVIEW_CAPTURE=true` writes real 3x screenshots of
/// the screens a test passes through to `build/watch-review`, for a visual
/// check off-watch. Off by default: the tests then cost nothing extra.
const watchReviewCapture = bool.fromEnvironment('WATCH_REVIEW_CAPTURE');

const watchReviewKey = Key('watch-render');

/// Loads the real watch faces (macOS only) so a capture reads as on the
/// device; the tests' own assertions never depend on it.
Future<void> watchReviewFonts() async {
  if (!watchReviewCapture || !Platform.isMacOS) return;
  final font = File('/System/Library/Fonts/SFCompact.ttf');
  if (!font.existsSync()) return;
  for (final family in ['CupertinoSystemText', 'CupertinoSystemDisplay']) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
    await loader.load();
  }
  final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
    ..addFont(
      rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
    );
  await icons.load();
}

Widget watchReviewBoundary(Widget child) =>
    RepaintBoundary(key: watchReviewKey, child: child);

Future<void> watchReviewShot(WidgetTester tester, String name) async {
  if (!watchReviewCapture) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(watchReviewKey),
  );
  if (find.byType(WatchBoard).evaluate().isNotEmpty) {
    final context = tester.element(find.byType(WatchBoard).first);
    await tester.runAsync(
      () => Future.wait([
        for (final color in ['w', 'b'])
          for (final role in ['P', 'N', 'B', 'R', 'Q', 'K'])
            precacheImage(
              AssetImage(
                'packages/chessground/assets/piece_sets/cburnett/$color$role.webp',
              ),
              context,
            ),
      ]),
    );
    await tester.pump();
  }
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/watch-review/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
