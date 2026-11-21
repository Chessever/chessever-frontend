// Times what opening (and closing) each bottom sheet costs over a busy page,
// and pins the shape of the cure: no full-screen or animated blur behind any
// sheet, at most one backdrop filter, sized to the sheet.
//
//   flutter test --no-pub test/sheets_open_perf_test.dart
//
// Every number is a median of several runs, printed as a `PERF` line. These
// are host timings (debug JIT, software raster): a proxy for the device,
// good for before/after ratios, not for absolute milliseconds.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/smooth_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sheets_harness.dart';
import 'sheets_scenes.dart';

const _runs = 5;

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

String _ms(double value) => '${value.toStringAsFixed(2)} ms';

/// Every BackdropFilter on screen, with its size and its filter, and
/// whether it blurs live (a tall sheet keeps the glass without it).
List<(String, Size)> _backdrops(WidgetTester tester) => [
  for (final element in find.byType(BackdropFilter).evaluate())
    (
      '${(element.widget as BackdropFilter).filter}'
          '${(element.renderObject! as RenderBackdropFilter).enabled ? '' : ' (not live)'}',
      (element.renderObject! as RenderBox).size,
    ),
];

/// How the A/B sheet is surfaced.
enum _Surface {
  /// The old opaque surface.
  opaque,

  /// The glass, under the frost rule (solid past 60% of the screen).
  glass,

  /// The glass declared solid ([GlassSheet.solid]): no backdrop filter.
  solid,

  /// The glass blurred live whatever its height (the rule held off by a
  /// screen too tall to cross): what a tall sheet cost before the rule.
  frosted,
}

