// The popup consolidation's rules:
//
// - one sheet glass ([GlassSheet], ChessSheetGlass its preset), bleeding
//   past the screen's sides so only the top lip draws a rim;
// - the frost rule (PopupGlassStyle.frostMaxScreenShare): a panel taller
//   than 60% of the screen, or one that says so (solid), is an opaque
//   plate in its own tone with no live blur, decided once, and a frosted
//   sheet averages to the same tone;
// - a bar pinned in a solid sheet (PopupGlassFill) is the sheet's own
//   material: no band across it;
// - light glass keeps the brand's mint instead of going neutral grey;
// - Material glass sheets ride the sheet spring, not Material's curve;
// - the share preview opens at its final height;
// - the date picker in Prep's options sits on the glass;
// - the share overlay's controls are the popups' glass, its card is not;
// - a tooltip is a solid chip of the glass, never a blur.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chessever2/screens/chessboard/widgets/share_game_card_overlay.dart';
import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_options_dialog.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/widgets/glass_dialog_route.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessever2/widgets/smooth_bottom_sheet.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _screen = Size(393, 852);
const _capture = ValueKey('capture');

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _screen;
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  addTearDown(tester.view.reset);
}

/// The page under a popup, flat: the theme's background.
Widget _host({
  required bool light,
  required Widget Function(BuildContext) panel,
}) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
    home: Builder(
      builder: (context) {
        ResponsiveHelper.init(context);
        final scrim = glassSheetBarrier(context);
        return Scaffold(
          backgroundColor: context.colors.background,
          body: Stack(
            children: [
              // The glass scrim over a flat page: what the plate is solved
              // over.
              Positioned.fill(child: ColoredBox(color: scrim)),
              Align(alignment: Alignment.bottomCenter, child: panel(context)),
            ],
          ),
        );
      },
    ),
  ),
);

RenderBackdropFilter _filter(WidgetTester tester) =>
    tester.renderObject<RenderBackdropFilter>(
      find.descendant(
        of: find.byType(PopupGlass),
        matching: find.byType(BackdropFilter),
      ),
    );

/// The mean colour over [rect] (logical), from the capture at 1x: the grain
/// is zero-mean, so the mean is the plate's tone.
Future<Color> _mean(WidgetTester tester, Rect rect) async {
  late Color mean;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var r = 0, g = 0, b = 0, n = 0;
    for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
      for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
        final i = (y * image.width + x) * 4;
        r += data.getUint8(i);
        g += data.getUint8(i + 1);
        b += data.getUint8(i + 2);
        n++;
      }
    }
    image.dispose();
    mean = Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
  });
  return mean;
}

int _channel(double v) => (v * 255).round();

