import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// ---------------------------------------------------------------------------
// Export profile
// ---------------------------------------------------------------------------

/// Target logical capture scale. The widget capture path also caps final raster
/// width near Lichess' 720px GIF width before calling `toImage`.
const double kGifCapturePixelRatio = 2.0;

const int _gifMoveDelayCs = 50;
const int _gifFinalHoldCs = 160;
const int _gifNeuralSamplingFactor = 30;

/// Describes which frames to capture and at what quality.
class GifExportProfile {
  /// Device-pixel ratio for rasterization.
  final double pixelRatio;

  /// Move indices (0-based into the selected move list) to capture.
  final List<int> frameIndices;

  /// Pre-computed durations in centiseconds.
  /// Length = frameIndices.length + 1 (index 0 = initial position frame).
  final List<int> frameDurations;

  const GifExportProfile({
    required this.pixelRatio,
    required this.frameIndices,
    required this.frameDurations,
  });
}

/// Full move list selected for a shared GIF.
class GifExportWindow {
  /// SAN moves to replay from [captureStartFen] through the final game position.
  final List<String> movesToAnimate;

  /// Offset into the original game move list. Kept for clock lookup.
  final int globalMoveOffset;

  /// Starting FEN for the first GIF frame; null means standard chess start.
  final String? captureStartFen;

  const GifExportWindow({
    required this.movesToAnimate,
    required this.globalMoveOffset,
    required this.captureStartFen,
  });
}

/// Selects the full game used for GIF generation.
///
/// [currentMoveIndex] is intentionally ignored: Share GIF always replays the
/// entire game from the beginning position to avoid ambiguity with the board's
/// currently selected move. Use static image sharing for the current position.
GifExportWindow? computeGifExportWindow({
  required List<String> moveSans,
  required int currentMoveIndex,
  String? startingFen,
}) {
  if (moveSans.isEmpty) return null;

  return GifExportWindow(
    movesToAnimate: List<String>.unmodifiable(moveSans),
    globalMoveOffset: 0,
    captureStartFen: startingFen,
  );
}

// ---------------------------------------------------------------------------
// Worker message protocol
// ---------------------------------------------------------------------------

/// Commands sent from the UI isolate to the encoder worker.
sealed class GifWorkerCommand {}

class GifWorkerFrameData extends GifWorkerCommand {
  final TransferableTypedData rgba;
  final int width;
  final int height;
  final int durationCs;
  final int
  frameIndex; // output-frame index (0 = initial, 1..n = selected move)

  GifWorkerFrameData({
    required this.rgba,
    required this.width,
    required this.height,
    required this.durationCs,
    required this.frameIndex,
  });
}

class GifWorkerFinish extends GifWorkerCommand {}

class GifWorkerCancel extends GifWorkerCommand {}

/// Responses sent from the encoder worker back to the UI isolate.
sealed class GifWorkerResponse {}

class GifWorkerReady extends GifWorkerResponse {
  final SendPort workerSendPort;
  GifWorkerReady(this.workerSendPort);
}

class GifWorkerFrameAccepted extends GifWorkerResponse {
  /// Output-frame index (0 = initial, 1..n = selected moves).
  final int frameIndex;
  GifWorkerFrameAccepted(this.frameIndex);
}

class GifWorkerDone extends GifWorkerResponse {
  /// Zero-copy transfer of the finished GIF bytes.
  final TransferableTypedData gifBytes;
  GifWorkerDone(this.gifBytes);
}

class GifWorkerError extends GifWorkerResponse {
  final String message;
  GifWorkerError(this.message);
}

// ---------------------------------------------------------------------------
// Frame planner
// ---------------------------------------------------------------------------

/// Builds an export profile for the given game length.
///
/// [moveCount] is the number of moves to animate. [currentMoveIndex] should be
/// `moveCount - 1` for normal Share GIF exports, because
/// [computeGifExportWindow] now returns the full game. Every move is captured
/// so the GIF reaches the final board position without dropping plies.
GifExportProfile planGifExport({
  required int moveCount,
  required int currentMoveIndex,
}) {
  assert(moveCount > 0);
  assert(currentMoveIndex >= 0 && currentMoveIndex < moveCount);

  final frameIndices = List<int>.generate(currentMoveIndex + 1, (i) => i);
  final durations = _computeDurations(frameIndices);
  return GifExportProfile(
    pixelRatio: kGifCapturePixelRatio,
    frameIndices: frameIndices,
    frameDurations: durations,
  );
}

