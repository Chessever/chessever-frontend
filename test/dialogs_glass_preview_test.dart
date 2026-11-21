// Group G5 ("dialogs") of the popup sweep: renders every popup of the group
// open over a busy page of live boards, in light and dark, at a 393x852
// phone view, 3x, for review.
//
//   flutter test --no-pub test/dialogs_glass_preview_test.dart \
//     --dart-define=POPUP_SWEEP_DIR=/tmp/popup_sweep/dialogs/after
//
// Only entry points that exist before and after the sweep are used, so the
// same file renders the "before" set from a scratch export of HEAD. Without
// POPUP_SWEEP_DIR the scenes still run as a smoke test and write nothing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dialogs_harness.dart';

const _outDir = String.fromEnvironment('POPUP_SWEEP_DIR');

Future<void> loadDialogsFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
      );
    }
    await loader.load();
  }

  final inter = [
    for (final weight in ['Regular', 'Medium', 'Bold'])
      'assets/fonts/Inter-$weight.otf',
  ];
  await family('InterDisplay', inter);
  await family('Inter', inter);
  // Styles that name no family take the theme's default (Roboto on the
  // test platform): give it Inter so they render as type.
  await family('Roboto', inter);
  // Styles with no family at all fall to the test font: Inter there too.
  await family('FlutterTest', inter);
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) await family('MaterialIcons', [icons.path]);
}

Future<void> shotDialogs(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  if (_outDir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(dialogsCapture),
    );
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(_outDir).create(recursive: true);
    await File('$_outDir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadDialogsFonts();
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
  });

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';
    for (final scene in dialogScenes) {
      testWidgets('${scene.name} over live boards, $theme', (tester) async {
        // Real shadows: flutter_test draws every shadow as an unblurred
        // block otherwise, which is not what a phone shows.
        debugDisableShadows = false;
        try {
          muteDialogsPlatform(tester);
          final opener = await scene.open(tester, light: light);
          opener();
          await tester.pump(scene.firstPump);
          var extra = 0;
          while (scene.shown().evaluate().isEmpty && extra < 20) {
            await tester.pump();
            extra++;
          }
          expect(scene.shown(), findsWidgets);
          // Come to rest (popups with a looping glyph or confetti: a second
          // and a half in, the glyph mid-demo, the confetti mid-fall).
          await settleDialogs(tester, limit: 90);
          await shotDialogs(tester, '${scene.name}_$theme');
          await scene.close?.call(tester);
          await tester.pumpWidget(const SizedBox());
        } finally {
          debugDisableShadows = true;
        }
      });
    }
  }
}
