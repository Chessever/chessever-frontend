import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:chessever2/board_scan/board_scan_crop.dart';
import 'package:chessever2/board_scan/board_scan_image.dart';

void main() {
  testWidgets(
    'crop handles remain visible and accept a real drag inside a phone-width frame',
    (tester) async {
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 400, height: 400)),
      );
      var corners = List<Offset>.of(initialBoardScanCorners);
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: BoardScanCrop(
                image: BoardScanImage(bytes, 400, 400),
                corners: corners,
                onChanged: (value) => corners = value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (var i = 1; i <= 4; i++) {
        expect(find.text('$i'), findsOneWidget);
      }
      final first = tester.getCenter(find.text('1'));
      expect(first.dx, greaterThan(24));
      expect(first.dy, greaterThan(24));
      await tester.drag(find.text('1'), const Offset(30, 30));
      expect(corners.first.dx, greaterThan(.06));
      expect(corners.first.dy, greaterThan(.06));
      expect(corners[1], initialBoardScanCorners[1]);
    },
  );
}