/// The same sheet body on each surface: the interleaved A/B that isolates
/// what the glass itself costs. A [tall] body is a scrollable page most of
/// the screen high (the games sheet, My Space add, sign-in: 89%); the short
/// one is a menu of four rows.
Widget _abBody(
  BuildContext context, {
  required _Surface surface,
  bool tall = false,
}) {
  final colors = context.colors;
  final row = [
    for (var i = 0; i < (tall ? 14 : 4); i++)
      ListTile(
        title: Text('Sicilian Najdorf, English Attack $i'),
        subtitle: const Text('1. e4 c5 2. Nf3 d6 3. d4 cxd4'),
      ),
  ];
  final Widget rows = tall
      ? SizedBox(height: 760, child: ListView(children: row))
      : Column(mainAxisSize: MainAxisSize.min, children: row);
  return switch (surface) {
    _Surface.opaque => Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: rows,
    ),
    _Surface.glass => GlassSheet(radius: 20, tone: colors.surface, child: rows),
    _Surface.solid => GlassSheet(
      radius: 20,
      tone: colors.surface,
      solid: true,
      child: rows,
    ),
    _Surface.frosted => MediaQuery(
      data: MediaQuery.of(context).copyWith(size: const Size(393, 100000)),
      child: GlassSheet(radius: 20, tone: colors.surface, child: rows),
    ),
  };
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
  });

  for (final tall in [false, true]) {
    testWidgets('A/B: the same ${tall ? 'tall' : 'short'} sheet, opaque vs '
        'glass vs solid vs frosted, interleaved', (tester) async {
      sheetsPhone(tester);
      var surface = _Surface.opaque;
      await tester.pumpWidget(
        sheetsHost(
          opener: (context, ref) => surface == _Surface.opaque
              ? showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) =>
                      _abBody(context, surface: surface, tall: tall),
                )
              : showGlassModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) =>
                      _abBody(context, surface: surface, tall: tall),
                ),
        ),
      );
      await tester.pump();
      await sheetsPrecache(tester);
      final raster = {for (final s in _Surface.values) s: <double>[]};
      final height = <_Surface, double>{};
      final live = <_Surface, bool>{};
      final kinds = _Surface.values.length;
      for (var run = 0; run < kinds * 9; run++) {
        surface = _Surface.values[run % kinds];
        sheetsTapOpen(tester);
        await tester.pump();
        await sheetsSettle(tester);
        final filters = find.byType(BackdropFilter).evaluate();
        live[surface] = filters.any(
          (e) => (e.renderObject! as RenderBackdropFilter).enabled,
        );
        height[surface] = tester.getSize(find.byType(BottomSheet)).height;
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(sheetsCapture),
          );
          final r = Stopwatch()..start();
          final image = await boundary.toImage(pixelRatio: 3);
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          r.stop();
          image.dispose();
          raster[surface]!.add(r.elapsedMicroseconds / 1000);
        });
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await sheetsSettle(tester);
      }
      // The first of each is the cold one (the grain tile, first layouts).
      String line(_Surface s) =>
          '${s.name} ${_ms(_median(raster[s]!.skip(1).toList()))}'
          '${live[s]! ? ' (live blur)' : ''}';
      // ignore: avoid_print
      print(
        'PERF A/B ${tall ? 'tall' : 'short'} '
        '(${height[_Surface.glass]!.toStringAsFixed(0)} pt): raster of the '
        'open sheet median: ${_Surface.values.map(line).join(' | ')}',
      );
      // The rule: short sheets frost, tall ones are solid; a declared solid
      // sheet never blurs.
      expect(live[_Surface.glass], !tall);
      expect(live[_Surface.solid], isFalse);
      expect(live[_Surface.frosted], isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final name in sheetScenes(shareImage: Uint8List(0)).map((s) => s.name)) {
    testWidgets('$name: open and close', (tester) async {
      sheetsPhone(tester);
      if (!shareImageReady) {
        shareImage = await sheetsSharePng(tester);
        shareImageReady = true;
      }
      final scene = sheetScenes(
        shareImage: shareImage,
      ).firstWhere((s) => s.name == name);
      await tester.pumpWidget(
        sheetsHost(opener: scene.opener, overrides: scene.overrides),
      );
      await tester.pump();
      await sheetsPrecache(tester);

      final openFrames = <double>[];
      final settleFrames = <int>[];
      final closeLatency = <double>[];
      final backdropReport = <String>{};
      var fullScreenBlur = false;
      var animatedBlur = false;
      var maxBackdrops = 0;
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final rasterRuns = <double>[];

      for (var run = 0; run < _runs; run++) {
        final watch = Stopwatch()..start();
        sheetsTapOpen(tester);
        await tester.pump();
        watch.stop();
        openFrames.add(watch.elapsedMicroseconds / 1000);
        final opened = sheetsLastOpen;

        // Every frame of the open: what blurs, how big, and whether the
        // blur itself is animated.
        final sigmas = <String>{};
        var frames = 0;
        while (tester.binding.hasScheduledFrame && frames < 600) {
          final backdrops = _backdrops(tester);
          if (backdrops.length > maxBackdrops) maxBackdrops = backdrops.length;
          for (final (filter, size) in backdrops) {
            sigmas.add(filter);
            if (size.width >= screen.width && size.height >= screen.height) {
              fullScreenBlur = true;
            }
            backdropReport.add(
              '${size.width.toStringAsFixed(0)}x'
              '${size.height.toStringAsFixed(0)} $filter',
            );
          }
          if (run == 0 && frames == 3) {
            // Raster proxy: rasterize this in-flight frame the way the GPU
            // would on every frame of the open.
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(sheetsCapture),
              );
              for (var i = 0; i < 3; i++) {
                final raster = Stopwatch()..start();
                final image = await boundary.toImage(pixelRatio: 3);
                await image.toByteData(format: ui.ImageByteFormat.rawRgba);
                raster.stop();
                image.dispose();
                rasterRuns.add(raster.elapsedMicroseconds / 1000);
              }
            });
          }
          await tester.pump(const Duration(milliseconds: 16));
          frames++;
        }
        if (sigmas.length > 1) animatedBlur = true;
        settleFrames.add(frames);
        expect(tester.takeException(), isNull);

        // Close the way a reader does: a tap on the dimmed page above it.
        var closedAt = -1.0;
        var elapsed = 0.0;
        if (opened is Future) {
          unawaited(opened.then((_) => closedAt = elapsed));
        }
        await tester.tapAt(const Offset(196, 8));
        await tester.pump();
        while (closedAt < 0 && elapsed < 2000) {
          await tester.pump(const Duration(milliseconds: 8));
          elapsed += 8;
        }
        closeLatency.add(closedAt < 0 ? double.nan : closedAt);
        await sheetsSettle(tester);
        // A sheet the page above cannot dismiss (it fills the screen) is
        // closed by its route, so runs never stack sheets.
        final left = find.byType(BottomSheet).evaluate().toList();
        if (left.isNotEmpty) {
          Navigator.of(left.last).pop();
          await sheetsSettle(tester);
        }
        expect(tester.takeException(), isNull);
      }

      // ignore: avoid_print
      print(
        'PERF $name: tap frame median ${_ms(_median(openFrames))} '
        '(runs ${openFrames.map(_ms).join(', ')}) | frames until idle '
        '${settleFrames.join(', ')} | raster of an in-flight frame median '
        '${rasterRuns.isEmpty ? 'n/a' : _ms(_median(rasterRuns))} | close tap -> result '
        '${closeLatency.map((v) => v.isNaN ? 'n/a' : '${v.toStringAsFixed(0)} ms').join(', ')} '
        '| max backdrops $maxBackdrops, full-screen $fullScreenBlur, '
        'animated sigma $animatedBlur | ${backdropReport.join('; ')}',
      );
    });
  }
}
