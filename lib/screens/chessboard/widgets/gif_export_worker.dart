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

/// Move prefix selected for a shared GIF.
class GifExportWindow {
  /// SAN moves to replay from [captureStartFen] up to the selected end move.
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

/// Selects the move prefix used for GIF generation.
///
/// [currentMoveIndex] is the user-selected end position. The GIF always starts
/// from the game's beginning position and replays the prefix up to that move.
GifExportWindow? computeGifExportWindow({
  required List<String> moveSans,
  required int currentMoveIndex,
  String? startingFen,
}) {
  if (moveSans.isEmpty || currentMoveIndex < 0) return null;

  final endIndex =
      currentMoveIndex < moveSans.length
          ? currentMoveIndex
          : moveSans.length - 1;

  return GifExportWindow(
    movesToAnimate: List<String>.unmodifiable(
      moveSans.sublist(0, endIndex + 1),
    ),
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
/// `moveCount - 1`, because [computeGifExportWindow] already trims the source
/// moves to the user-selected end position. Every selected move is captured so
/// the GIF reaches the exact current board position without dropping plies.
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

  final gif = img.GifEncoder(
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
        final image = img.Image.fromBytes(
          width: message.width,
          height: message.height,
          bytes: rgba.buffer,
          numChannels: 4,
          order: img.ChannelOrder.rgba,
        );

        gif.addFrame(image, duration: message.durationCs);
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

  final gif = img.GifEncoder(
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

    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );

    gif.addFrame(image, duration: durationsCs[i]);
  }

  return gif.finish();
}
