import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motor/motor.dart';

void main() {
  group('GlassMotion Apple Music widen tokens', () {
    test('widen is softer/longer than collapse', () {
      expect(
        GlassMotion.widenDuration.inMilliseconds,
        greaterThan(GlassMotion.collapseDuration.inMilliseconds),
      );
      expect(GlassMotion.widenBounce, greaterThan(GlassMotion.collapseBounce));
    });

    test('searchDirection picks widen vs collapse springs', () {
      expect(GlassMotion.searchDirection(true), same(GlassMotion.widen));
      expect(GlassMotion.searchDirection(false), same(GlassMotion.collapse));
      expect(GlassMotion.widen, isA<CupertinoMotion>());
      expect(GlassMotion.collapse, isA<CupertinoMotion>());
    });

    test('morphBreathe is identity at ends and peaks mid-way', () {
      expect(GlassMotion.morphBreathe(0), closeTo(1.0, 1e-9));
      expect(GlassMotion.morphBreathe(1), closeTo(1.0, 1e-9));
      expect(GlassMotion.morphBreathe(0.5), greaterThan(1.0));
    });

    test('morphLift is zero collapsed and negative when open', () {
      expect(GlassMotion.morphLift(0), 0);
      expect(GlassMotion.morphLift(1), lessThan(0));
    });

    test('shellScale interpolates min → 1', () {
      expect(GlassMotion.shellScale(0, min: 0.94), closeTo(0.94, 1e-9));
      expect(GlassMotion.shellScale(1, min: 0.94), closeTo(1.0, 1e-9));
    });

    test('package searchMorphSpring is derived from motor widen', () {
      final spring = GlassMotion.searchMorphSpring;
      expect(spring.mass, greaterThan(0));
      expect(spring.stiffness, greaterThan(0));
      expect(spring.damping, greaterThan(0));
    });
  });
}
