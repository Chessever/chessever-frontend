import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A collection cover is the image shown on collection cards and at the top
/// of the collection page. It is NOT the profile photo: that one is the
/// author picture and has its own square pipeline in profile_avatar_editor.
///
/// Gamebase accepts JPEG/PNG/WebP covers that are a 2:3 portrait of at least
/// 600×900 and stores them as 800×1200. Preparing the exact output here keeps
/// the upload small and makes the preview identical to what gets published.
const collectionCoverWidth = 800;
const collectionCoverHeight = 1200;
const collectionCoverMinWidth = 600;
const collectionCoverMinHeight = 900;
const _maxSourceBytes = 25 * 1024 * 1024;

const _mediaChannel = MethodChannel('com.chessever/media_picker');

/// Mobile opens the system photo picker for one chosen photo; no camera or
/// library-wide permission is requested. Other platforms use the file picker.
/// Returns the untouched photo, or null when the user cancels; the cropper
/// then frames it and [prepareCollectionCover] renders the cover.
final collectionCoverSourceProvider = Provider<Future<Uint8List?> Function()>(
  (ref) => () async {
    final Uint8List? source;
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android)) {
      final Object? raw;
      try {
        // The permission-free single-photo picker. It shares the avatar's
        // method name but returns the untouched photo; the 2:3 cover
        // preparation below is separate from the avatar's square crop.
        raw = await _mediaChannel.invokeMethod<Object?>('pickProfileImage');
      } on PlatformException {
        throw const FormatException(
          'This photo could not be read. Choose another one.',
        );
      }
      if (raw == null) return null;
      final bytes = raw is Map ? raw['bytes'] : null;
      source = bytes is Uint8List && bytes.isNotEmpty ? bytes : null;
    } else {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null) return null;
      source = picked.files.single.bytes;
    }
    if (source == null) {
      throw const FormatException(
        'This photo could not be read. Choose another one.',
      );
    }
    if (source.length > _maxSourceBytes) {
      throw const FormatException('Choose a photo smaller than 25 MB.');
    }
    return source;
  },
);

/// Pixel size of an encoded photo, without decoding it.
Future<Size> collectionCoverSourceSize(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = Size(
      descriptor.width.toDouble(),
      descriptor.height.toDouble(),
    );
    descriptor.dispose();
    return size;
  } catch (_) {
    throw const FormatException(
      'This photo could not be read. Choose another one.',
    );
  } finally {
    buffer.dispose();
  }
}

/// Whether a photo of [size] can give a 2:3 cover of at least 600×900.
bool collectionCoverFits(Size size) =>
    math.min(size.width, size.height * 2 / 3) >= collectionCoverMinWidth;

/// Renders [bytes] as an exactly 800×1200 PNG cover. [crop] is the framed
/// window as fractions of the photo (0..1); omitted, the largest centred 2:3
/// window is used. Refuses a window smaller than 600×900 photo pixels rather
/// than upscaling it into a blurry cover.
Future<Uint8List> prepareCollectionCover(Uint8List bytes, {Rect? crop}) async {
  if (bytes.length > _maxSourceBytes) {
    throw const FormatException('Choose a photo smaller than 25 MB.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  late final ui.Codec codec;
  late final Rect window;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width, h = descriptor.height;
    if (w * h > 60000000) {
      throw const FormatException('Choose a photo with smaller dimensions.');
    }
    // The framed window in photo pixels, kept exactly 2:3 and inside the
    // photo; by default the largest centred one.
    final full = math.min(w.toDouble(), h * 2 / 3);
    final cropW = crop == null
        ? full
        : (crop.width * w).clamp(1.0, full).toDouble();
    final cropH = cropW * 3 / 2;
    final left = crop == null
        ? (w - cropW) / 2
        : (crop.left * w).clamp(0.0, w - cropW).toDouble();
    final top = crop == null
        ? (h - cropH) / 2
        : (crop.top * h).clamp(0.0, h - cropH).toDouble();
    if (cropW < collectionCoverMinWidth || cropH < collectionCoverMinHeight) {
      throw const FormatException(
        'This photo is too small for a cover. Use one at least 600 × 900 pixels.',
      );
    }
    // Decode only as large as the cover needs, to keep memory low.
    final factor = math.min(1.0, collectionCoverHeight / cropH);
    final dw = math.max(1, (w * factor).round());
    final dh = math.max(1, (h * factor).round());
    codec = await descriptor.instantiateCodec(
      targetWidth: dw,
      targetHeight: dh,
    );
    window = Rect.fromLTWH(
      left * dw / w,
      top * dh / h,
      cropW * dw / w,
      cropH * dh / h,
    );
  } catch (_) {
    descriptor?.dispose();
    rethrow;
  } finally {
    buffer.dispose();
  }
  try {
    final image = (await codec.getNextFrame()).image;
    try {
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..drawColor(Colors.white, BlendMode.src)
        ..drawImageRect(
          image,
          window,
          Rect.fromLTWH(
            0,
            0,
            collectionCoverWidth.toDouble(),
            collectionCoverHeight.toDouble(),
          ),
          Paint()..filterQuality = FilterQuality.high,
        );
      final picture = recorder.endRecording();
      final cover = await picture.toImage(
        collectionCoverWidth,
        collectionCoverHeight,
      );
      picture.dispose();
      try {
        final data = await cover.toByteData(format: ui.ImageByteFormat.png);
        if (data == null || data.lengthInBytes > 8 * 1024 * 1024) {
          throw const FormatException('Choose a simpler or smaller photo.');
        }
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        cover.dispose();
      }
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
    descriptor.dispose();
  }
}
