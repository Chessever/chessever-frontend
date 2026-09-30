import 'dart:ui' as ui;

import 'package:chessever2/screens/feed/race/race_widgets.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// Puzzle Race's Feed header mark: a knight at full gallop, which must
/// parse, draw at the header's sizes, and stay whole inside its box. The
/// header draws it as [RaceGlyphs.rush] (pinned in home_top_bar_parity_test).
void main() {
  testWidgets('the race mark parses as a 24-unit picture', (tester) async {
    final info = await tester.runAsync(
      () => vg.loadPicture(SvgStringLoader(RaceGlyphs.rush), null),
    );
    expect(info, isNotNull);
    expect(info!.size, const Size(24, 24));
    info.picture.dispose();
  });

  // 22dp is what the Feed header draws; 20 and 24 bracket it.
  for (final size in const [20.0, 22.0, 24.0]) {
    testWidgets('the race mark draws whole and tinted at ${size.toInt()}dp', (
      tester,
    ) async {
      final rush = await _ink(tester, RaceGlyphs.rush, size);
      final soundOn = await _ink(tester, FeedGlyphs.soundOn, size);
      final soundOff = await _ink(tester, FeedGlyphs.soundOff, size);

      // The knight sits beside the speaker in the header, so it carries
      // about the same ink: no lighter than the muted speaker, and at most
      // 35% heavier than the sounding one (a closed outline with an eye
      // runs a little denser than a cone and two arcs; it measures about
      // 1.2x). A sliver or a filled blob fails one bound or the other.
      expect(rush.inked, greaterThanOrEqualTo(soundOff.inked));
      expect(rush.inked / soundOn.inked, lessThanOrEqualTo(1.35));
      // Nothing is shaved off by the box's edge.
      expect(rush.onEdge, 0);
      // Every solid pixel takes the header's ink.
      expect(rush.offTint, 0);
    });
  }
}

const _tint = Color(0xFF0B6E4F);

/// Draws [glyph] at [size] in [_tint] and counts its solid pixels at 3x.
Future<({int inked, int onEdge, int offTint})> _ink(
  WidgetTester tester,
  String glyph,
  double size,
) async {
  final boundary = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: boundary,
          child: FeedGlyph(glyph, width: size, height: size, color: _tint),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  expect(find.byType(SvgPicture), findsOneWidget);
  expect(tester.getSize(find.byType(SvgPicture)), Size(size, size));

  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final pixels = await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width;
    image.dispose();
    return (data!, width);
  });
  final (data, width) = pixels!;
  final height = data.lengthInBytes ~/ (4 * width);

  var inked = 0;
  var onEdge = 0;
  var offTint = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final alpha = data.getUint8(i + 3);
      if (alpha < 200) continue;
      inked++;
      if (x == 0 || y == 0 || x == width - 1 || y == height - 1) onEdge++;
      // Raw bytes are premultiplied, so only opaque pixels show the ink.
      if (alpha < 255) continue;
      final r = data.getUint8(i);
      final g = data.getUint8(i + 1);
      final b = data.getUint8(i + 2);
      if ((r - 0x0B).abs() > 3 ||
          (g - 0x6E).abs() > 3 ||
          (b - 0x4F).abs() > 3) {
        offTint++;
      }
    }
  }
  return (inked: inked, onEdge: onEdge, offTint: offTint);
}
