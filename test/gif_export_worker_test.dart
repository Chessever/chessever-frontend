import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:chessever2/screens/chessboard/widgets/gif_export_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('computeGifExportWindow', () {
    test('animates only up to the focused move', () {
      final moves = List.generate(20, (i) => 'move$i');

      final window = computeGifExportWindow(
        moveSans: moves,
        currentMoveIndex: 5,
        startingFen: 'custom start',
      );

      expect(window, isNotNull);
      // moves move0..move5 inclusive (6 moves).
      expect(window!.movesToAnimate, moves.sublist(0, 6));
      expect(window.movesToAnimate.last, 'move5');
      expect(window.globalMoveOffset, 0);
      expect(window.captureStartFen, 'custom start');
    });

    test('stops at the focused move for long games', () {
      final moves = List.generate(80, (i) => 'move$i');

      final window = computeGifExportWindow(
        moveSans: moves,
        currentMoveIndex: 5,
      );

      expect(window, isNotNull);
      expect(window!.movesToAnimate.length, 6);
      expect(window.movesToAnimate.first, 'move0');
      expect(window.movesToAnimate.last, 'move5');
    });

    test('exports the whole game when the final move is focused', () {
      final moves = List.generate(20, (i) => 'move$i');

      final window = computeGifExportWindow(
        moveSans: moves,
        currentMoveIndex: moves.length - 1,
      );

      expect(window, isNotNull);
      expect(window!.movesToAnimate, moves);
      expect(window.movesToAnimate.last, 'move19');
    });

    test('falls back to the full game when no move is focused', () {
      final window = computeGifExportWindow(
        moveSans: const ['e4', 'e5'],
        currentMoveIndex: -1,
      );

      expect(window, isNotNull);
      expect(window!.movesToAnimate, ['e4', 'e5']);
    });

    test('clamps an out-of-range focused index to the full game', () {
      final moves = List.generate(10, (i) => 'move$i');

      final window = computeGifExportWindow(
        moveSans: moves,
        currentMoveIndex: 999,
      );

      expect(window, isNotNull);
      expect(window!.movesToAnimate, moves);
    });

    test('returns null when there are no moves', () {
      final window = computeGifExportWindow(
        moveSans: const <String>[],
        currentMoveIndex: 0,
      );

      expect(window, isNull);
    });
  });

  group('planGifExport', () {
    test('captures every selected move at sharp capture ratio', () {
      final profile = planGifExport(moveCount: 12, currentMoveIndex: 11);

      expect(profile.pixelRatio, kGifCapturePixelRatio);
      expect(profile.frameIndices, List.generate(12, (i) => i));
      // 13 durations: 1 initial + 12 moves
      expect(profile.frameDurations.length, 13);
      // All non-final durations should be 50cs (gap of 1)
      for (int i = 0; i < 12; i++) {
        expect(profile.frameDurations[i], 50);
      }
      expect(profile.frameDurations[12], 160);
    });

    test('medium game keeps every move frame', () {
      final profile = planGifExport(moveCount: 80, currentMoveIndex: 79);

      expect(profile.pixelRatio, kGifCapturePixelRatio);
      expect(profile.frameIndices, List.generate(80, (i) => i));
      expect(profile.frameDurations.length, 81);
    });

    test('long game keeps every move frame', () {
      final profile = planGifExport(moveCount: 150, currentMoveIndex: 149);

      expect(profile.pixelRatio, kGifCapturePixelRatio);
      expect(profile.frameIndices.length, 150);
      expect(profile.frameIndices.first, 0);
      expect(profile.frameIndices.last, 149);
      expect(profile.frameDurations.length, 151);
    });

    test('long game durations accumulate correctly without sampling gaps', () {
      final profile = planGifExport(moveCount: 150, currentMoveIndex: 149);

      // 150 transition frames from initial through move 149.
      // Last frame hold is 160cs.
      final totalDuration = profile.frameDurations.reduce((a, b) => a + b);
      expect(totalDuration, 50 * 150 + 160);
    });

    test('captures only through the selected current move', () {
      final profile = planGifExport(moveCount: 6, currentMoveIndex: 5);

      expect(profile.frameIndices, [0, 1, 2, 3, 4, 5]);
      expect(profile.frameDurations.length, 7);
    });
  });

  group('gifEncoderWorker', () {
    test('produces a non-empty GIF from synthetic frames', () async {
      final mainPort = ReceivePort();

      final isolate = await Isolate.spawn(gifEncoderWorker, mainPort.sendPort);

      final responses = <GifWorkerResponse>[];
      final doneCompleter = Completer<Uint8List>();
      SendPort? workerSendPort;
      final readyCompleter = Completer<SendPort>();

      final subscription = mainPort.listen((message) {
        if (message is GifWorkerReady) {
          readyCompleter.complete(message.workerSendPort);
        } else if (message is GifWorkerFrameAccepted) {
          responses.add(message);
        } else if (message is GifWorkerDone) {
          doneCompleter.complete(message.gifBytes.materialize().asUint8List());
        } else if (message is GifWorkerError) {
          doneCompleter.completeError(Exception(message.message));
        }
      });

      workerSendPort = await readyCompleter.future.timeout(
        const Duration(seconds: 5),
      );

      // Send 3 synthetic 2x2 RGBA frames
      const w = 2;
      const h = 2;
      for (int i = 0; i < 3; i++) {
        final rgba = Uint8List(w * h * 4);
        // Fill with a distinct color per frame
        for (int p = 0; p < w * h; p++) {
          rgba[p * 4] = (i * 80) % 256; // R
          rgba[p * 4 + 1] = 128; // G
          rgba[p * 4 + 2] = 64; // B
          rgba[p * 4 + 3] = 255; // A
        }

        workerSendPort.send(
          GifWorkerFrameData(
            rgba: TransferableTypedData.fromList([rgba]),
            width: w,
            height: h,
            durationCs: i == 2 ? 300 : 80,
            frameIndex: i,
          ),
        );
      }

      workerSendPort.send(GifWorkerFinish());

      final gifBytes = await doneCompleter.future.timeout(
        const Duration(seconds: 10),
      );

      // Verify we got 3 frame-accepted responses
      expect(responses.length, 3);
      for (int i = 0; i < 3; i++) {
        expect((responses[i] as GifWorkerFrameAccepted).frameIndex, i);
      }

      // Verify GIF output is non-empty and starts with GIF magic bytes
      expect(gifBytes.length, greaterThan(0));
      // GIF89a magic: 0x47 0x49 0x46 0x38 0x39 0x61
      expect(gifBytes[0], 0x47); // G
      expect(gifBytes[1], 0x49); // I
      expect(gifBytes[2], 0x46); // F

      await subscription.cancel();
      mainPort.close();
      isolate.kill(priority: Isolate.immediate);
    });
  });

  group('encodeGifFallback', () {
    test('produces a non-empty GIF from synthetic frames', () {
      const w = 4;
      const h = 4;
      final frames = <Uint8List>[];
      final widths = <int>[];
      final heights = <int>[];
      final durations = <int>[];

      for (int i = 0; i < 3; i++) {
        final rgba = Uint8List(w * h * 4);
        for (int p = 0; p < w * h; p++) {
          rgba[p * 4] = (i * 60) % 256;
          rgba[p * 4 + 1] = 100;
          rgba[p * 4 + 2] = 200;
          rgba[p * 4 + 3] = 255;
        }
        frames.add(rgba);
        widths.add(w);
        heights.add(h);
        durations.add(i == 2 ? 300 : 80);
      }

      final result = encodeGifFallback(
        rgbaFrames: frames,
        widths: widths,
        heights: heights,
        durationsCs: durations,
      );

      expect(result, isNotNull);
      expect(result!.length, greaterThan(0));
      // GIF magic bytes
      expect(result[0], 0x47);
      expect(result[1], 0x49);
      expect(result[2], 0x46);
    });

    test('returns null for empty input', () {
      final result = encodeGifFallback(
        rgbaFrames: [],
        widths: [],
        heights: [],
        durationsCs: [],
      );

      expect(result, isNull);
    });

    test('writes smaller GIFs for sparse frame changes', () {
      const w = 80;
      const h = 80;
      final frames = <Uint8List>[];
      final widths = <int>[];
      final heights = <int>[];
      final durations = <int>[];

      for (int i = 0; i < 18; i++) {
        final rgba = _solidFrame(w, h, r: 245, g: 245, b: 245);
        final markerX = 4 + i * 3;
        final markerY = 12 + (i % 4) * 8;
        _fillRect(
          rgba,
          w,
          x: markerX,
          y: markerY,
          width: 6,
          height: 6,
          r: 20,
          g: 90,
          b: 220,
        );
        frames.add(rgba);
        widths.add(w);
        heights.add(h);
        durations.add(50);
      }

      final optimized = encodeGifFallback(
        rgbaFrames: frames,
        widths: widths,
        heights: heights,
        durationsCs: durations,
      );
      final fullFrame = _encodeFullFrameGif(
        frames: frames,
        widths: widths,
        heights: heights,
        durationsCs: durations,
      );

      expect(optimized, isNotNull);
      expect(optimized!.length, lessThan(fullFrame.length));
    });

    test('preserves the final composited frame', () {
      const w = 24;
      const h = 24;
      final frames = <Uint8List>[];
      final widths = <int>[];
      final heights = <int>[];
      final durations = <int>[];

      for (int i = 0; i < 4; i++) {
        final rgba = _solidFrame(w, h, r: 255, g: 255, b: 255);
        _fillRect(
          rgba,
          w,
          x: 2 + i * 4,
          y: 3 + i * 3,
          width: 5,
          height: 5,
          r: 0,
          g: 0,
          b: 0,
        );
        frames.add(rgba);
        widths.add(w);
        heights.add(h);
        durations.add(50);
      }

      final optimized = encodeGifFallback(
        rgbaFrames: frames,
        widths: widths,
        heights: heights,
        durationsCs: durations,
      );

      expect(optimized, isNotNull);
      final decoded = img.GifDecoder().decode(optimized!);
      expect(decoded, isNotNull);
      expect(decoded!.frames, isNotEmpty);

      final finalFrame = decoded.frames.last;
      final expected = frames.last;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final expectedOffset = (y * w + x) * 4;
          final pixel = finalFrame.getPixel(x, y);
          expect(pixel.r.toInt(), expected[expectedOffset]);
          expect(pixel.g.toInt(), expected[expectedOffset + 1]);
          expect(pixel.b.toInt(), expected[expectedOffset + 2]);
        }
      }
    });
  });
}

