// How cheap is opening each G4 popover (dropdowns and anchored panels)?
//
// For every scene, opened the way a reader opens it:
//  * frames from the tap to the first frame that draws the popover;
//  * host time of that path (tap dispatch plus those frames' build, layout
//    and paint): cold (first open) and the median of warm opens;
//  * frames the popover itself moves before it rests (its rows stop moving
//    and nothing fades them), and every frame scheduled until the screen is
//    idle (that one includes the trigger's own ink ripple).
//
// Then two in-process A/B pairs, runs interleaved so drift hits both sides:
// Material's DropdownButton menu against GlassDropdown on identical items,
// and an opaque popover panel against the glass one.
//
// Host timings in flutter_test are a proxy for a phone's: they rank the
// work, they do not predict milliseconds on a device (and no blur is
// rasterized here). The frame counts are exact.
//
//   flutter test --no-pub test/g4_dropdowns_open_perf_test.dart
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'g4_dropdowns_harness.dart';

const _runs = 11;

double _median(List<num> values) {
  final sorted = [for (final v in values) v.toDouble()]..sort();
  return sorted[sorted.length ~/ 2];
}

String _ms(double v) => v.toStringAsFixed(1);

/// One timed open: host ms to the first popover frame, the frames that
/// took, and the frames the popover then moves.
Future<(double, int, int)> _timedOpen(
  WidgetTester tester,
  Finder Function() trigger,
  Finder Function() marker,
) async {
  final before = marker().evaluate().length;
  final watch = Stopwatch()..start();
  await tester.tap(trigger().first, warnIfMissed: false);
  var frames = 0;
  while (frames < 12) {
    await tester.pump();
    frames++;
    if (marker().evaluate().length > before) break;
  }
  watch.stop();
  expect(frames, lessThan(12), reason: 'the popover never showed');
  final motion = await g4PanelMotionFrames(tester, marker);
  return (watch.elapsedMicroseconds / 1000, frames, motion);
}

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  home: Builder(
    builder: (context) {
      ResponsiveHelper.init(context);
      return Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: G4BusyBoards(top: 130)),
            Positioned(left: 24, right: 24, top: 70, child: child),
          ],
        ),
      );
    },
  ),
);

void main() {
  for (final scene in g4Scenes) {
    testWidgets('${scene.name}: open cost', (tester) async {
      await scene.pump(tester, light: false);
      await g4Settle(tester, cap: 60);

      final openMs = <double>[];
      final firstFrames = <int>[];
      final motion = <int>[];
      final idle = <int>[];
      double? coldMs;
      for (var run = 0; run < _runs + 1; run++) {
        final (ms, frames, moved) = await _timedOpen(
          tester,
          scene.trigger,
          scene.marker,
        );
        final rest = await g4Settle(tester);
        if (run == 0) {
          coldMs = ms;
        } else {
          openMs.add(ms);
          firstFrames.add(frames);
          motion.add(moved);
          idle.add(moved + rest);
        }
        await g4Dismiss(tester);
      }
      expect(tester.takeException(), isNull);
      // ignore: avoid_print
      print(
        'G4PERF ${scene.name}: tap->popover ${firstFrames.first} frame(s); '
        'host cold ${_ms(coldMs!)} ms, warm median ${_ms(_median(openMs))} '
        'ms; panel moves ${_median(motion).toInt()} frames; '
        'idle after ${_median(idle).toInt()} frames (cap 120)',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    });
  }

  // Material's menu against the glass one, on identical rows.
  for (final count in [25, 250]) {
    testWidgets('A/B DropdownButton vs GlassDropdown, $count rows', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = g4Screen * 3;
      addTearDown(tester.view.reset);
      final labels = [for (var i = 0; i < count; i++) 'Round ${i + 1}'];
      final items = [
        for (final label in labels)
          DropdownMenuItem(value: label, child: Text(label)),
      ];
      final selected = labels[count * 2 ~/ 3];
      final marker = labels[count * 2 ~/ 3 + 1];
      final cases = <String, Widget>{
        'DropdownButton': DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const ValueKey('ab'),
            value: selected,
            isExpanded: true,
            menuMaxHeight: 400,
            items: items,
            onChanged: (_) {},
          ),
        ),
        'GlassDropdown': DropdownButtonHideUnderline(
          child: GlassDropdown<String>(
            key: const ValueKey('ab'),
            value: selected,
            isExpanded: true,
            menuMaxHeight: 400,
            items: items,
            onChanged: (_) {},
          ),
        ),
      };
      final ms = {for (final name in cases.keys) name: <double>[]};
      final moves = {for (final name in cases.keys) name: <int>[]};
      for (var run = 0; run < _runs + 1; run++) {
        for (final MapEntry(key: name, value: widget) in cases.entries) {
          await tester.pumpWidget(_host(widget));
          await tester.pump();
          final (t, _, moved) = await _timedOpen(
            tester,
            () => find.byKey(const ValueKey('ab')),
            () => find.text(marker),
          );
          if (run > 0) {
            ms[name]!.add(t);
            moves[name]!.add(moved);
          }
          await g4Settle(tester);
          await tester.tapAt(const Offset(4, 846));
          await g4Settle(tester);
        }
      }
      expect(tester.takeException(), isNull);
      // ignore: avoid_print
      print(
        'G4AB $count rows: ${[for (final name in cases.keys) '$name warm median ${_ms(_median(ms[name]!))} ms, moves ${_median(moves[name]!).toInt()} frames'].join(' | ')}',
      );
    });
  }

  // What the glass itself costs: the same popover layer, opaque or glass.
  testWidgets('A/B opaque panel vs glass panel', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = g4Screen * 3;
    addTearDown(tester.view.reset);
    Widget rows() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 8; i++)
          SizedBox(height: 44, child: Center(child: Text('Row $i'))),
      ],
    );
    final cases = <String, Widget Function(BuildContext)>{
      'opaque': (context) => Container(
        width: 361,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: rows(),
      ),
      'glass': (context) => GlassPopoverPanel(
        width: 361,
        borderRadius: BorderRadius.circular(16),
        child: rows(),
      ),
    };
    final ms = {for (final name in cases.keys) name: <double>[]};
    for (var run = 0; run < _runs + 1; run++) {
      for (final MapEntry(key: name, value: panel) in cases.entries) {
        await tester.pumpWidget(
          _host(
            Builder(
              builder: (context) => TextButton(
                key: const ValueKey('ab'),
                onPressed: () {
                  late OverlayEntry entry;
                  entry = OverlayEntry(
                    builder: (context) => GlassPopoverLayer(
                      left: 16,
                      top: 120,
                      onDismiss: () => entry.remove(),
                      child: Builder(builder: panel),
                    ),
                  );
                  Overlay.of(context).insert(entry);
                },
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.pump();
        final (t, _, _) = await _timedOpen(
          tester,
          () => find.byKey(const ValueKey('ab')),
          () => find.text('Row 7'),
        );
        if (run > 0) ms[name]!.add(t);
        await tester.tapAt(const Offset(4, 846));
        await g4Settle(tester);
      }
    }
    // ignore: avoid_print
    print(
      'G4AB panel: ${[for (final name in cases.keys) '$name warm median ${_ms(_median(ms[name]!))} ms'].join(' | ')}',
    );
  });
}
