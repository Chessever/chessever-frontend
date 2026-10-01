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
/// Returns null when the user cancels.
final collectionCoverPickerProvider = Provider<Future<Uint8List?> Function()>(
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
    return prepareCollectionCover(source);
  },
);

/// Centre-crops [bytes] to 2:3 and renders it at exactly 800×1200 (PNG).
/// Refuses photos whose crop would be smaller than 600×900, rather than
/// upscaling them into a blurry cover.
Future<Uint8List> prepareCollectionCover(Uint8List bytes) async {
  if (bytes.length > _maxSourceBytes) {
    throw const FormatException('Choose a photo smaller than 25 MB.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  late final ui.Codec codec;
  late final Rect crop;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width, h = descriptor.height;
    if (w * h > 60000000) {
      throw const FormatException('Choose a photo with smaller dimensions.');
    }
    // Largest 2:3 window centred in the photo.
    final cropW = math.min(w.toDouble(), h * 2 / 3);
    final cropH = cropW * 3 / 2;
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
    final cw = cropW * factor, ch = cropH * factor;
    crop = Rect.fromLTWH((dw - cw) / 2, (dh - ch) / 2, cw, ch);
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
          crop,
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
