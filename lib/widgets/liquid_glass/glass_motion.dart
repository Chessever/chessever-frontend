import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

/// Shared motion presets for liquid-glass island chrome.
///
/// - **motor** drives app-owned continuous values (scroll-shrink scale,
///   island width factors) via [SingleMotionBuilder] / [Motion].
/// - **cue** drives boolean morphs (search expand / collapse) with
///   [Cue.onToggle] + [Act.sizedClip] for Apple Music–style horizontal widen.
/// - [searchMorphSpring] is passed into `GlassTabBar.searchable` so the
///   package pill morph matches the same physical feel.
abstract final class GlassMotion {
  /// Horizontal search widen (forward) — soft jelly, slight overshoot.
  static const Motion widen = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 480),
    extraBounce: 0.12,
  );

  /// Search collapse (back) — snappier settle so dismiss feels decisive.
  static const Motion collapse = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 340),
    extraBounce: 0.05,
  );

  /// Bottom-nav scroll minimize scale (down-shrink / up-restore).
  static const Motion scrollChrome = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 220),
  );

  /// Micro scale pulse when search toggles (outer shell).
  static const Motion shellPulse = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 280),
    extraBounce: 0.08,
  );

  /// Spring handed to liquid_glass_widgets searchable morph.
  ///
  /// Tuned for Apple Music “widening forward / snappy back” feel:
  /// lower damping than package default (30) for a hint of jelly overshoot.
  static const SpringDescription searchMorphSpring = SpringDescription(
    mass: 1.0,
    stiffness: 300.0,
    damping: 24.0,
  );

  /// Maps [progress] 0→1 to a slight scale around 1.0 for shell pulse.
  static double shellScale(double progress, {double min = 0.985}) {
    return min + (1.0 - min) * progress.clamp(0.0, 1.0);
  }
}
