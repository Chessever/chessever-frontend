import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chessever2/repository/library/collection_cover.dart';
import 'package:chessever2/screens/library/cover_cropper.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// A PNG photo of [width]×[height]: left half red, right half blue.
Future<Uint8List> _photo(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawRect(
      Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
      Paint()..color = const Color(0xFFFF0000),
    )
    ..drawRect(
      Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
      Paint()..color = const Color(0xFF0000FF),
    );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<(Size, Color)> _decode(Uint8List png, {required Offset at}) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = ((at.dy.round() * image.width) + at.dx.round()) * 4;
  final colour = Color.fromARGB(
    raw.getUint8(i + 3),
    raw.getUint8(i),
    raw.getUint8(i + 1),
    raw.getUint8(i + 2),
  );
  return (Size(image.width.toDouble(), image.height.toDouble()), colour);
}

void main() {
  test('a photo too small for a 2:3 cover of 600×900 is refused early', () {
    expect(collectionCoverFits(const Size(600, 900)), isTrue);
    expect(collectionCoverFits(const Size(1600, 800)), isFalse); // 533 wide
    expect(collectionCoverFits(const Size(599, 2000)), isFalse);
  });

  testWidgets('the cover is rendered at 800×1200 from the framed window', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final photo = await _photo(1800, 1200);
      // Frame the right-hand (blue) part of a landscape photo.
      final cover = await prepareCollectionCover(
        photo,
        crop: const Rect.fromLTWH(0.6, 0, 0.4444, 1),
      );
      final (size, colour) = await _decode(cover, at: const Offset(400, 600));
      expect(size, const Size(800, 1200));
      expect(colour, const Color(0xFF0000FF));
      // No frame given: the centred window straddles both halves.
      final centred = await prepareCollectionCover(photo);
      final (_, left) = await _decode(centred, at: const Offset(100, 600));
      final (_, right) = await _decode(centred, at: const Offset(700, 600));
      expect(left, const Color(0xFFFF0000));
      expect(right, const Color(0xFF0000FF));
    });
  });

  testWidgets('the cropper starts centred and returns the framed window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Rect? framed;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return TextButton(
              onPressed: () async =>
                  framed = await Navigator.of(context).push<Rect>(
                    MaterialPageRoute(
                      builder: (_) => CoverCropper(
                        bytes: _onePixelPng,
                        photoSize: const Size(1800, 1200),
                      ),
                    ),
                  ),
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Frame your cover'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cover_crop_use')));
    await tester.pumpAndSettle();
    // Landscape 3:2 photo: the full-height 2:3 window, centred.
    expect(framed!.top, closeTo(0, 1e-6));
    expect(framed!.height, closeTo(1, 1e-6));
    expect(framed!.width, closeTo(800 / 1800, 1e-6));
    expect(framed!.left, closeTo((1 - 800 / 1800) / 2, 1e-6));
  });

  testWidgets('Cancel returns nothing', (tester) async {
    Rect? framed = Rect.zero;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return TextButton(
              onPressed: () async =>
                  framed = await Navigator.of(context).push<Rect>(
                    MaterialPageRoute(
                      builder: (_) => CoverCropper(
                        bytes: _onePixelPng,
                        photoSize: const Size(1200, 1800),
                      ),
                    ),
                  ),
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(framed, isNull);
  });
}
