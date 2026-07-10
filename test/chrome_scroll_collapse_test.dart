import 'package:chessever2/widgets/liquid_glass/chrome_scroll_collapse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChromeScrollCollapse', () {
    test('starts expanded', () {
      final c = ChromeScrollCollapse();
      expect(c.expanded, isTrue);
    });

    test('scroll down past threshold collapses to chips', () {
      final c = ChromeScrollCollapse(collapseThreshold: 36);
      expect(
        c.applyScrollUpdate(pixels: 10, minScrollExtent: 0, delta: 20),
        isFalse,
      );
      expect(c.expanded, isTrue);
      expect(
        c.applyScrollUpdate(pixels: 40, minScrollExtent: 0, delta: 20),
        isTrue,
      );
      expect(c.expanded, isFalse);
    });

    test('scroll up past threshold expands again', () {
      final c = ChromeScrollCollapse(
        collapseThreshold: 36,
        expandThreshold: 28,
      );
      c.applyScrollUpdate(pixels: 100, minScrollExtent: 0, delta: 50);
      expect(c.expanded, isFalse);

      expect(
        c.applyScrollUpdate(pixels: 80, minScrollExtent: 0, delta: -15),
        isFalse,
      );
      expect(
        c.applyScrollUpdate(pixels: 50, minScrollExtent: 0, delta: -20),
        isTrue,
      );
      expect(c.expanded, isTrue);
    });

    test('at top always forces expand', () {
      final c = ChromeScrollCollapse();
      c.applyScrollUpdate(pixels: 200, minScrollExtent: 0, delta: 80);
      expect(c.expanded, isFalse);

      expect(
        c.applyScrollUpdate(pixels: 0, minScrollExtent: 0, delta: 10),
        isTrue,
      );
      expect(c.expanded, isTrue);
    });

    test('reset restores expanded', () {
      final c = ChromeScrollCollapse();
      c.applyScrollUpdate(pixels: 100, minScrollExtent: 0, delta: 80);
      expect(c.expanded, isFalse);
      c.reset();
      expect(c.expanded, isTrue);
    });
  });
}
