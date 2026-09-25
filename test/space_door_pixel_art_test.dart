import 'dart:io';

import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_flame.dart';
import 'package:chessever2/screens/my_space/widgets/space_door.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Door labels are measured in Inter; the test font's square glyphs are far
/// wider and would wrap words the app never wraps.
Future<void> _loadInter() async {
  final loader = FontLoader('InterDisplay');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final bytes = File('assets/fonts/Inter-$weight.otf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void _expectRectangular(List<String> bitmap, String name) {
  expect(bitmap, isNotEmpty, reason: '$name has no rows');
  final width = bitmap.first.length;
  expect(width, greaterThan(0), reason: '$name has empty rows');
  for (var r = 0; r < bitmap.length; r++) {
    expect(bitmap[r].length, width, reason: '$name row $r is ragged');
  }
  final filled = bitmap.join().replaceAll('.', '').length;
  expect(filled, greaterThan(0), reason: '$name has no blocks');
}

void main() {
  test('every door bitmap is rectangular and styles every block', () {
    for (final section in SpaceSection.values) {
      final art = PixelArt.door(section);
      _expectRectangular(art.bitmap, section.name);
      expect(art.cols, art.bitmap.first.length);
      expect(art.rows, art.bitmap.length);
      expect(
        art.cells.length,
        art.bitmap.join().replaceAll('.', '').length,
        reason: '${section.name}: one cell per block',
      );
      for (final c in art.cells) {
        expect(art.bitmap[c.row][c.col], isNot('.'));
        expect(c.opacity, inInclusiveRange(0, 1));
        expect(c.phase, inInclusiveRange(0, 1));
        expect(c.period, lessThanOrEqualTo(8), reason: 'texture caps at 8 s');
      }
      expect(art.embers.length, lessThanOrEqualTo(5));
    }
  });

  test('flame bitmap is rectangular at every heat level', () {
    _expectRectangular(kFlameBitmap, 'flame');
    for (final streak in [0, 4, 5, 10, 20, 99]) {
      final art = PixelArt.flame(streak);
      expect(art.cells.length, kFlameBitmap.join().replaceAll('.', '').length);
      final sparks = streak >= 20 ? 3 : (streak >= 10 ? 2 : 0);
      expect(art.embers.length, sparks, reason: 'streak $streak');
    }
  });

  test('seeded jitter matches the design source', () {
    final likes = PixelRandom.forKey('likes');
    expect(likes.next(), closeTo(0.3225115581881255, 1e-12));
    expect(likes.next(), closeTo(0.2340966542251408, 1e-12));
    expect(likes.next(), closeTo(0.7497301159892231, 1e-12));
    final flame = PixelRandom(11 * 7 + 3);
    expect(flame.next(), closeTo(0.7848348836414516, 1e-12));

    List<double> firstOpacities(SpaceSection s) =>
        PixelArt.door(s).cells.take(4).map((c) => c.opacity).toList();
    expect(firstOpacities(SpaceSection.library), [0.22, 0.27, 0.25, 0.27]);
    expect(firstOpacities(SpaceSection.likes), [0.66, 0.62, 0.87, 0.8]);
    expect(firstOpacities(SpaceSection.smartEvents), [0.78, 0.46, 0.63, 0.42]);
    expect(firstOpacities(SpaceSection.links), [0.52, 0.47, 0.74, 0.55]);
  });

  test('door layout places the same number of blocks as the design', () {
    // Total rects the HTML draws: blocks + embers + 5 per sparkle.
    const narrow = {
      SpaceSection.library: 130,
      SpaceSection.players: 101,
      SpaceSection.events: 78,
      SpaceSection.likes: 93,
      // The design draws 72: its one sparkle hangs off the tile's left edge,
      // so it is dropped here.
      SpaceSection.openings: 67,
      SpaceSection.games: 97,
      SpaceSection.smartEvents: 61,
      SpaceSection.links: 67,
    };
    const wide = {
      SpaceSection.library: 125,
      SpaceSection.players: 96,
      SpaceSection.events: 73,
      SpaceSection.likes: 88,
      SpaceSection.openings: 77,
      SpaceSection.games: 92,
      SpaceSection.smartEvents: 61,
      SpaceSection.links: 67,
    };
    int count(PixelScene s) =>
        s.art.cells.length + s.embers.length + s.sparkles.length * 5;
    for (final section in SpaceSection.values) {
      final art = PixelArt.door(section);
      for (final size in const [Size(120, 209), Size(358, 209)]) {
        final scene = PixelScene.door(art, size);
        final expected = size.width > 200 ? wide : narrow;
        expect(
          count(scene),
          expected[section],
          reason: '${section.name} at ${size.width}',
        );
        final tile = Offset.zero & size;
        for (final sp in scene.sparkles) {
          final plus = Rect.fromLTWH(
            sp.origin.dx - sp.block,
            sp.origin.dy - sp.block,
            sp.block * 3,
            sp.block * 3,
          );
          expect(
            tile.deflate(2).contains(plus.topLeft) &&
                tile.deflate(2).contains(plus.bottomRight - const Offset(1, 1)),
            isTrue,
            reason: '${section.name} sparkle clipped by the tile',
          );
        }
      }
    }
  });

  test('data texture marks exactly the filled cells', () {
    final art = PixelArt.door(SpaceSection.openings);
    final bytes = art.encodeTexture();
    expect(bytes.length, art.textureWidth * art.textureHeight * 4);
    var present = 0;
    for (var y = 0; y < art.rows; y++) {
      for (var x = 0; x < art.textureWidth; x++) {
        if (bytes[(y * art.textureWidth + x) * 4 + 3] == 255) present++;
      }
    }
    expect(present, art.cells.length);
  });

  test('only paper fire writes a flicker dip into the texture', () {
    int dipByte(PixelArt art, PixelCell c) =>
        art.encodeTexture()[((art.rows * 2 + c.row) * art.textureWidth +
                    c.col) *
                4 +
            1];
    // The streak flame is the fire My Space still draws.
    final dark = PixelArt.flame(20);
    final light = PixelArt.flame(20, tone: PixelTone.light);
    expect(dark.cells.map((c) => dipByte(dark, c)).toSet(), {0});
    expect(light.cells.map((c) => dipByte(light, c)).toSet(), {51});
  });

  testWidgets('doors and flames render with the static fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (final section in SpaceSection.values)
                SpaceDoor(section: section, locked: section.index.isEven),
              const SpaceDoor(section: SpaceSection.library, width: 358),
              const PixelFlame(streak: 21),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Add to Library'), findsWidgets);
  });

  test('the light tone inks the same shapes, under its own texture id', () {
    for (final section in SpaceSection.values) {
      final dark = PixelArt.door(section);
      final light = PixelArt.door(section, tone: PixelTone.light);
      // The dark art is the design: its id (and shared texture) is unchanged.
      expect(dark.id, isNot(endsWith(':light')));
      expect(light.id, '${dark.id}:light');
      expect(light.cells.length, dark.cells.length, reason: section.name);
      for (var i = 0; i < dark.cells.length; i++) {
        final d = dark.cells[i], l = light.cells[i];
        expect([l.col, l.row, l.fx], [d.col, d.row, d.fx]);
        expect(l.opacity, d.opacity);
        expect(l.phase, d.phase);
        expect(l.period, d.period);
      }
      expect(dark.sparkles, isTrue);
      // The shader paints sparkles in fixed white and cyan; none on paper.
      expect(light.sparkles, isFalse);
      expect(identical(PixelArt.door(section), dark), isTrue);
    }
    expect(PixelArt.flame(12).id, 'flame:12');
    expect(PixelArt.flame(12, tone: PixelTone.light).id, 'flame:12:light');
  });

  test('light art clears 3:1 on the light tile and page where it carries '
      'the shape', () {
    final light = AppColors.light;
    final p = PixelPalette.light;
    for (final c in [
      p.square,
      p.squareAlt,
      p.accent,
      p.red,
      p.redBright,
      p.handle,
      p.handleAlt,
      p.fireOuter,
      p.fireOuterCool,
      p.fireMid,
      p.fireCore,
      p.spark,
    ]) {
      expect(
        wcagContrast(c, light.surface),
        greaterThanOrEqualTo(3),
        reason: '$c on the tile',
      );
    }
    // Every block of the paper flame holds 3:1 on the page and the surfaces
    // even at the bottom of its flicker.
    for (final streak in [0, 5, 20]) {
      for (final c in PixelArt.flame(streak, tone: PixelTone.light).cells) {
        expect(c.dip, p.flickerDip);
        final dimmest = c.opacity * (1 - c.dip!);
        for (final ground in [light.background, light.surface]) {
          expect(
            wcagContrast(c.color.withValues(alpha: dimmest), ground),
            greaterThanOrEqualTo(3),
            reason: 'streak $streak ${c.color} at $dimmest',
          );
        }
      }
    }
    // The dark flame keeps the design's own flicker, byte for byte.
    expect(PixelArt.flame(20).cells.every((c) => c.dip == null), isTrue);
    expect(PixelArt.flame(20).cells.first.opacity, 0.85);
    // The dark palette is untouched.
    expect(PixelPalette.dark.square, const Color(0xFFDEE3E6));
    expect(PixelPalette.dark.accent, const Color(0xFF0FB4E5));
  });

  testWidgets('a door follows the theme: ink on paper, white on the plate', (
    tester,
  ) async {
    Future<Color?> labelColor(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: SpaceDoor(section: SpaceSection.players)),
        ),
      );
      // Let the theme change finish animating.
      await tester.pump(const Duration(seconds: 1));
      return tester
          .widget<Text>(find.text(SpaceSection.players.doorLabel))
          .style
          ?.color;
    }

    final onPaper = await labelColor(AppTheme.lightTheme);
    expect(onPaper, AppColors.light.textPrimary);
    expect(
      wcagContrast(onPaper!, AppColors.light.surface),
      greaterThanOrEqualTo(4.5),
    );
    final onPlate = await labelColor(AppTheme.darkTheme);
    expect(onPlate, Colors.white);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('door label at large text', () {
    setUpAll(_loadInter);

    // A 360dp phone's door, at the default and the 1.3x cap (2x clamps).
    testWidgets('wraps whole and ends the art 8px above it', (tester) async {
      for (final scale in [1.0, 1.3, 2.0]) {
        for (final width in [109.0, 120.0]) {
          for (final section in SpaceSection.values) {
            await tester.pumpWidget(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SpaceDoor(
                      section: section,
                      width: width,
                      height: 191,
                    ),
                  ),
                ),
              ),
            );
            final why = '${section.name} at ${width}px, ${scale}x';
            final label = find.text(section.doorLabel);
            expect(
              tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
              isFalse,
              reason: '$why: label truncated',
            );
            final view = find.byType(PixelArtView);
            final art = tester
                .widget<PixelArtView>(view)
                .scene
                .artRect
                .shift(tester.getTopLeft(view));
            expect(
              tester.getRect(label).top - art.bottom,
              greaterThanOrEqualTo(8),
              reason: '$why: art runs into the label',
            );
          }
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
