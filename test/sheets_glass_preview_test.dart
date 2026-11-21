// Renders every bottom sheet over a busy Today page to PNGs, in light and
// dark, at a 393x852 phone view, 3x, and checks that sheet text clears AA on
// the glass over the busiest page.
//
//   flutter test --no-pub test/sheets_glass_preview_test.dart \
//     --dart-define=POPUP_SWEEP_DIR=/tmp/popup_sweep/sheets \
//     --dart-define=POPUP_SWEEP_PHASE=after
//
// Without POPUP_SWEEP_DIR the scenes still run as a smoke test and write
// nothing. Files are `<scene>_<theme>_<phase>.png`.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chessever2/screens/gamebase/widgets/position_games_sheet.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessever2/widgets/smooth_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sheets_harness.dart';
import 'sheets_scenes.dart';

const _outDir = String.fromEnvironment('POPUP_SWEEP_DIR');
const _phase = String.fromEnvironment(
  'POPUP_SWEEP_PHASE',
  defaultValue: 'after',
);

/// A scene with real shadows: flutter_test draws every shadow as an
/// unblurred block ([debugDisableShadows]), which is not what a phone shows.
void _scene(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List shareImage;
  var shareImageReady = false;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-publishable-key',
      // No deep-link listener (app_links has no test platform).
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
    await sheetsLoadFonts();
  });

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';
    for (final name in sheetScenes(
      shareImage: Uint8List(0),
    ).map((s) => s.name)) {
      _scene('$name over live boards, $theme', (tester) async {
        sheetsPhone(tester);
        if (!shareImageReady) {
          shareImage = await sheetsSharePng(tester);
          shareImageReady = true;
        }
        final scene = sheetScenes(
          shareImage: shareImage,
        ).firstWhere((s) => s.name == name);
        await tester.pumpWidget(
          sheetsHost(
            opener: scene.opener,
            light: light,
            overrides: scene.overrides,
          ),
        );
        await tester.pump();
        await sheetsPrecache(tester);
        sheetsTapOpen(tester);
        await tester.pump();
        await sheetsSettle(tester);
        // The share preview's image decodes off the frame.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await sheetsSettle(tester);
        expect(tester.takeException(), isNull);
        await sheetsShot(tester, _outDir, '${name}_${theme}_$_phase');
      });
    }

    // Every glass a sheet is cut from, over the busiest page: the surface
    // (most sheets), the page background (the start screen picker), the
    // popup tone (Manage subscription) and the explorer's (the games, sort
    // and filter sheets).
    for (final tone in ['surface', 'background', 'popup', 'explorer']) {
      _scene('sheet glass contrast over the busiest page, $tone, $theme', (
        tester,
      ) async {
        sheetsPhone(tester);
        await tester.pumpWidget(
          sheetsHost(
            light: light,
            opener: (context, ref) => showGlassModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (context) {
                const body = SizedBox(height: 520, width: double.infinity);
                final palette = context.colors;
                return switch (tone) {
                  'explorer' => const ExplorerSheetGlass(
                    radius: 20,
                    child: body,
                  ),
                  _ => GlassSheet(
                    radius: 20,
                    tone: switch (tone) {
                      'background' => palette.background,
                      'popup' => palette.popup,
                      _ => palette.surface,
                    },
                    child: body,
                  ),
                };
              },
            ),
          ),
        );
        await tester.pump();
        await sheetsPrecache(tester);
        sheetsTapOpen(tester);
        await tester.pump();
        await sheetsSettle(tester);
        final panel = tester.getRect(find.byType(PopupGlass));
        // What a glyph sits on: the plate averaged over 2x2 pt cells. The
        // grain is a sub-glyph dither (single specks lighter and darker
        // than the plate) and would otherwise decide the extremes.
        final cells = <Color>[];
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(sheetsCapture),
          );
          final image = await boundary.toImage(pixelRatio: 3);
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          // Under the top sheen, where body text sits.
          final inside = Rect.fromLTRB(
            panel.left + 4,
            panel.top + PopupGlassStyle.sheenDepth,
            panel.right - 4,
            panel.bottom - 4,
          );
          const cell = 6;
          for (
            var y = (inside.top * 3).ceil();
            y + cell <= inside.bottom * 3;
            y += cell
          ) {
            for (
              var x = (inside.left * 3).ceil();
              x + cell <= inside.right * 3;
              x += cell
            ) {
              var r = 0, g = 0, b = 0;
              for (var dy = 0; dy < cell; dy++) {
                for (var dx = 0; dx < cell; dx++) {
                  final i = ((y + dy) * image.width + x + dx) * 4;
                  r += data.getUint8(i);
                  g += data.getUint8(i + 1);
                  b += data.getUint8(i + 2);
                }
              }
              const n = cell * cell;
              cells.add(Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n));
            }
          }
          image.dispose();
        });
        cells.sort(
          (a, b) => a.computeLuminance().compareTo(b.computeLuminance()),
        );
        final darkest = cells.first;
        final lightest = cells.last;
        final colors = tester.element(find.byType(PopupGlass)).colors;
        final inks = {
          'textPrimary': colors.textPrimary,
          'textSecondary': colors.textSecondary,
          'body (textPrimary 70%)': colors.textPrimary.withValues(alpha: 0.7),
        };
        final report = <String>[];
        String hex(Color c) =>
            '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
        for (final MapEntry(key: ink, value: color) in inks.entries) {
          final worst = [
            wcagContrast(color, darkest),
            wcagContrast(color, lightest),
          ].reduce((a, b) => a < b ? a : b);
          report.add('$ink ${worst.toStringAsFixed(2)}:1');
          expect(worst, greaterThanOrEqualTo(4.5), reason: '$ink on $tone');
        }
        // ignore: avoid_print
        print(
          'CONTRAST sheet $theme $tone: plate ${hex(darkest)}..'
          '${hex(lightest)} | ${report.join(' | ')}',
        );
        if (tone == 'surface') {
          await sheetsShot(tester, _outDir, 'plate_empty_${theme}_$_phase');
        }
      });
    }
  }

  // Keeps the import honest at HEAD and after: the sheet opener exists.
  test('showSmoothBottomSheet is the sheet opener', () {
    expect(showSmoothBottomSheet, isA<Function>());
  });
}
