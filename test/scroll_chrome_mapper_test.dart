import 'package:chessever2/widgets/liquid_glass/scroll_chrome_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScrollChromeMapper', () {
    test('starts fully expanded (scale 1.0, progress 0)', () {
      final mapper = ScrollChromeMapper();
      expect(mapper.progress, 0.0);
      expect(mapper.scale, 1.0);
      expect(mapper.isMinimized, isFalse);
    });

    test('scrolling down increases progress and shrinks scale', () {
      final mapper = ScrollChromeMapper(
        minScale: 0.72,
        collapseRange: 64.0,
      );

      // Half the collapse range → progress 0.5
      final scaleMid = mapper.applyScrollDelta(32.0);
      expect(mapper.progress, closeTo(0.5, 1e-9));
      expect(
        scaleMid,
        closeTo(ScrollChromeMapper.scaleForProgress(0.5, minScale: 0.72), 1e-9),
      );
      expect(mapper.isMinimized, isTrue);

      // Rest of collapse range → fully minimized
      final scaleMin = mapper.applyScrollDelta(32.0);
      expect(mapper.progress, 1.0);
      expect(scaleMin, closeTo(0.72, 1e-9));
    });

    test('scrolling up restores progress and expands scale', () {
      final mapper = ScrollChromeMapper(
        minScale: 0.72,
        collapseRange: 64.0,
        expandRange: 48.0,
      );

      mapper.applyScrollDelta(64.0); // fully minimized
      expect(mapper.progress, 1.0);
      expect(mapper.scale, closeTo(0.72, 1e-9));

      // Half expand range
      mapper.applyScrollDelta(-24.0);
      expect(mapper.progress, closeTo(0.5, 1e-9));
      expect(
        mapper.scale,
        closeTo(ScrollChromeMapper.scaleForProgress(0.5, minScale: 0.72), 1e-9),
      );

      // Rest of expand → full size
      mapper.applyScrollDelta(-24.0);
      expect(mapper.progress, 0.0);
      expect(mapper.scale, 1.0);
      expect(mapper.isMinimized, isFalse);
    });

    test('clamps progress at 0 and 1 under large deltas', () {
      final mapper = ScrollChromeMapper();
      mapper.applyScrollDelta(10000);
      expect(mapper.progress, 1.0);
      mapper.applyScrollDelta(-10000);
      expect(mapper.progress, 0.0);
    });

    test('zero delta is a no-op', () {
      final mapper = ScrollChromeMapper();
      mapper.applyScrollDelta(32.0);
      final p = mapper.progress;
      final s = mapper.scale;
      mapper.applyScrollDelta(0);
      expect(mapper.progress, p);
      expect(mapper.scale, s);
    });

    test('reset returns to expanded', () {
      final mapper = ScrollChromeMapper();
      mapper.applyScrollDelta(80);
      mapper.reset();
      expect(mapper.progress, 0.0);
      expect(mapper.scale, 1.0);
    });

    test('pure nextProgress matches instance applyScrollDelta', () {
      var progress = 0.0;
      final mapper = ScrollChromeMapper(collapseRange: 80, expandRange: 40);

      for (final delta in <double>[10, 20, -5, 40, -30, -50, 15]) {
        progress = ScrollChromeMapper.nextProgress(
          current: progress,
          delta: delta,
          collapseRange: 80,
          expandRange: 40,
        );
        mapper.applyScrollDelta(delta);
        expect(mapper.progress, closeTo(progress, 1e-9));
        expect(
          mapper.scale,
          closeTo(
            ScrollChromeMapper.scaleForProgress(progress, minScale: 0.72),
            1e-9,
          ),
        );
      }
    });

    test('scaleForProgress is linear between 1 and minScale', () {
      expect(ScrollChromeMapper.scaleForProgress(0, minScale: 0.8), 1.0);
      expect(ScrollChromeMapper.scaleForProgress(1, minScale: 0.8), 0.8);
      expect(
        ScrollChromeMapper.scaleForProgress(0.25, minScale: 0.8),
        closeTo(0.95, 1e-9),
      );
    });
  });
}