void main() {
  group('the frost rule', () {
    for (final light in [false, true]) {
      final theme = light ? 'light' : 'dark';
      testWidgets('a short sheet blurs live, a tall one does not, and both '
          'are the sheet\'s own tone, $theme', (tester) async {
        _phone(tester);
        final means = <Color>[];
        for (final height in [300.0, _screen.height * 0.9]) {
          // A fresh panel each time: the choice is held per panel.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            _host(
              light: light,
              panel: (context) => GlassSheet(
                radius: 20,
                height: height,
                child: const SizedBox.expand(),
              ),
            ),
          );
          await tester.pump();
          final tall =
              height > _screen.height * PopupGlassStyle.frostMaxScreenShare;
          expect(_filter(tester).enabled, !tall, reason: 'height $height');
          // Under the top sheen, inside the rim.
          final panel = tester.getRect(find.byType(GlassSheet));
          means.add(
            await _mean(
              tester,
              Rect.fromLTRB(
                panel.left + 8,
                panel.top + PopupGlassStyle.sheenDepth + 8,
                panel.right - 8,
                panel.bottom - 8,
              ),
            ),
          );
        }
        final context = tester.element(find.byType(PopupGlass));
        // The sheet's own tone: the brand's paper in light, the neutral
        // surface in dark.
        final expected = context.colors.surface;
        // The same material: the solid panel reads as the frosted one.
        expect(_channel(means[0].r), closeTo(_channel(means[1].r), 1));
        expect(_channel(means[0].g), closeTo(_channel(means[1].g), 1));
        expect(_channel(means[0].b), closeTo(_channel(means[1].b), 1));
        // And both are that tone (the grain, laid with less headroom above
        // paper than below, pulls light glass a hair down).
        for (final mean in means) {
          expect(_channel(mean.r), closeTo(_channel(expected.r), 3));
          expect(_channel(mean.g), closeTo(_channel(expected.g), 3));
          expect(_channel(mean.b), closeTo(_channel(expected.b), 3));
        }
      });
    }

    testWidgets('the choice is made once: a sheet that grows keeps its frost, '
        'one that shrinks stays solid', (tester) async {
      _phone(tester);
      Future<void> pump(double height) => tester.pumpWidget(
        _host(
          light: false,
          panel: (_) => GlassSheet(
            radius: 20,
            height: height,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await pump(300);
      expect(_filter(tester).enabled, isTrue);
      await pump(760);
      expect(_filter(tester).enabled, isTrue);

      await tester.pumpWidget(const SizedBox());
      await pump(760);
      expect(_filter(tester).enabled, isFalse);
      // A rebuild hands the filter back enabled: it stays off.
      await pump(740);
      expect(_filter(tester).enabled, isFalse);
      await pump(300);
      expect(_filter(tester).enabled, isFalse);
    });

    testWidgets('a new screen decides again', (tester) async {
      _phone(tester);
      Widget sheet() => _host(
        light: false,
        panel: (_) =>
            const GlassSheet(radius: 20, height: 600, child: SizedBox.expand()),
      );
      await tester.pumpWidget(sheet());
      expect(_filter(tester).enabled, isFalse);
      // A taller screen (a tablet in portrait): 600 is now short.
      tester.view.physicalSize = const Size(820, 1180);
      await tester.pumpWidget(sheet());
      await tester.pump();
      expect(_filter(tester).enabled, isTrue);
    });

    testWidgets('the line sits at 60% of the screen: a sheet just under it '
        'frosts, one just over it is solid', (tester) async {
      _phone(tester);
      expect(PopupGlassStyle.frostMaxScreenShare, 0.6);
      final line = _screen.height * PopupGlassStyle.frostMaxScreenShare;
      for (final (height, frosted) in [
        (line - 4, true),
        (line + 4, false),
        // A full-height page.
        (_screen.height * 0.9, false),
      ]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _host(
            light: true,
            panel: (_) => GlassSheet(
              radius: 20,
              height: height,
              child: const SizedBox.expand(),
            ),
          ),
        );
        await tester.pump();
        expect(_filter(tester).enabled, frosted, reason: 'height $height');
      }
    });

    testWidgets('a full-height page declared solid stays solid even when its '
        'first frame lays out short', (tester) async {
      _phone(tester);
      Future<void> pump(double height) => tester.pumpWidget(
        _host(
          light: false,
          panel: (_) => GlassSheet(
            radius: 20,
            height: height,
            solid: true,
            child: const SizedBox.expand(),
          ),
        ),
      );
      // A loading list, then the full page.
      await pump(200);
      expect(find.byType(BackdropFilter), findsNothing);
      await pump(_screen.height * 0.9);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('a solid sheet has no backdrop filter at any height, and '
        'is its tone', (tester) async {
      _phone(tester);
      for (final light in [false, true]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _host(
            light: light,
            panel: (_) => const GlassSheet(
              radius: 20,
              height: 300,
              solid: true,
              child: SizedBox.expand(),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(BackdropFilter), findsNothing);
        final panel = tester.getRect(find.byType(GlassSheet));
        final mean = await _mean(
          tester,
          Rect.fromLTRB(
            panel.left + 8,
            panel.top + PopupGlassStyle.sheenDepth + 8,
            panel.right - 8,
            panel.bottom - 8,
          ),
        );
        final tone = tester.element(find.byType(PopupGlass)).colors.surface;
        expect(_channel(mean.r), closeTo(_channel(tone.r), 3));
        expect(_channel(mean.g), closeTo(_channel(tone.g), 3));
        expect(_channel(mean.b), closeTo(_channel(tone.b), 3));
      }
    });

    testWidgets('a bar pinned in a solid sheet is the sheet itself', (
      tester,
    ) async {
      _phone(tester);
      for (final light in [false, true]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _host(
            light: light,
            panel: (context) => GlassSheet(
              radius: 20,
              height: 400,
              solid: true,
              // A tone of its own, to prove the bar takes the glass's.
              tone: context.colors.surfaceElevated,
              child: const Column(
                children: [
                  Spacer(),
                  PopupGlassFill(
                    child: SizedBox(height: 80, width: double.infinity),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        final bar = tester.getRect(find.byType(PopupGlassFill));
        final inBar = await _mean(tester, bar.deflate(8));
        final above = await _mean(
          tester,
          Rect.fromLTRB(bar.left + 8, bar.top - 90, bar.right - 8, bar.top - 8),
        );
        final tone = tester
            .element(find.byType(PopupGlass))
            .colors
            .surfaceElevated;
        for (final (a, b, t) in [
          (inBar.r, above.r, tone.r),
          (inBar.g, above.g, tone.g),
          (inBar.b, above.b, tone.b),
        ]) {
          expect(_channel(a), closeTo(_channel(b), 1), reason: 'light $light');
          expect(_channel(a), closeTo(_channel(t), 3), reason: 'light $light');
        }
      }
    });

    testWidgets('PopupGlassNoFrost takes the blur from a short panel', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _host(
          light: false,
          panel: (_) => const PopupGlassNoFrost(
            child: GlassSheet(radius: 20, height: 200, child: SizedBox()),
          ),
        ),
      );
      expect(_filter(tester).enabled, isFalse);
    });
  });

  group('one sheet glass', () {
    testWidgets('it bleeds past the sides and bottom, so no rim runs along '
        "the screen's edges", (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _host(
          light: true,
          panel: (_) => const GlassSheet(
            radius: 20,
            height: 300,
            child: SizedBox.expand(),
          ),
        ),
      );
      final sheet = tester.getRect(find.byType(GlassSheet));
      final glass = tester.getRect(find.byType(PopupGlass));
      expect(sheet.left, 0);
      expect(sheet.right, _screen.width);
      expect(glass.left, sheet.left - GlassSheet.bleed);
      expect(glass.right, sheet.right + GlassSheet.bleed);
      expect(glass.bottom, sheet.bottom + GlassSheet.bleed);
      expect(glass.top, sheet.top);
    });

    test('ChessSheetGlass is the same glass, on a Material', () {
      const glass = ChessSheetGlass(child: SizedBox());
      expect(glass, isA<GlassSheet>());
      expect(glass.inkSurface, isTrue);
      expect(glass.radius, 28);
    });
  });

  testWidgets('light glass keeps the mint of the surface it is solved to', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final light = context.colors;
    for (final tone in [light.surface, light.surfaceElevated, light.popup]) {
      // The plate over the page it is solved over.
      final glass = Color.alphaBlend(
        PopupGlassStyle.of(context, tone: tone).plate,
        PopupGlassStyle.pageUnder(context),
      );
      // Same hue and chroma: every channel moved by the same step.
      final dr = _channel(tone.r) - _channel(glass.r);
      final dg = _channel(tone.g) - _channel(glass.g);
      final db = _channel(tone.b) - _channel(glass.b);
      expect((dr - dg).abs(), lessThanOrEqualTo(1), reason: '$tone');
      expect((dr - db).abs(), lessThanOrEqualTo(1), reason: '$tone');
      // The brand's mint, not grey: green and blue stand above red.
      expect(_channel(glass.g) - _channel(glass.r), greaterThanOrEqualTo(4));
      // At most a step darker than the surface it stands for.
      expect(dr, lessThanOrEqualTo(8));
    }
  });

  group('Material glass sheets', () {
    Future<void> open(WidgetTester tester) async {
      _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showGlassModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const GlassSheet(
                      radius: 20,
                      height: 320,
                      child: Center(child: Text('Sheet')),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
    }

    testWidgets('slide on the sheet spring, parked for the frame that '
        'builds them', (tester) async {
      await open(tester);
      await tester.pump();
      final route = ModalRoute.of(tester.element(find.text('Sheet')))!;
      expect(route, isA<GlassModalSheetRoute<void>>());
      expect(route, isA<SpringSheetTransition<void>>());
      // The frame that built the sheet showed it nowhere.
      expect(route.animation!.value, 0);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));
      final early = route.animation!.value;
      expect(early, greaterThan(0));
      expect(early, lessThan(1));
      await tester.pumpAndSettle();
      expect(route.animation!.value, 1);
    });

    testWidgets('a short drag let go springs back, not along a line', (
      tester,
    ) async {
      await open(tester);
      await tester.pumpAndSettle();
      final route = ModalRoute.of(tester.element(find.text('Sheet')))!;
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Sheet')),
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      final pulled = route.animation!.value;
      expect(pulled, lessThan(1));
      await gesture.up();
      // A spring gathers speed and eases into rest; a linear run would close
      // the same share on every frame.
      final values = <double>[];
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        values.add(route.animation!.value);
      }
      final steps = [
        for (var i = 1; i < values.length; i++) values[i] - values[i - 1],
      ].where((step) => step > 0).toList();
      expect(steps.length, greaterThanOrEqualTo(3));
      final fastest = steps.reduce((a, b) => a > b ? a : b);
      final slowest = steps.reduce((a, b) => a < b ? a : b);
      expect(fastest, greaterThan(slowest * 1.5));
      await tester.pumpAndSettle();
      expect(route.animation!.value, 1);
      expect(find.text('Sheet'), findsOneWidget);
    });
  });

  group('the share preview', () {
    Uint8List png(int width, int height) {
      final bytes = Uint8List(33);
      bytes.setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final view = ByteData.sublistView(bytes);
      view.setUint32(8, 13);
      bytes.setAll(12, 'IHDR'.codeUnits);
      view.setUint32(16, width);
      view.setUint32(20, height);
      return bytes;
    }

    test('reads the aspect from a PNG or JPEG header', () {
      expect(shareImageAspectRatio(png(1080, 1350)), closeTo(0.8, 1e-9));
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, // APP0, 2 bytes of payload
        0xFF, 0xC0, 0x00, 0x11, 0x08, 0x05, 0x46, 0x04, 0x38, // SOF0
        0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
      ]);
      expect(shareImageAspectRatio(jpeg), closeTo(1080 / 1350, 1e-9));
      expect(shareImageAspectRatio(Uint8List.fromList([1, 2, 3])), isNull);
    });

    testWidgets('opens at its final height, before the image decodes', (
      tester,
    ) async {
      _phone(tester);
      late Uint8List image;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(const Color(0xFF9A7650), BlendMode.src);
        final picture = recorder.endRecording();
        final raster = await picture.toImage(1080, 1350);
        image = (await raster.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        raster.dispose();
        picture.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: TextButton(
                  onPressed: () => showShareImagePreview(
                    context,
                    imageBytes: image,
                    onShareImage: () async {},
                  ),
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      final first = tester.getSize(find.byType(GlassSheet)).height;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final rest = tester.getSize(find.byType(GlassSheet)).height;
      expect(first, rest);
      // Most of the screen: the picture's box is held from the first frame.
      expect(rest, greaterThan(_screen.height * 0.6));
    });
  });

  testWidgets("Prep's date picker sits on the glass and hands back the date", (
    tester,
  ) async {
    _phone(tester);
    PrepDownloadPreferences? got;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: SingleChildScrollView(
                child: PrepScopeFields(
                  sources: const [PrepSource.lichess],
                  value: PrepDownloadPreferences(
                    range: PrepDateRange.custom,
                    fromDate: DateTime.utc(2026, 3, 10),
                  ),
                  onChanged: (value) => got = value,
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-03-10'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.byType(DatePickerDialog))),
      isA<GlassDialogRoute<DateTime>>(),
    );
    // The glass is laid under the picker's own card.
    final glass = find.descendant(
      of: find.byType(GlassAlertFrame),
      matching: find.byType(PopupGlass),
    );
    expect(glass, findsOneWidget);
    final card = tester.getRect(glass);
    expect(card.width, greaterThan(280));
    expect(card.height, greaterThan(300));
    // Nothing else paints a surface under it.
    final dialog = tester.widget<Dialog>(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.byType(Dialog),
      ),
    );
    expect(dialog.backgroundColor, Colors.transparent);
    await tester.tap(find.text('15'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(got?.fromDate, DateTime.utc(2026, 3, 15));
    expect(find.byType(DatePickerDialog), findsNothing);
  });

  testWidgets("the share overlay's controls are the popups' glass, and the "
      'card it shares is not', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final light in [false, true]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return ShareGameCardOverlay(
                  boardSettings: const ChessboardSettings(),
                  positionFen: '8/8/4k3/8/8/4K3/8/8 w - - 0 60',
                  lastMove: null,
                  pgn: '1. e4 e5 *',
                  moveSans: const ['e4', 'e5'],
                  whitePlayerName: 'Carlsen, Magnus',
                  blackPlayerName: 'Nakamura, Hikaru',
                  currentMoveIndex: 1,
                  evaluation: 0.0,
                  mate: 0,
                  isFlipped: false,
                  gameStatus: GameStatus.ongoing,
                  onClose: () {},
                  shareUrl: 'https://chessever.com/g/abc123',
                  gameId: 'test',
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      Finder glassOf(Finder content) =>
          find.ancestor(of: content, matching: find.byType(PopupGlass));
      // The eval switch, the link and the actions: each on its own glass,
      // frosted (they are short) over the overlay's stage.
      for (final control in [
        find.text('Eval Bar'),
        find.text('https://chessever.com/g/abc123'),
        find.text('Share GIF'),
      ]) {
        expect(glassOf(control), findsOneWidget, reason: '$control');
        expect(
          find.descendant(
            of: glassOf(control),
            matching: find.byType(BackdropFilter),
          ),
          findsOneWidget,
        );
      }
      // The card is the picture being shared: opaque, exactly as exported.
      final card = find.byKey(const ValueKey('share-preview-entrance'));
      expect(card, findsOneWidget);
      expect(glassOf(card), findsNothing);
      expect(
        find.descendant(of: card, matching: find.byType(PopupGlass)),
        findsNothing,
      );
    }
  });

  test('a tooltip is a solid chip of the glass in both themes', () {
    for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
      final decoration = theme.tooltipTheme.decoration;
      expect(decoration, isA<SolidGlassDecoration>());
      final chip = decoration! as SolidGlassDecoration;
      expect(chip.tone.a, 1, reason: 'an opaque plate');
      expect(chip.light, theme.brightness == Brightness.light);
      // Its type reads on it at AA or better.
      final ink = theme.tooltipTheme.textStyle!.color!;
      final hi = [ink, chip.tone].map((c) => c.computeLuminance()).toList()
        ..sort();
      expect((hi[1] + 0.05) / (hi[0] + 0.05), greaterThanOrEqualTo(7));
    }
  });
}
