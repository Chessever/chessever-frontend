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
        expandRange: 36.0,
      );

      mapper.applyScrollDelta(64.0); // fully minimized
      expect(mapper.progress, 1.0);
      expect(mapper.scale, closeTo(0.72, 1e-9));

      // Half expand range
      mapper.applyScrollDelta(-18.0);
      expect(mapper.progress, closeTo(0.5, 1e-9));
      expect(
        mapper.scale,
        closeTo(ScrollChromeMapper.scaleForProgress(0.5, minScale: 0.72), 1e-9),
      );

      // Rest of expand → full size
      mapper.applyScrollDelta(-18.0);
      expect(mapper.progress, 0.0);
      expect(mapper.scale, 1.0);
      expect(mapper.isMinimized, isFalse);
    });

    test('at top-most position forces full expand even if minimized', () {
      final mapper = ScrollChromeMapper();
      mapper.applyScrollDelta(100);
      expect(mapper.progress, 1.0);

      // Settled at top (pixels == minScrollExtent) — grow back fully.
      mapper.applyScroll(
        pixels: 0,
        minScrollExtent: 0,
        delta: null,
      );
      expect(mapper.progress, 0.0);
      expect(mapper.scale, 1.0);
      expect(mapper.isMinimized, isFalse);
    });

    test('overscroll past top still forces expand', () {
      final mapper = ScrollChromeMapper();
      mapper.applyScrollDelta(80);
      // iOS rubber-band: pixels can go below minScrollExtent.
      mapper.applyScroll(
        pixels: -12,
        minScrollExtent: 0,
        delta: -4,
      );
      expect(mapper.progress, 0.0);
      expect(mapper.scale, 1.0);
    });

    test('scroll-up away from top expands via delta without full reset', () {
      final mapper = ScrollChromeMapper(expandRange: 36);
      mapper.applyScrollDelta(64); // minimized
      mapper.applyScroll(
        pixels: 400,
        minScrollExtent: 0,
        delta: -18,
      );
      expect(mapper.progress, closeTo(0.5, 1e-9));
      expect(mapper.isMinimized, isTrue);
    });

    test('top-edge wins over positive (down) delta', () {
      final mapper = ScrollChromeMapper();
      mapper.applyScrollDelta(64);
      // Still at top — must stay expanded even if a spurious +delta arrives.
      mapper.applyScroll(
        pixels: 0,
        minScrollExtent: 0,
        delta: 20,
      );
      expect(mapper.progress, 0.0);
    });

    test('isAtTop respects epsilon', () {
      expect(ScrollChromeMapper.isAtTop(0, 0), isTrue);
      expect(ScrollChromeMapper.isAtTop(0.5, 0, topEpsilon: 1.0), isTrue);
      expect(ScrollChromeMapper.isAtTop(2.0, 0, topEpsilon: 1.0), isFalse);
      expect(ScrollChromeMapper.isAtTop(-8, 0), isTrue);
    });

    test('nextProgressFromMetrics pure helper matches instance applyScroll', () {
      var progress = 1.0;
      final mapper = ScrollChromeMapper()..setProgress(1.0);

      progress = ScrollChromeMapper.nextProgressFromMetrics(
        current: progress,
        pixels: 0,
        minScrollExtent: 0,
        delta: 10,
      );
      mapper.applyScroll(pixels: 0, minScrollExtent: 0, delta: 10);
      expect(mapper.progress, 0.0);
      expect(progress, 0.0);

      progress = ScrollChromeMapper.nextProgressFromMetrics(
        current: 0.8,
        pixels: 200,
        minScrollExtent: 0,
        delta: -18,
        expandRange: 36,
      );
      mapper.setProgress(0.8);
      mapper.applyScroll(pixels: 200, minScrollExtent: 0, delta: -18);
      expect(mapper.progress, closeTo(progress, 1e-9));
      expect(progress, closeTo(0.3, 1e-9));
    });

    test('clamps progress at 0 and 1 under large deltas', () {
      final mapper = ScrollChromeMapper();
      mapper.applyScrollDelta(10000);
      expect(mapper.progress, 1.0);
      mapper.applyScrollDelta(-10000);
      expect(mapper.progress, 0.0);
    });

    test('zero delta is a no-op when not at top', () {
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
