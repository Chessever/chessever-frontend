import 'package:chessever2/watch/core/watch_wrist_flick.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feeds (x, y, z) samples 20 ms apart, as the watch's game-rate gyroscope
/// does, and collects every non-zero step.
List<int> run(
  WatchWristFlick d,
  List<(double, double, double)> s, [
  int at = 0,
]) {
  final steps = <int>[];
  for (var i = 0; i < s.length; i++) {
    final (x, y, z) = s[i];
    final r = d.add(x, y, z, Duration(milliseconds: at + i * 20));
    if (r != 0) steps.add(r);
  }
  return steps;
}

void main() {
  const outward = [
    (1.0, 0.3, 0.2),
    (7.5, 1.0, 0.8),
    (2.0, 0.5, 0.3),
    (-5.0, 0.8, 0.6),
    (-0.5, 0.1, 0.1),
  ];

  test('outward-then-back flick steps forward, inward-first steps back', () {
    expect(run(WatchWristFlick(), outward), [1]);
    expect(
      run(WatchWristFlick(), [for (final (x, y, z) in outward) (-x, y, z)]),
      [-1],
    );
  });

  test('raising the wrist to read is slow and one-way: no step', () {
    expect(
      run(WatchWristFlick(), [for (var i = 0; i < 30; i++) (2.5, 0.8, 0.5)]),
      isEmpty,
    );
  });

  test('walking sway stays under the threshold', () {
    expect(
      run(WatchWristFlick(), [
        for (var i = 0; i < 100; i++) (i.isEven ? 3.0 : -3.0, 2.0, 1.5),
      ]),
      isEmpty,
    );
  });

  test('a spike that never snaps back within the window does nothing', () {
    expect(
      run(WatchWristFlick(), [
        (7.5, 1.0, 0.5),
        for (var i = 0; i < 20; i++) (0.2, 0.1, 0.1),
        (-5.0, 0.5, 0.5),
      ]),
      isEmpty,
    );
  });

  test('a swing spread across axes is not a flick', () {
    expect(
      run(WatchWristFlick(), [(7.5, 6.0, 1.0), (-5.0, 4.5, 1.0)]),
      isEmpty,
    );
  });

  test('cooldown absorbs the settle after a flick', () {
    final d = WatchWristFlick();
    expect(run(d, [...outward, ...outward]), [1]);
    expect(run(d, outward, 2000), [1]);
  });
}