/// Precomputes per-frame durations (centiseconds).
///
/// Returns a list of length `frameIndices.length + 1` where index 0
/// is the initial-position frame and indices 1..n correspond to the
/// sampled move frames.
///
/// Each frame holds for `_gifMoveDelayCs * gap_to_next_captured` cs, except the
/// last frame which gets a shorter final hold to keep shared GIFs snappy.
List<int> _computeDurations(List<int> frameIndices) {
  // Conceptual indices: initial = -1, then frameIndices[0], [1], ...
  final allIndices = <int>[-1, ...frameIndices];
  final durations = <int>[];

  for (int i = 0; i < allIndices.length; i++) {
    if (i == allIndices.length - 1) {
      durations.add(_gifFinalHoldCs);
    } else {
      final gap = allIndices[i + 1] - allIndices[i];
      durations.add(_gifMoveDelayCs * gap);
    }
  }

  return durations;
}

// ---------------------------------------------------------------------------
// Worker isolate entry point
// ---------------------------------------------------------------------------

/// Top-level function that runs in a dedicated isolate.
///
/// Protocol:
/// 1. Sends [GifWorkerReady] with its [SendPort].
/// 2. Receives [GifWorkerFrameData] messages, encodes each incrementally,
///    and replies with [GifWorkerFrameAccepted].
/// 3. On [GifWorkerFinish], finalises the GIF and sends [GifWorkerDone].
/// 4. On [GifWorkerCancel], shuts down immediately.
void gifEncoderWorker(SendPort mainSendPort) {
  final workerPort = ReceivePort();

  // Single handshake: send our port inside GifWorkerReady.
  mainSendPort.send(GifWorkerReady(workerPort.sendPort));

  final gif = _DeltaGifEncoder(
    delay: _gifMoveDelayCs,
    dither: img.DitherKernel.none,
    quantizerType: img.QuantizerType.neural,
    numColors: 256,
    samplingFactor: _gifNeuralSamplingFactor,
  );

  workerPort.listen((message) {
    if (message is GifWorkerFrameData) {
      try {
        final rgba = message.rgba.materialize().asUint8List();
        gif.addRgbaFrame(
          rgba,
          width: message.width,
          height: message.height,
          duration: message.durationCs,
        );
        mainSendPort.send(GifWorkerFrameAccepted(message.frameIndex));
      } catch (e) {
        mainSendPort.send(GifWorkerError('Frame ${message.frameIndex}: $e'));
      }
    } else if (message is GifWorkerFinish) {
      try {
        final result = gif.finish();
        if (result == null || result.isEmpty) {
          mainSendPort.send(
            GifWorkerError('GifEncoder.finish() returned null/empty'),
          );
        } else {
          mainSendPort.send(
            GifWorkerDone(TransferableTypedData.fromList([result])),
          );
        }
      } catch (e) {
        mainSendPort.send(GifWorkerError('Finish error: $e'));
      }
      workerPort.close();
    } else if (message is GifWorkerCancel) {
      workerPort.close();
    }
  });
}

// ---------------------------------------------------------------------------
// Synchronous fallback encoder
// ---------------------------------------------------------------------------

/// Encodes a GIF synchronously on the calling isolate.
///
/// Used when [Isolate.spawn] fails (common on some iOS devices).
/// Uses [img.Image.fromBytes] for bulk pixel copy instead of per-pixel loops.
Uint8List? encodeGifFallback({
  required List<Uint8List> rgbaFrames,
  required List<int> widths,
  required List<int> heights,
  required List<int> durationsCs,
}) {
  if (rgbaFrames.isEmpty) return null;

  final gif = _DeltaGifEncoder(
    delay: _gifMoveDelayCs,
    dither: img.DitherKernel.none,
    quantizerType: img.QuantizerType.neural,
    numColors: 256,
    samplingFactor: _gifNeuralSamplingFactor,
  );

  for (int i = 0; i < rgbaFrames.length; i++) {
    final width = widths[i];
    final height = heights[i];
    final rgba = rgbaFrames[i];

    final expectedSize = width * height * 4;
    if (rgba.length != expectedSize) continue;

    gif.addRgbaFrame(
      rgba,
      width: width,
      height: height,
      duration: durationsCs[i],
    );
  }

  return gif.finish();
}

// ---------------------------------------------------------------------------
// Delta GIF encoder
// ---------------------------------------------------------------------------

class _ChangedBounds {
  final int x;
  final int y;
  final int width;
  final int height;

