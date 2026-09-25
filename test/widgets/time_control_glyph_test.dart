import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _originals = [
  PngAsset.rapidIcon,
  PngAsset.classicalIcon,
  PngAsset.blitzIcon,
];

const _twins = {
  PngAsset.rapidIcon: PngAsset.rapidIconLight,
  PngAsset.classicalIcon: PngAsset.classicalIconLight,
  PngAsset.blitzIcon: PngAsset.blitzIconLight,
};

/// Every mint surface a time-control glyph is drawn on in light mode.
final Map<String, Color> _paper = {
  'background': AppColors.light.background,
  'surface': AppColors.light.surface,
  'surfaceRecessed': AppColors.light.surfaceRecessed,
};

Future<void> _pump(
  WidgetTester tester,
  Widget glyph, {
  required ThemeData theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: glyph)),
    ),
  );
}

String _drawnAsset(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image));
  return (image.image as AssetImage).assetName;
}

/// Decoded RGBA pixels of a PNG on disk.
Future<(Uint8List, int)> _pixels(WidgetTester tester, String path) async {
  final result = await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    return (data!.buffer.asUint8List(), frame.image.width);
  });
  return result!;
}

/// Share of the glyph's fully opaque pixels that clear the 3:1 non-text
/// floor on [ground]. The coin, the bolt: the body of the mark.
Future<double> _legibleShare(
  WidgetTester tester,
  String path,
  Color ground,
) async {
  final (rgba, _) = await _pixels(tester, path);
  var opaque = 0;
  var legible = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] != 255) continue;
    opaque++;
    final pixel = Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]);
    if (wcagContrast(pixel, ground) >= 3) legible++;
  }
  return legible / opaque;
}

void main() {
  group('TimeControlGlyph.resolve', () {
    test('light swaps each mark for its baked twin, dark keeps it', () {
      for (final asset in _originals) {
        expect(TimeControlGlyph.resolve(asset, light: true), _twins[asset]);
        expect(TimeControlGlyph.resolve(asset, light: false), asset);
      }
    });

    test('an unknown asset passes through in both themes', () {
      const other = 'assets/pngs/bK.png';
      expect(TimeControlGlyph.resolve(other, light: true), other);
      expect(TimeControlGlyph.resolve(other, light: false), other);
    });

    test('assetForLabel reads free-text time controls', () {
      expect(TimeControlGlyph.assetForLabel('Blitz 3+2'), PngAsset.blitzIcon);
      expect(TimeControlGlyph.assetForLabel('RAPID'), PngAsset.rapidIcon);
      expect(
        TimeControlGlyph.assetForLabel('Classical'),
        PngAsset.classicalIcon,
      );
      expect(
        TimeControlGlyph.assetForLabel('standard'),
        PngAsset.classicalIcon,
      );
      expect(TimeControlGlyph.assetForLabel('bullet'), isNull);
      expect(TimeControlGlyph.assetForLabel(null), isNull);
    });
  });

  group('TimeControlGlyph widget', () {
    testWidgets('light theme draws the paper twin', (tester) async {
      await _pump(
        tester,
        const TimeControlGlyph(PngAsset.rapidIcon, size: 16),
        theme: AppTheme.lightTheme,
      );
      expect(_drawnAsset(tester), PngAsset.rapidIconLight);
    });

    testWidgets('dark theme draws the original art', (tester) async {
      await _pump(
        tester,
        const TimeControlGlyph(PngAsset.rapidIcon, size: 16),
        theme: AppTheme.darkTheme,
      );
      expect(_drawnAsset(tester), PngAsset.rapidIcon);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.color, isNull);
      expect(image.colorBlendMode, isNull);
    });

    testWidgets('onDark keeps the original on a fixed-dark ground', (
      tester,
    ) async {
      await _pump(
        tester,
        const TimeControlGlyph(PngAsset.classicalIcon, size: 16, onDark: true),
        theme: AppTheme.lightTheme,
      );
      expect(_drawnAsset(tester), PngAsset.classicalIcon);
    });

    testWidgets('tint draws a srcIn silhouette', (tester) async {
      await _pump(
        tester,
        const TimeControlGlyph(
          PngAsset.blitzIcon,
          size: 16,
          tint: Color(0xFF123456),
        ),
        theme: AppTheme.lightTheme,
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.color, const Color(0xFF123456));
      expect(image.colorBlendMode, BlendMode.srcIn);
    });

    testWidgets('stays decorative unless labelled', (tester) async {
      await _pump(
        tester,
        const TimeControlGlyph(PngAsset.blitzIcon, size: 16),
        theme: AppTheme.lightTheme,
      );
      expect(
        tester.widget<Image>(find.byType(Image)).excludeFromSemantics,
        isTrue,
      );
    });
  });

  group('baked light twins', () {
    test('exist beside the originals at the same pixel size', () {
      for (final asset in _originals) {
        final twin = File(_twins[asset]!);
        expect(twin.existsSync(), isTrue, reason: '${twin.path} is missing');
        // PNG IHDR: width and height are big-endian at bytes 16..23.
        final a = File(asset).readAsBytesSync().sublist(16, 24);
        final b = twin.readAsBytesSync().sublist(16, 24);
        expect(b, a, reason: '${twin.path} must match $asset in size');
      }
    });

    testWidgets('twins clear 3:1 on every mint surface; originals did not', (
      tester,
    ) async {
      for (final asset in _originals) {
        for (final ground in _paper.entries) {
          final twin = await _legibleShare(
            tester,
            _twins[asset]!,
            ground.value,
          );
          expect(
            twin,
            greaterThanOrEqualTo(0.65),
            reason:
                '${_twins[asset]} on ${ground.key}: only '
                '${(twin * 100).round()}% of the mark clears 3:1',
          );
        }
        // The regression this fixes: on the page background the original
        // mark (the white rabbit coin above all) mostly vanished.
        final original = await _legibleShare(
          tester,
          asset,
          AppColors.light.background,
        );
        expect(original, lessThan(0.5), reason: '$asset on paper');
      }
    });
  });
}
