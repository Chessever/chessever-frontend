// What a short frosted sheet's glass actually reads as over the busiest page
// (live boards), in light and dark: the plate's darkest and lightest 2x2 pt
// cells, whether the light glass keeps the brand mint (its green-over-red
// lead, the surface's own tint) or sinks to a neutral grey, and the AA
// contrast of the sheet's inks on it.
//
//   flutter test --no-pub test/sheet_glass_tint_probe_test.dart
//
// Prints one `TINT` line per sheet height and theme. The heights are the
// frosted sheets (under the frost rule's share of the screen, the ones that
// keep the live blur), up to a 500 pt one, just under the rule's 60% of a
// phone; the last case is a solid sheet, which must be the tone itself.
import 'dart:ui' as ui;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessever2/widgets/smooth_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sheets_harness.dart';

/// Green over red, in 0-255: the mint's lead (the light surface #F4FAF9
/// leads by 6). A neutral grey leads by 0 or 1.
int _mintLead(Color c) => (c.g * 255).round() - (c.r * 255).round();

String _rgb(Color c) =>
    '(${(c.r * 255).round()},${(c.g * 255).round()},${(c.b * 255).round()})';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final light in [true, false]) {
    final theme = light ? 'light' : 'dark';
    // The sheet glass at three heights, and a card floating in a sheet
    // route (add to library, a knockout match, puzzle difficulty).
    for (final (height, card) in [
      (300.0, false),
      (420.0, false),
      (500.0, false),
      (300.0, true),
    ]) {
      final kind = card ? 'floating card' : 'short frosted sheet';
      testWidgets('$kind ${height.round()} pt, $theme', (tester) async {
        sheetsPhone(tester);
        await tester.pumpWidget(
          sheetsHost(
            light: light,
            opener: (context, ref) => showGlassModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (context) => card
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      child: PopupGlass(
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(height: height, width: double.infinity),
                      ),
                    )
                  : GlassSheet(
                      radius: 20,
                      tone: context.colors.surface,
                      child: SizedBox(height: height, width: double.infinity),
                    ),
            ),
          ),
        );
        await tester.pump();
        await sheetsPrecache(tester);
        sheetsTapOpen(tester);
        await tester.pump();
        await sheetsSettle(tester);

        // The probe is about the frosted glass: a short sheet must blur.
        final filters = tester
            .renderObjectList<RenderBackdropFilter>(find.byType(BackdropFilter))
            .toList();
        expect(filters, hasLength(1));
        expect(filters.single.enabled, isTrue);

        final panel = tester.getRect(find.byType(PopupGlass));
        final cells = <Color>[];
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(sheetsCapture),
          );
          final image = await boundary.toImage(pixelRatio: 3);
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          // Inside the sheet, under the top sheen, clear of the rim (and of
          // a card's rounded corners), on screen.
          final clear = card ? 24.0 : 4.0;
          final inside = Rect.fromLTRB(
            panel.left.clamp(0, sheetsScreen.width) + clear,
            panel.top + PopupGlassStyle.sheenDepth,
            panel.right.clamp(0, sheetsScreen.width) - clear,
            panel.bottom.clamp(0, sheetsScreen.height) - clear,
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
        final leads = cells.map(_mintLead).toList()..sort();
        final worstText = [
          for (final ink in [colors.textPrimary, colors.textSecondary])
            for (final plate in [darkest, lightest]) wcagContrast(ink, plate),
        ].reduce((a, b) => a < b ? a : b);

        // ignore: avoid_print
        print(
          'TINT $theme ${card ? 'card ' : ''}${height.round()}pt: tone ${_rgb(colors.surface)} '
          '(lead ${_mintLead(colors.surface)}) | plate ${_rgb(darkest)}..'
          '${_rgb(lightest)} | mint lead min ${leads.first} '
          'median ${leads[leads.length ~/ 2]} max ${leads.last} | '
          'worst text ${worstText.toStringAsFixed(2)}:1',
        );
        expect(worstText, greaterThanOrEqualTo(4.5));
        if (light) {
          // The light glass keeps the brand's paper everywhere on it: no
          // cell falls to a neutral grey (a lead of 0 or 1), the typical
          // cell keeps the paper's own lead, and the darkest board behind
          // pulls it under ten levels down (the popups' 86% plate let it
          // sink 21, to a grey cast).
          expect(leads.first, greaterThanOrEqualTo(4));
          expect(
            leads[leads.length ~/ 2],
            greaterThanOrEqualTo(_mintLead(colors.surface) - 1),
          );
          final drop = (colors.surface.g - darkest.g) * 255;
          expect(drop, lessThan(10), reason: 'darkest ${_rgb(darkest)}');
        }
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await sheetsSettle(tester);
      });
    }

    testWidgets('a solid sheet is its own tone, opaque, $theme', (
      tester,
    ) async {
      sheetsPhone(tester);
      await tester.pumpWidget(
        sheetsHost(
          light: light,
          opener: (context, ref) => showGlassModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (context) => GlassSheet(
              radius: 20,
              tone: context.colors.surface,
              solid: true,
              child: const SizedBox(height: 480, width: double.infinity),
            ),
          ),
        ),
      );
      await tester.pump();
      await sheetsPrecache(tester);
      sheetsTapOpen(tester);
      await tester.pump();
      await sheetsSettle(tester);
      // No backdrop filter at all: nothing is blurred on any frame.
      expect(find.byType(BackdropFilter), findsNothing);
      final panel = tester.getRect(find.byType(PopupGlass));
      final colors = tester.element(find.byType(PopupGlass)).colors;
      var worst = 0.0;
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(sheetsCapture),
        );
        final image = await boundary.toImage(pixelRatio: 3);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        const cell = 6;
        for (
          var y = ((panel.top + PopupGlassStyle.sheenDepth) * 3).ceil();
          y + cell <= (sheetsScreen.height - 4) * 3;
          y += cell
        ) {
          for (
            var x = 12;
            x + cell <= (sheetsScreen.width - 4) * 3;
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
            for (final (got, want) in [
              (r / n, colors.surface.r * 255),
              (g / n, colors.surface.g * 255),
              (b / n, colors.surface.b * 255),
            ]) {
              final off = (got - want).abs();
              if (off > worst) worst = off;
            }
          }
        }
        image.dispose();
      });
      // ignore: avoid_print
      print(
        'TINT $theme solid: tone ${_rgb(colors.surface)} | worst cell off '
        'by ${worst.toStringAsFixed(1)} levels (grain only)',
      );
      // The page never shows through: every cell is the tone, give or take
      // the grain.
      expect(worst, lessThan(4));
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await sheetsSettle(tester);
    });
  }
}