  const _ChangedBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class _PendingGifFrame {
  final img.Image image;
  final int x;
  final int y;
  int duration;

  _PendingGifFrame({
    required this.image,
    required this.x,
    required this.y,
    required this.duration,
  });
}

/// GIF encoder variant that stores unchanged pixels only once.
///
/// The first frame is encoded normally. Later frames are cropped to the
/// changed pixel bounds and written with "do not dispose" semantics, so the
/// previous canvas remains visible outside each changed region.
class _DeltaGifEncoder {
  final int delay;
  final int numColors;
  final img.QuantizerType quantizerType;
  final int samplingFactor;
  final img.DitherKernel dither;

  _DeltaGifEncoder({
    this.delay = 80,
    this.numColors = 256,
    this.quantizerType = img.QuantizerType.neural,
    this.samplingFactor = 10,
    this.dither = img.DitherKernel.floydSteinberg,
  });

  img.OutputBuffer? _output;
  _PendingGifFrame? _pendingFrame;
  Uint8List? _previousRgba;
  late int _width;
  late int _height;
  int _encodedFrames = 0;

  void addRgbaFrame(
    Uint8List rgba, {
    required int width,
    required int height,
    int? duration,
  }) {
    final expectedSize = width * height * 4;
    if (rgba.length != expectedSize) {
      throw ArgumentError(
        'RGBA length ${rgba.length} does not match $width x $height',
      );
    }

    final frameDuration = duration ?? delay;
    final previous = _previousRgba;

    if (previous == null) {
      _output = img.OutputBuffer();
      _width = width;
      _height = height;
      _pendingFrame = _buildPendingFrame(
        rgba,
        sourceWidth: width,
        x: 0,
        y: 0,
        width: width,
        height: height,
        duration: frameDuration,
      );
      _previousRgba = Uint8List.fromList(rgba);
      return;
    }

    if (width != _width || height != _height) {
      throw ArgumentError(
        'All GIF frames must share the initial dimensions '
        '$_width x $_height; got $width x $height',
      );
    }

    final changedBounds = _findChangedBounds(previous, rgba, width, height);
    if (changedBounds == null) {
      _pendingFrame?.duration += frameDuration;
      return;
    }

    _writePendingFrame();
    _pendingFrame = _buildPendingFrame(
      rgba,
      sourceWidth: width,
      x: changedBounds.x,
      y: changedBounds.y,
      width: changedBounds.width,
      height: changedBounds.height,
      duration: frameDuration,
    );
    _previousRgba = Uint8List.fromList(rgba);
  }

  Uint8List? finish() {
    if (_output == null || _pendingFrame == null) return null;

    _writePendingFrame();
    _output!.writeByte(_terminateRecordType);

    final bytes = _output!.getBytes();
    _output = null;
    _pendingFrame = null;
    _previousRgba = null;
    _encodedFrames = 0;
    return bytes;
  }

