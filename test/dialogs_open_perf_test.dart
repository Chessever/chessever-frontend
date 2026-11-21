// Group G5 ("dialogs") of the popup sweep: what opening each popup costs.
//
// For every popup of the group, over a busy page of live boards, dark
// theme, seven runs (the first discarded as JIT warm-up):
//  - open: wall time from the opener to the end of the first frame that
//    shows the popup (the frame's build, layout, paint and compositing);
//  - frames: the frames the open goes on asking for afterwards, until it
//    rests (capped at 120: a popup whose content loops never rests);
//  - blur: how many of those frames carry a backdrop filter over the whole
//    screen (a full-screen re-blur on the GPU every frame);
//  - frame: the median cost of one of those frames.
//
// Host timings in the Dart VM test engine are a proxy for the device, not a
// device measurement. The same file runs on a scratch export of HEAD for the
// numbers before the sweep:
//
//   flutter test --no-pub test/dialogs_open_perf_test.dart
import 'dart:io';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dialogs_harness.dart';

const _runs = 7;

double _median(List<num> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid].toDouble()
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final report = <String>[];

  setUpAll(() async {
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
  });

  tearDownAll(() {
    final out = [
      'G5 dialogs open perf (${Platform.operatingSystem} host, dark, '
          'median of ${_runs - 1})',
      ...report,
    ].join('\n');
    // ignore: avoid_print
    print(out);
  });

  for (final scene in dialogScenes) {
    testWidgets('opening ${scene.name}', (tester) async {
      muteDialogsPlatform(tester);
      final open = <int>[];
      final frames = <int>[];
      final blurs = <int>[];
      final frameCost = <int>[];
      for (var run = 0; run < _runs; run++) {
        final opener = await scene.open(tester, light: false);
        final clock = Stopwatch()..start();
        opener();
        await tester.pump(scene.firstPump);
        var extra = 0;
        while (scene.shown().evaluate().isEmpty && extra < 20) {
          await tester.pump();
          extra++;
        }
        clock.stop();
        expect(scene.shown(), findsWidgets, reason: scene.name);
        var count = 0;
        var blurred = fullScreenBlurs(tester) > 0 ? 1 : 0;
        final costs = <int>[];
        while (tester.binding.hasScheduledFrame && count < 120) {
          final frame = Stopwatch()..start();
          await tester.pump(const Duration(milliseconds: 16));
          frame.stop();
          costs.add(frame.elapsedMicroseconds);
          count++;
          if (fullScreenBlurs(tester) > 0) blurred++;
        }
        expect(tester.takeException(), isNull);
        await scene.close?.call(tester);
        await tester.pumpWidget(const SizedBox());
        if (run == 0) continue;
        open.add(clock.elapsedMicroseconds);
        frames.add(count);
        blurs.add(blurred);
        if (costs.isNotEmpty) frameCost.add(_median(costs).round());
      }
      String ms(num us) => (us / 1000).toStringAsFixed(2);
      report.add(
        '${scene.name.padRight(18)} open ${ms(_median(open)).padLeft(7)} ms'
        '  frames ${_median(frames).round().toString().padLeft(3)}'
        '  full-screen blur ${_median(blurs).round().toString().padLeft(3)}'
        '  frame ${frameCost.isEmpty ? '   -' : ms(_median(frameCost)).padLeft(5)} ms'
        '  (open runs: ${open.map(ms).join(' ')})',
      );
    });
  }
}
