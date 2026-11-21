// Renders every G4 popover (dropdown menus and anchored panels) open over a
// busy page of live boards, in light and dark, at a 393x852 phone, 3x.
//
//   flutter test --no-pub test/g4_dropdowns_preview_test.dart \
//     --dart-define=POPUP_SWEEP_DIR=/tmp/popup_sweep/G4 \
//     --dart-define=POPUP_SWEEP_TAG=after
//
// Without POPUP_SWEEP_DIR the scenes still run as a smoke test and write
// nothing. The tag names the files (`<scene>_<theme>_<tag>.png`), so a run of
// the code before a change and one after sit side by side.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_dropdown.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'g4_dropdowns_harness.dart';

const _outDir = String.fromEnvironment('POPUP_SWEEP_DIR');
const _tag = String.fromEnvironment('POPUP_SWEEP_TAG', defaultValue: 'after');

Future<void> _precache(WidgetTester tester) async {
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Scaffold).first);
    for (final widget in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(widget.image, context);
    }
    for (final box in tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    )) {
      final decoration = box.decoration;
      if (decoration is BoxDecoration && decoration.image != null) {
        await precacheImage(decoration.image!.image, context);
      }
    }
  });
  await tester.pump();
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (_outDir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(g4Capture),
    );
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(_outDir).create(recursive: true);
    await File(
      '$_outDir/${name}_$_tag.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
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
    await family('Roboto', inter);
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) await family('MaterialIcons', [icons.path]);
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
  });

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';

    // Every ink a G4 menu draws, over an empty popover panel laid on the
    // live boards under the popover's (lighter than a dialog's) scrim: the
    // worst pixel of the plate decides legibility.
    testWidgets('popover plate contrast over live boards, $theme', (
      tester,
    ) async {
      debugDisableShadows = false;
      try {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = g4Screen * 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          RepaintBoundary(
            key: g4Capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return Scaffold(
                    body: Stack(
                      children: [
                        const Positioned.fill(child: G4BusyBoards(top: 60)),
                        Positioned.fill(
                          child: GlassPopoverLayer(
                            left: 16,
                            top: 80,
                            child: GlassPopoverPanel(
                              width: 361,
                              height: 600,
                              borderRadius: BorderRadius.circular(16),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await _precache(tester);
        await g4Settle(tester, cap: 90);
        final panel = tester.getRect(find.byType(PopupGlass));
        final pixels = <Color>[];
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(g4Capture),
          );
          final image = await boundary.toImage(pixelRatio: 3);
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final inside = panel.deflate(4);
          for (var y = (inside.top * 3).ceil(); y < inside.bottom * 3; y++) {
            for (var x = (inside.left * 3).ceil(); x < inside.right * 3; x++) {
              final i = (y * image.width + x) * 4;
              pixels.add(
                Color.fromARGB(
                  255,
                  data.getUint8(i),
                  data.getUint8(i + 1),
                  data.getUint8(i + 2),
                ),
              );
            }
          }
          image.dispose();
        });
        pixels.sort(
          (a, b) => a.computeLuminance().compareTo(b.computeLuminance()),
        );
        final darkest = pixels[pixels.length ~/ 200];
        final lightest = pixels[pixels.length - 1 - pixels.length ~/ 200];
        final context = tester.element(find.byType(Scaffold).first);
        final colors = context.colors;
        // Every ink a G4 menu sets as text. textSecondary only draws icons
        // inside these menus (the calendar's All Formats mark): 3:1 for it.
        final inks = {
          'textPrimary': colors.textPrimary,
          'round name (textPrimary 85%)': colors.textPrimary.withValues(
            alpha: 0.85,
          ),
          'date (textInk 0.5)': context.textInk(0.5),
          'count (textInk 0.55)': context.textInk(0.55),
          'accentText': colors.accentText,
        };
        String hex(Color c) =>
            '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
        final report = <String>[];
        final worstOf = <String, double>{};
        for (final MapEntry(key: name, value: ink) in inks.entries) {
          final worst = [
            wcagContrast(ink, darkest),
            wcagContrast(ink, lightest),
          ].reduce((a, b) => a < b ? a : b);
          report.add('$name ${worst.toStringAsFixed(2)}:1');
          worstOf[name] = worst;
        }
        // ignore: avoid_print
        print(
          'G4CONTRAST $theme: plate ${hex(darkest)}..${hex(lightest)} | '
          '${report.join(' | ')}',
        );
        for (final MapEntry(key: name, value: worst) in worstOf.entries) {
          expect(worst, greaterThanOrEqualTo(4.5), reason: '$name, $theme');
        }
        final icon = [
          wcagContrast(colors.textSecondary, darkest),
          wcagContrast(colors.textSecondary, lightest),
        ].reduce((a, b) => a < b ? a : b);
        // ignore: avoid_print
        print(
          'G4CONTRAST $theme: icon ink textSecondary ${icon.toStringAsFixed(2)}:1',
        );
        expect(icon, greaterThanOrEqualTo(3), reason: 'icon ink, $theme');
        await _shot(tester, 'popover_plate_$theme');
      } finally {
        debugDisableShadows = true;
      }
    });

    for (final scene in g4Scenes) {
      testWidgets('${scene.name} open over live boards, $theme', (
        tester,
      ) async {
        // Real shadows: flutter_test otherwise draws them as hard blocks.
        debugDisableShadows = false;
        try {
          await scene.pump(tester, light: light);
          await _precache(tester);
          final frames = await g4Open(tester, scene);
          expect(frames, lessThan(12), reason: 'the popover never showed');
          await g4Settle(tester, cap: 90);
          await _precache(tester);
          expect(tester.takeException(), isNull);
          await _shot(tester, '${scene.name}_$theme');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 30));
        } finally {
          debugDisableShadows = true;
        }
      });
    }
  }
}