Uint8List _solidFrame(
  int width,
  int height, {
  required int r,
  required int g,
  required int b,
}) {
  final rgba = Uint8List(width * height * 4);
  for (int p = 0; p < width * height; p++) {
    rgba[p * 4] = r;
    rgba[p * 4 + 1] = g;
    rgba[p * 4 + 2] = b;
    rgba[p * 4 + 3] = 255;
  }
  return rgba;
}

void _fillRect(
  Uint8List rgba,
  int frameWidth, {
  required int x,
  required int y,
  required int width,
  required int height,
  required int r,
  required int g,
  required int b,
}) {
  for (int yy = y; yy < y + height; yy++) {
    for (int xx = x; xx < x + width; xx++) {
      final offset = (yy * frameWidth + xx) * 4;
      rgba[offset] = r;
      rgba[offset + 1] = g;
      rgba[offset + 2] = b;
      rgba[offset + 3] = 255;
    }
  }
}

Uint8List _encodeFullFrameGif({
  required List<Uint8List> frames,
  required List<int> widths,
  required List<int> heights,
  required List<int> durationsCs,
}) {
  final gif = img.GifEncoder(
    delay: 50,
    dither: img.DitherKernel.none,
    quantizerType: img.QuantizerType.neural,
    numColors: 256,
    samplingFactor: 30,
  );

  for (int i = 0; i < frames.length; i++) {
    final image = img.Image.fromBytes(
      width: widths[i],
      height: heights[i],
      bytes: frames[i].buffer,
      bytesOffset: frames[i].offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    gif.addFrame(image, duration: durationsCs[i]);
  }

  return gif.finish()!;
}
