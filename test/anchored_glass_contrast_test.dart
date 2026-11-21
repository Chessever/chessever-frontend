// The anchored glass menus' legibility at their one dim ([AnchoredGlassDim]):
//
// * the control that opened a popdown (the board's game switcher chip, a
//   smart event's tier chip, an event's category chip) reads at 4.5:1 or
//   better while its panel is open: the dim leaves it out;
// * every ink an anchored panel sets reads on its glass, over the busiest
//   page (live boards) under that dim: 4.5:1 for text, 3:1 for icons.
//
//   flutter test --no-pub test/anchored_glass_contrast_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_anchored_route.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'g4_dropdowns_harness.dart';
import 'support/chessboard_surfaces_harness.dart';

const _capture = ValueKey('anchored_contrast_capture');

Future<ui.Image> _grab(WidgetTester tester, Key key) async {
  late ui.Image image;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
  });
  return image;
}

/// Every pixel of [rect] as drawn now.
Future<List<Color>> _pixels(WidgetTester tester, Rect rect, Key key) async {
  final image = await _grab(tester, key);
  final ratio = tester.view.devicePixelRatio;
  final pixels = <Color>[];
  await tester.runAsync(() async {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    for (var y = (rect.top * ratio).ceil(); y < rect.bottom * ratio; y++) {
      for (var x = (rect.left * ratio).ceil(); x < rect.right * ratio; x++) {
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
  });
  image.dispose();
  return pixels;
}

/// How the control in [rect] reads as drawn: its most frequent pixel is its
/// ground, the pixel furthest from that its ink (a glyph's fully covered
/// stem), and the WCAG ratio between the two.
Future<double> _renderedContrast(
  WidgetTester tester,
  Rect rect,
  Key key,
) async {
  final pixels = await _pixels(tester, rect, key);
  final counts = <int, int>{};
  for (final pixel in pixels) {
    counts.update(pixel.toARGB32(), (n) => n + 1, ifAbsent: () => 1);
  }
  final ground = Color(
    counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key,
  );
  var best = 1.0;
  for (final pixel in pixels) {
    final contrast = wcagContrast(pixel, ground);
    if (contrast > best) best = contrast;
  }
  return best;
}

/// The scrim painter an open popdown dims the page with.
GlassScrimPainter _dim(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<GlassScrimPainter>()
    .single;

Future<void> _loadFonts() async {
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
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'swipable_walkthrough_dont_show': true,
      'explorer_panel_walkthrough_dont_show': true,
      'like_walkthrough_dont_show': true,
      'board_pinch_coachmark_dont_show': true,
    });
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-anon-key',
    );
    GameAnalysisReportStore.debugSetInstance(GameAnalysisReportStore.memory());
    await _loadFonts();
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
  });

  tearDownAll(GameAnalysisReportStore.debugResetInstance);

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';

    testWidgets('the game switcher chip reads while its panel is open, '
        '$theme', (tester) async {
      final board = await pumpSurfacesBoard(
        tester,
        light: light,
        wrap: (app) => RepaintBoundary(key: _capture, child: app),
      );
      board.tapGameSwitcher();
      await tester.pump();
      await board.settle();
      final chip = tester.getRect(
        find.byKey(e2eKey(E2eIds.boardGameSelector)).first,
      );
      // The one anchored dim, leaving the chip out, whole.
      final dim = _dim(tester);
      expect(
        dim.color,
        AnchoredGlassDim.colorOf(
          tester.element(find.byKey(e2eKey(E2eIds.boardGameSelector)).first),
        ),
      );
      expect(dim.hole, isNotNull);
      expect(dim.hole!.outerRect.inflate(0.5).contains(chip.topLeft), isTrue);
      expect(
        dim.hole!.outerRect.inflate(0.5).contains(chip.bottomRight),
        isTrue,
      );
      final contrast = await _renderedContrast(tester, chip, _capture);
      // ignore: avoid_print
      print(
        'CHIPCONTRAST game_switcher_chip $theme: '
        '${contrast.toStringAsFixed(2)}:1',
      );
      expect(contrast, greaterThanOrEqualTo(4.5));
      await board.dispose();
    });

    for (final (sceneName, label) in [
      ('smart_event_tier', 'smart event tier chip'),
      ('category_dropdown', 'event category chip'),
    ]) {
      testWidgets('the $label reads while its panel is open, $theme', (
        tester,
      ) async {
        final scene = g4Scenes.firstWhere((s) => s.name == sceneName);
        await scene.pump(tester, light: light);
        final trigger = scene.trigger().first;
        final opener = sceneName == 'smart_event_tier'
            ? find
                  .ancestor(
                    of: trigger,
                    matching: find.byType(AnimatedContainer),
                  )
                  .first
            : trigger;
        final chip = tester.getRect(opener);
        await g4Open(tester, scene);
        await g4Settle(tester, cap: 90);
        final dim = _dim(tester);
        expect(dim.color, AnchoredGlassDim.colorOf(tester.element(opener)));
        expect(dim.hole, isNotNull);
        expect(dim.hole!.outerRect.inflate(0.5).contains(chip.topLeft), isTrue);
        expect(
          dim.hole!.outerRect.inflate(0.5).contains(chip.bottomRight),
          isTrue,
        );
        final contrast = await _renderedContrast(tester, chip, g4Capture);
        // ignore: avoid_print
        print(
          'CHIPCONTRAST $sceneName $theme: '
          '${contrast.toStringAsFixed(2)}:1',
        );
        expect(contrast, greaterThanOrEqualTo(4.5));
        await tester.pumpWidget(const SizedBox.shrink());
        // The category scene's realtime channel leaves a 50 s timer.
        await tester.pump(const Duration(minutes: 1));
      });
    }

    // Every tone an anchored panel averages to, empty, over live boards
    // under the one anchored dim: the worst pixel of the glass decides
    // whether the inks drawn on it read.
    testWidgets('anchored panels read over live boards, $theme', (
      tester,
    ) async {
      debugDisableShadows = false;
      try {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = g4Screen * 3;
        addTearDown(tester.view.reset);
        late BuildContext page;
        final tones = <String, Color Function(AppColors)>{
          'surface (menus, dropdowns, game switcher, chips)': (c) => c.surface,
          'popup (add button, light)': (c) => c.popup,
          'surfaceElevated (tag picker)': (c) => c.surfaceElevated,
          'surfaceRecessed (board hold menu)': (c) => c.surfaceRecessed,
        };
        final names = tones.keys.toList();
        await tester.pumpWidget(
          RepaintBoundary(
            key: _capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  page = context;
                  return Scaffold(
                    body: Stack(
                      children: [
                        const Positioned.fill(child: G4BusyBoards(top: 60)),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: GlassScrimPainter(
                              color: AnchoredGlassDim.colorOf(context),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          top: 80,
                          bottom: 40,
                          child: Column(
                            children: [
                              for (final tone in tones.values)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: PopupGlass(
                                      borderRadius: BorderRadius.circular(16),
                                      tone: tone(context.colors),
                                      page: AnchoredGlassDim.pageOf(context),
                                      cover: AnchoredGlassDim.cover,
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                                ),
                            ],
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
        await tester.runAsync(() async {
          for (final widget in tester.widgetList<Image>(find.byType(Image))) {
            await precacheImage(widget.image, page);
          }
        });
        await tester.pump();
        await tester.pump();
        final colors = page.colors;
        // The text each tone carries in an anchored panel. Floors are AA
        // (4.5:1), but for the destructive red, which reads under AA on its
        // tone even opaque (dark surface 4.8:1, the recessed tone under 4.5
        // in both themes): it must not read worse than it did at the
        // dialogs' darker dim.
        final inksOf = <String, Map<String, (Color, double)>>{
          names[0]: {
            'textPrimary': (colors.textPrimary, 4.5),
            'textPrimary 85%': (
              colors.textPrimary.withValues(alpha: 0.85),
              4.5,
            ),
            'textSecondary': (colors.textSecondary, 4.5),
            'accentText': (colors.accentText, 4.5),
            'danger (favorites menu)': (colors.danger, light ? 4.5 : 4.0),
          },
          names[1]: {
            'textPrimary': (colors.textPrimary, 4.5),
            'textSecondary (title)': (colors.textSecondary, 4.5),
          },
          names[2]: {
            'textPrimary': (colors.textPrimary, 4.5),
            'textSecondary (header)': (colors.textSecondary, 4.5),
            'accentText (Save)': (colors.accentText, 4.5),
          },
          names[3]: {
            'textPrimary': (colors.textPrimary, 4.5),
            'danger (clear analysis)': (colors.danger, light ? 3.0 : 3.3),
          },
        };
        final panels = find.byType(PopupGlass).evaluate().toList();
        for (var i = 0; i < panels.length; i++) {
          final rect = tester.getRect(
            find.byElementPredicate((e) => identical(e, panels[i])),
          );
          final pixels = await _pixels(tester, rect.deflate(4), _capture);
          pixels.sort(
            (a, b) => a.computeLuminance().compareTo(b.computeLuminance()),
          );
          final darkest = pixels[pixels.length ~/ 200];
          final lightest = pixels[pixels.length - 1 - pixels.length ~/ 200];
          double worst(Color ink) => [
            wcagContrast(ink, darkest),
            wcagContrast(ink, lightest),
          ].reduce((a, b) => a < b ? a : b);
          final tone = tones.values.elementAt(i)(colors);
          final inks = inksOf[names[i]]!;
          final report = [
            for (final MapEntry(key: name, value: (ink, _)) in inks.entries)
              '$name ${worst(ink).toStringAsFixed(2)}:1 '
                  '(opaque ${wcagContrast(Color.alphaBlend(ink, tone), tone).toStringAsFixed(2)})',
            'icon ${worst(colors.iconPrimary).toStringAsFixed(2)}:1',
          ];
          // ignore: avoid_print
          print('ANCHOREDCONTRAST $theme ${names[i]}: ${report.join(' | ')}');
          for (final MapEntry(key: name, value: (ink, floor)) in inks.entries) {
            expect(
              worst(ink),
              greaterThanOrEqualTo(floor),
              reason: '$name on ${names[i]}, $theme',
            );
          }
          expect(
            worst(colors.iconPrimary),
            greaterThanOrEqualTo(3),
            reason: 'icons on ${names[i]}, $theme',
          );
        }
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
