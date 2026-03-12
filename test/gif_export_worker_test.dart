import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:chessever2/screens/chessboard/widgets/gif_export_worker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('planGifExport', () {
    test('short game (20 moves) keeps all frames at pixelRatio 1.25', () {
      final profile = planGifExport(moveCount: 20, currentMoveIndex: 19);

      expect(profile.pixelRatio, 1.25);
      expect(profile.frameIndices, List.generate(20, (i) => i));
      // 21 durations: 1 initial + 20 moves
      expect(profile.frameDurations.length, 21);
      // All non-final durations should be 80cs (gap of 1)
      for (int i = 0; i < 20; i++) {
        expect(profile.frameDurations[i], 80);
      }
      // Last frame: 300cs (3s hold)
      expect(profile.frameDurations[20], 300);
    });

    test('medium game (80 moves) keeps all frames at pixelRatio 1.0', () {
      final profile = planGifExport(moveCount: 80, currentMoveIndex: 79);

      expect(profile.pixelRatio, 1.0);
      expect(profile.frameIndices.length, 80);
      expect(profile.frameDurations.length, 81);
      // Last duration is 300cs
      expect(profile.frameDurations.last, 300);
    });

    test('boundary: 60 moves stays in short tier', () {
      final profile = planGifExport(moveCount: 60, currentMoveIndex: 59);

      expect(profile.pixelRatio, 1.25);
      expect(profile.frameIndices.length, 60);
    });

    test('boundary: 61 moves moves to medium tier', () {
      final profile = planGifExport(moveCount: 61, currentMoveIndex: 60);

      expect(profile.pixelRatio, 1.0);
      expect(profile.frameIndices.length, 61);
    });

    test('boundary: 100 moves stays in medium tier', () {
      final profile = planGifExport(moveCount: 100, currentMoveIndex: 99);

      expect(profile.pixelRatio, 1.0);
      expect(profile.frameIndices.length, 100);
    });

    test('boundary: 101 moves moves to long tier', () {
      final profile = planGifExport(moveCount: 101, currentMoveIndex: 100);

      expect(profile.pixelRatio, 1.0);
      expect(profile.frameIndices.length, 59);
      // Total output frames = 1 initial + 59 = 60
      expect(profile.frameDurations.length, 60);
    });

    test('long game (150 moves) caps to 59 sampled move frames', () {
      final profile = planGifExport(moveCount: 150, currentMoveIndex: 149);

      expect(profile.pixelRatio, 1.0);
      expect(profile.frameIndices.length, 59);
      // 60 total output frames: 1 initial + 59 sampled
      expect(profile.frameDurations.length, 60);
    });

    test('long game includes required indices', () {
      final profile = planGifExport(moveCount: 150, currentMoveIndex: 149);
      final indices = profile.frameIndices;

      // Must include move 0
      expect(indices.contains(0), isTrue);
      // Must include currentMoveIndex
      expect(indices.contains(149), isTrue);
      // Must include previous 8 moves (141-148)
      for (int i = 141; i <= 148; i++) {
        expect(indices.contains(i), isTrue, reason: 'Missing index $i');
      }
      // Sorted
      for (int i = 1; i < indices.length; i++) {
        expect(indices[i], greaterThan(indices[i - 1]));
      }
    });

    test('long game durations accumulate correctly for gaps', () {
      final profile = planGifExport(moveCount: 150, currentMoveIndex: 149);

      // Non-last durations telescope: 80 * (lastIndex - (-1)) = 80 * 150 = 12000
      // Last frame: 300cs
      // Total = 12000 + 300 = 12300
      final totalDuration =
          profile.frameDurations.reduce((a, b) => a + b);
      expect(totalDuration, 80 * 150 + 300);
    });

    test('edge case: currentMoveIndex < 9 includes available previous moves',
        () {
      final profile = planGifExport(moveCount: 120, currentMoveIndex: 5);
      final indices = profile.frameIndices;

      // Must include move 0 and move 5
      expect(indices.contains(0), isTrue);
      expect(indices.contains(5), isTrue);
      // Includes moves 1-4 (all available before current)
      for (int i = 1; i <= 4; i++) {
        expect(indices.contains(i), isTrue, reason: 'Missing index $i');
      }
    });
  });

  group('sampleFrameIndices', () {
    test('returns sorted, deduplicated list', () {
      final indices = sampleFrameIndices(
        totalMoves: 200,
        targetMoveFrames: 59,
        currentMoveIndex: 199,
      );

      // Sorted
      for (int i = 1; i < indices.length; i++) {
        expect(indices[i], greaterThan(indices[i - 1]));
      }
      // No duplicates
      expect(indices.toSet().length, indices.length);
    });

    test('does not exceed target', () {
      final indices = sampleFrameIndices(
        totalMoves: 500,
        targetMoveFrames: 59,
        currentMoveIndex: 499,
      );

      expect(indices.length, lessThanOrEqualTo(59));
    });

    test('includes must-have indices', () {
      final indices = sampleFrameIndices(
        totalMoves: 300,
        targetMoveFrames: 59,
        currentMoveIndex: 299,
      );

      expect(indices.contains(0), isTrue);
      expect(indices.contains(299), isTrue);
      for (int i = 291; i <= 298; i++) {
        expect(indices.contains(i), isTrue);
      }
    });
  });

  group('gifEncoderWorker', () {
    test('produces a non-empty GIF from synthetic frames', () async {
      final mainPort = ReceivePort();

      final isolate = await Isolate.spawn(
        gifEncoderWorker,
        mainPort.sendPort,
      );

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

      workerSendPort =
          await readyCompleter.future.timeout(const Duration(seconds: 5));

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

        workerSendPort.send(GifWorkerFrameData(
          rgba: TransferableTypedData.fromList([rgba]),
          width: w,
          height: h,
          durationCs: i == 2 ? 300 : 80,
          frameIndex: i,
        ));
      }

      workerSendPort.send(GifWorkerFinish());

      final gifBytes =
          await doneCompleter.future.timeout(const Duration(seconds: 10));

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
  });
}
