import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class BoardScanImage {
  const BoardScanImage(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

Future<BoardScanImage> prepareBoardScanImage(Uint8List bytes) =>
    compute(_prepare, bytes);

BoardScanImage _prepare(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('Choose an image smaller than 20 MB.');
  }
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > 32000000) {
    throw const FormatException(
      'Choose a JPEG, PNG or WebP image up to 32 megapixels.',
    );
  }
  final frame = decoder!.decodeFrame(0);
  if (frame == null) {
    throw const FormatException('This image could not be read.');
  }
  var image = img.bakeOrientation(frame);
  if (math.max(image.width, image.height) > 2048) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 2048 : null,
      height: image.height > image.width ? 2048 : null,
      interpolation: img.Interpolation.linear,
    );
  }
  return BoardScanImage(
    Uint8List.fromList(img.encodeJpg(image, quality: 90)),
    image.width,
    image.height,
  );
}

/// Convex clockwise corners, in the image's normalized coordinate system.
bool validBoardScanCorners(List<Offset> points) {
  if (points.length != 4 ||
      points.any(
        (p) =>
            !p.dx.isFinite ||
            !p.dy.isFinite ||
            p.dx < 0 ||
            p.dy < 0 ||
            p.dx > 1 ||
            p.dy > 1,
      )) {
    return false;
  }
  var area = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = points[i], b = points[(i + 1) % 4], c = points[(i + 2) % 4];
    if ((b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx) <=
        0.0001) {
      return false;
    }
    area += a.dx * b.dy - b.dx * a.dy;
  }
  return area / 2 > 0.025;
}

/// Maps a unit square into a perspective quadrilateral. Bilinear warping would
/// shift the inner ranks on angled photos, so solve the actual homography.
List<double> boardScanHomography(List<Offset> corners) {
  if (!validBoardScanCorners(corners)) {
    throw const FormatException(
      'Keep all four corners in order around the board.',
    );
  }
  final source = [
    Offset.zero,
    const Offset(1, 0),
    const Offset(1, 1),
    const Offset(0, 1),
  ];
  final a = <List<double>>[];
  for (var i = 0; i < 4; i++) {
    final x = source[i].dx,
        y = source[i].dy,
        u = corners[i].dx,
        v = corners[i].dy;
    a.add([x, y, 1, 0, 0, 0, -u * x, -u * y, u]);
    a.add([0, 0, 0, x, y, 1, -v * x, -v * y, v]);
  }
  for (var i = 0; i < 8; i++) {
    var pivot = i;
    for (var r = i + 1; r < 8; r++) {
      if (a[r][i].abs() > a[pivot][i].abs()) pivot = r;
    }
    final swap = a[i];
    a[i] = a[pivot];
    a[pivot] = swap;
    final scale = a[i][i];
    if (scale.abs() < 1e-10) {
      throw const FormatException('Align the four corners with the board.');
    }
    a[i] = a[i].map((v) => v / scale).toList();
    for (var r = 0; r < 8; r++) {
      if (r == i) continue;
      final factor = a[r][i];
      for (var c = 0; c < 9; c++) {
        a[r][c] -= factor * a[i][c];
      }
    }
  }
  return [for (var i = 0; i < 8; i++) a[i][8]];
}

Offset boardScanProject(List<double> h, double x, double y) {
  final z = h[6] * x + h[7] * y + 1;
  return Offset(
    (h[0] * x + h[1] * y + h[2]) / z,
    (h[3] * x + h[4] * y + h[5]) / z,
  );
}

Future<List<Map<String, String>>> boardScanQuadrants(
  BoardScanImage image,
  List<Offset> corners, {
  required bool photo,
}) {
  return compute(_quadrants, (image.bytes, corners, photo));
}

List<Map<String, String>> _quadrants((Uint8List, List<Offset>, bool) input) {
  final image = img.decodeJpg(input.$1)!;
  final h = boardScanHomography(input.$2);
  final rectified = img.Image(width: 1600, height: 1600);
  for (var y = 0; y < 1600; y++) {
    for (var x = 0; x < 1600; x++) {
      final p = boardScanProject(h, x / 1600, y / 1600);
      rectified.setPixel(
        x,
        y,
        image.getPixelInterpolate(
          p.dx * (image.width - 1),
          p.dy * (image.height - 1),
          interpolation: img.Interpolation.linear,
        ),
      );
    }
  }
  final result = <Map<String, String>>[];
  for (var r = 0; r < 2; r++) {
    for (var c = 0; c < 2; c++) {
      final crop = img.copyCrop(
        rectified,
        x: c * 800,
        y: r * 800,
        width: 800,
        height: 800,
      );
      final tile = img.copyResize(
        crop,
        width: 1024,
        height: 1024,
        interpolation: img.Interpolation.linear,
      );
      result.add({
        'image':
            'data:image/jpeg;base64,${base64Encode(img.encodeJpg(tile, quality: 90))}',
      });
    }
  }
  return result;
}

/// The original view retains file/rank labels for automatic camera alignment.
Future<Map<String, dynamic>> boardScanSource(
  BoardScanImage image,
  List<Offset> corners,
) => compute(_source, (image.bytes, corners));

Map<String, dynamic> _source((Uint8List, List<Offset>) input) {
  var image = img.decodeJpg(input.$1)!;
  if (math.max(image.width, image.height) > 1024) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 1024 : null,
      height: image.height > image.width ? 1024 : null,
      interpolation: img.Interpolation.linear,
    );
  }
  final width = image.width, height = image.height;
  final edge = input.$2[1] - input.$2[0];
  final angle = -math.atan2(edge.dy * height, edge.dx * width);
  final ca = math.cos(angle), sa = math.sin(angle);
  final expandedWidth = (width * ca).abs() + (height * sa).abs();
  final expandedHeight = (width * sa).abs() + (height * ca).abs();
  image.backgroundColor = img.ColorRgb8(255, 255, 255);
  image = img.copyRotate(
    image,
    angle: angle * 180 / math.pi,
    interpolation: img.Interpolation.linear,
  );
  final rotatedWidth = image.width, rotatedHeight = image.height;
  final corners = [
    for (final p in input.$2)
      {
        'x':
            (((p.dx * width - width / 2) * ca -
                        (p.dy * height - height / 2) * sa +
                        expandedWidth / 2) /
                    rotatedWidth)
                .clamp(0.0, 1.0),
        'y':
            (((p.dx * width - width / 2) * sa +
                        (p.dy * height - height / 2) * ca +
                        expandedHeight / 2) /
                    rotatedHeight)
                .clamp(0.0, 1.0),
      },
  ];
  if (math.max(image.width, image.height) > 1024) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 1024 : null,
      height: image.height > image.width ? 1024 : null,
      interpolation: img.Interpolation.linear,
    );
  }
  return {
    'image':
        'data:image/jpeg;base64,${base64Encode(img.encodeJpg(image, quality: 85))}',
    'corners': corners,
  };
}