  _ChangedBounds? _findChangedBounds(
    Uint8List previous,
    Uint8List current,
    int width,
    int height,
  ) {
    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;

    for (var y = 0; y < height; y++) {
      final rowOffset = y * width * 4;
      for (var x = 0; x < width; x++) {
        final offset = rowOffset + x * 4;
        if (previous[offset] != current[offset] ||
            previous[offset + 1] != current[offset + 1] ||
            previous[offset + 2] != current[offset + 2] ||
            previous[offset + 3] != current[offset + 3]) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (maxX < 0) return null;
    return _ChangedBounds(
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
    );
  }

  _PendingGifFrame _buildPendingFrame(
    Uint8List rgba, {
    required int sourceWidth,
    required int x,
    required int y,
    required int width,
    required int height,
    required int duration,
  }) {
    final frameBytes =
        x == 0 &&
                y == 0 &&
                width == sourceWidth &&
                rgba.length == width * height * 4
            ? rgba
            : _copyRgbaRect(
              rgba,
              sourceWidth: sourceWidth,
              x: x,
              y: y,
              width: width,
              height: height,
            );

    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: frameBytes.buffer,
      bytesOffset: frameBytes.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );

    final indexedImage = _quantize(image);
    return _PendingGifFrame(
      image: indexedImage,
      x: x,
      y: y,
      duration: duration,
    );
  }

  Uint8List _copyRgbaRect(
    Uint8List rgba, {
    required int sourceWidth,
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    final bytesPerPixel = 4;
    final rowBytes = width * bytesPerPixel;
    final sourceStride = sourceWidth * bytesPerPixel;
    final out = Uint8List(rowBytes * height);

    for (var row = 0; row < height; row++) {
      final sourceStart = (y + row) * sourceStride + x * bytesPerPixel;
      final targetStart = row * rowBytes;
      out.setRange(targetStart, targetStart + rowBytes, rgba, sourceStart);
    }

    return out;
  }

  img.Image _quantize(img.Image image) {
    final img.Quantizer quantizer;
    switch (quantizerType) {
      case img.QuantizerType.neural:
        quantizer = img.NeuralQuantizer(
          image,
          numberOfColors: numColors,
          samplingFactor: samplingFactor,
        );
        break;
      case img.QuantizerType.octree:
        quantizer = img.OctreeQuantizer(image, numberOfColors: numColors);
        break;
      case img.QuantizerType.binary:
        quantizer = img.BinaryQuantizer();
        break;
    }

    return img.ditherImage(
      image,
      quantizer: quantizer,
      kernel: dither,
      serpentine: false,
    );
  }

  void _writePendingFrame() {
    final frame = _pendingFrame;
    if (frame == null) return;

    if (_encodedFrames == 0) {
      _writeHeader(_width, _height);
      _writeApplicationExt();
    }

    _writeGraphicsCtrlExt(frame.duration);
    _addImage(frame.image, frame.x, frame.y);
    _encodedFrames++;
    _pendingFrame = null;
  }

  void _addImage(img.Image image, int x, int y) {
    if (!image.hasPalette) {
      throw img.ImageException('GIF can only encode palette images.');
    }

    final palette = image.palette!;
    final numColors = palette.numColors;
    final out =
        _output!
          ..writeByte(_imageDescRecordType)
          ..writeUint16(x)
          ..writeUint16(y)
          ..writeUint16(image.width)
          ..writeUint16(image.height);

    // Use an 8-bit local color table, matching package:image's GIF encoder.
    out.writeByte(0x87);

    final paletteBytes = palette.toUint8List();
    final numChannels = palette.numChannels;
    if (numChannels == 3) {
      out.writeBytes(paletteBytes);
    } else if (numChannels == 4) {
      for (var i = 0, pi = 0; i < numColors; ++i, pi += 4) {
        out
          ..writeByte(paletteBytes[pi])
          ..writeByte(paletteBytes[pi + 1])
          ..writeByte(paletteBytes[pi + 2]);
      }
    } else if (numChannels == 1 || numChannels == 2) {
      for (var i = 0, pi = 0; i < numColors; ++i, pi += numChannels) {
        final g = paletteBytes[pi];
        out
          ..writeByte(g)
          ..writeByte(g)
          ..writeByte(g);
      }
    }

    for (var i = numColors; i < 256; ++i) {
      out
        ..writeByte(0)
        ..writeByte(0)
        ..writeByte(0);
    }

    _encodeLzw(image);
  }

  void _encodeLzw(img.Image image) {
    _curAccum = 0;
    _curBits = 0;
    _blockSize = 0;
    _block = Uint8List(256);

    const initCodeSize = 8;
    _output!.writeByte(initCodeSize);

    final hTab = Int32List(_hSize);
    final codeTab = Int32List(_hSize);
    final pIter = image.iterator..moveNext();

    _initBits = initCodeSize + 1;
    _nBits = _initBits;
    _maxCode = (1 << _nBits) - 1;
    _clearCode = 1 << (_initBits - 1);
    _eofCode = _clearCode + 1;
    _clearFlag = false;
    _freeEnt = _clearCode + 2;
    var pFinished = false;

    int nextPixel() {
      if (pFinished) return _eof;
      final r = pIter.current.index as int;
      if (!pIter.moveNext()) {
        pFinished = true;
      }
      return r;
    }

    var ent = nextPixel();
    var hShift = 0;
    for (var fCode = _hSize; fCode < 65536; fCode *= 2) {
      hShift++;
    }
    hShift = 8 - hShift;

    const hSizeReg = _hSize;
    for (var i = 0; i < hSizeReg; ++i) {
      hTab[i] = -1;
    }

    _outputCode(_clearCode);

    var outerLoop = true;
    while (outerLoop) {
      outerLoop = false;

      var c = nextPixel();
      while (c != _eof) {
        final fcode = (c << _bits) + ent;
        var i = (c << hShift) ^ ent;

        if (hTab[i] == fcode) {
          ent = codeTab[i];
          c = nextPixel();
          continue;
        } else if (hTab[i] >= 0) {
          var disp = hSizeReg - i;
          if (i == 0) disp = 1;
          do {
            if ((i -= disp) < 0) {
              i += hSizeReg;
            }

            if (hTab[i] == fcode) {
              ent = codeTab[i];
              outerLoop = true;
              break;
            }
          } while (hTab[i] >= 0);
          if (outerLoop) break;
        }

        _outputCode(ent);
        ent = c;

        if (_freeEnt < (1 << _bits)) {
          codeTab[i] = _freeEnt++;
          hTab[i] = fcode;
        } else {
          for (var i = 0; i < _hSize; ++i) {
            hTab[i] = -1;
          }
          _freeEnt = _clearCode + 2;
          _clearFlag = true;
          _outputCode(_clearCode);
        }

        c = nextPixel();
      }
    }

    _outputCode(ent);
    _outputCode(_eofCode);
    _output!.writeByte(0);
  }

  void _outputCode(int? code) {
    _curAccum &= _masks[_curBits];

    if (_curBits > 0) {
      _curAccum |= code! << _curBits;
    } else {
      _curAccum = code!;
    }

    _curBits += _nBits;

    while (_curBits >= 8) {
      _addToBlock(_curAccum & 0xff);
      _curAccum >>= 8;
      _curBits -= 8;
    }

    if (_freeEnt > _maxCode || _clearFlag) {
      if (_clearFlag) {
        _nBits = _initBits;
        _maxCode = (1 << _nBits) - 1;
        _clearFlag = false;
      } else {
        ++_nBits;
        if (_nBits == _bits) {
          _maxCode = 1 << _bits;
        } else {
          _maxCode = (1 << _nBits) - 1;
        }
      }
    }

    if (code == _eofCode) {
      while (_curBits > 0) {
        _addToBlock(_curAccum & 0xff);
        _curAccum >>= 8;
        _curBits -= 8;
      }
      _writeBlock();
    }
  }

  void _writeGraphicsCtrlExt(int duration) {
    _output!
      ..writeByte(_extensionRecordType)
      ..writeByte(_graphicControlExt)
      ..writeByte(4);

    const disposeDoNotDispose = 1;
    final fields = disposeDoNotDispose << 2;
    _output!
      ..writeByte(fields)
      ..writeUint16(duration)
      ..writeByte(0)
      ..writeByte(0);
  }

  void _writeHeader(int width, int height) {
    _output!
      ..writeBytes(_gif89Id.codeUnits)
      ..writeUint16(width)
      ..writeUint16(height)
      ..writeByte(0)
      ..writeByte(0)
      ..writeByte(0);
  }

  void _writeApplicationExt() {
    _output!
      ..writeByte(_extensionRecordType)
      ..writeByte(_applicationExt)
      ..writeByte(11)
      ..writeBytes('NETSCAPE2.0'.codeUnits)
      ..writeBytes([0x03, 0x01])
      ..writeUint16(0)
      ..writeByte(0);
  }

  void _addToBlock(int c) {
    _block[_blockSize++] = c;
    if (_blockSize >= 254) {
      _writeBlock();
    }
  }

  void _writeBlock() {
    if (_blockSize > 0) {
      _output!.writeByte(_blockSize);
      _output!.writeBytes(_block, _blockSize);
      _blockSize = 0;
    }
  }

  int _curAccum = 0;
  int _curBits = 0;
  int _nBits = 0;
  int _initBits = 0;
  int _eofCode = 0;
  int _maxCode = 0;
  int _clearCode = 0;
  int _freeEnt = 0;
  bool _clearFlag = false;
  late Uint8List _block;
  int _blockSize = 0;

  static const _gif89Id = 'GIF89a';
  static const _imageDescRecordType = 0x2c;
  static const _extensionRecordType = 0x21;
  static const _terminateRecordType = 0x3b;
  static const _applicationExt = 0xff;
  static const _graphicControlExt = 0xf9;
  static const _eof = -1;
  static const _bits = 12;
  static const _hSize = 5003;
  static const _masks = [
    0x0000,
    0x0001,
    0x0003,
    0x0007,
    0x000F,
    0x001F,
    0x003F,
    0x007F,
    0x00FF,
    0x01FF,
    0x03FF,
    0x07FF,
    0x0FFF,
    0x1FFF,
    0x3FFF,
    0x7FFF,
    0xFFFF,
  ];
}
