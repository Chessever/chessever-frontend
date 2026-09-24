import 'dart:io';

import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/my_space/defaults/space_defaults.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/space_metrics.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile_content.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Tile copy is measured in Inter; the test font's square glyphs are far
/// wider and would cut words the app never cuts.
Future<void> _loadInter() async {
  final loader = FontLoader('InterDisplay');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final bytes = File('assets/fonts/Inter-$weight.otf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// Every seeded default on its own plate, at [width] and [textScale].
Future<void> _pumpDefaults(
  WidgetTester tester, {
  required double width,
  required double textScale,
  required ThemeData theme,
}) async {
  tester.view.physicalSize = Size(width, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerPhotoProvider.overrideWith((ref, fideId) async => null),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              backgroundColor: context.colors.background,
              body: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in spaceSeedDrafts())
                      SizedBox(
                        width: d.kind.tileWidth,
                        height: SpaceMetrics.railHeight,
                        child: SpaceTileContent(shortcut: d),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text).first);

void main() {
  setUpAll(_loadInter);

  for (final width in [360.0, 390.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('every default reads whole at ${width.toInt()}pt, '
          '${scale}x text', (tester) async {
        await _pumpDefaults(
          tester,
          width: width,
          textScale: scale,
          theme: AppTheme.lightTheme,
        );
        final drafts = spaceSeedDrafts();
        for (final d in drafts) {
          final name = d.kind == SpaceShortcutKind.smartEvent
              ? d.title
              : d.params['openingName'] as String;
          final p = _paragraph(tester, name);
          expect(p.didExceedMaxLines, isFalse, reason: name);
          // Inter's tabular set widens hyphens: "Caro - Kann", "Bogo - Indian".
          expect(
            p.text.style!.fontFeatures ?? const <FontFeature>[],
            isNot(contains(const FontFeature.tabularFigures())),
            reason: name,
          );
          if (d.kind == SpaceShortcutKind.smartEvent) {
            final caption = _paragraph(tester, d.subtitle!);
            expect(caption.didExceedMaxLines, isFalse, reason: d.subtitle);
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final light in [true, false]) {
    testWidgets('default tiles clear AA in ${light ? 'light' : 'dark'} mode', (
      tester,
    ) async {
      await _pumpDefaults(
        tester,
        width: 390,
        textScale: 1,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      );
      final colors = light ? AppColors.light : AppColors.dark;
      // Opening tiles sit on the page; Smart Event tiles on their plate.
      final checks = <(String, Color)>[
        (kSpaceDefaultOpenings.first.tileName, colors.background),
        (kSpaceDefaultOpenings.first.eco, colors.background),
        ('After 4.Nf3', colors.background),
        ('GM Games', colors.surface),
      ];
      for (final (text, ground) in checks) {
        final style = _paragraph(tester, text).text.style!;
        final ink = Color.alphaBlend(style.color!, ground);
        final ratio = _contrast(ink, ground);
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '$text: $ratio');
      }
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
