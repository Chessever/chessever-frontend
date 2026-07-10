import 'dart:math' as math;

import 'package:cue/cue.dart';
import 'package:flutter/physics.dart';
import 'package:motor/motor.dart';

/// Shared motion presets for liquid-glass island chrome.
///
/// Apple Music search morph language:
/// - **Widen forward** — soft jelly spring with a hint of overshoot
/// - **Collapse back** — snappier, near-critical settle (decisive dismiss)
///
/// Stack:
/// - **motor** [Motion] — continuous values (scroll scale, morph progress 0→1)
/// - **cue** [CueMotion] — boolean toggles ([Cue.onToggle] + [Act]s)
/// - **package** [searchMorphSpring] — [GlassTabBar.searchable] pill axes
///
/// All three share the same duration/bounce tokens so the morph feels like
/// one physical system rather than stacked independent easings.
abstract final class GlassMotion {
  // ── Shared physics tokens (motor ↔ cue ↔ package) ─────────────────────

  /// Open / widen settle time (Apple Music: unhurried jelly).
  static const Duration widenDuration = Duration(milliseconds: 520);

  /// Close / collapse settle time (faster, decisive).
  static const Duration collapseDuration = Duration(milliseconds: 360);

  /// Forward bounce — soft overshoot without carnival wobble.
  static const double widenBounce = 0.11;

  /// Reverse bounce — tiny residual so dismiss still feels springy.
  static const double collapseBounce = 0.04;

  // ── motor: continuous ─────────────────────────────────────────────────

  /// Horizontal / progress widen (0 → 1).
  static const Motion widen = CupertinoMotion.smooth(
    duration: widenDuration,
    extraBounce: widenBounce,
  );

  /// Progress collapse (1 → 0).
  static const Motion collapse = CupertinoMotion.snappy(
    duration: collapseDuration,
    extraBounce: collapseBounce,
  );

  /// Bottom-nav scroll minimize scale.
  static const Motion scrollChrome = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 220),
  );

  /// Shell scale settle (island pulse around expand).
  static const Motion shellPulse = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 480),
    extraBounce: 0.08,
  );

  /// Picks widen vs collapse [Motion] from search active direction.
  static Motion searchDirection(bool expanding) =>
      expanding ? widen : collapse;

  // ── cue: boolean morph acts ───────────────────────────────────────────

  /// Forward cue spring — same duration/bounce as [widen].
  static CueMotion get cueWiden => CueMotion.spring(
        duration: widenDuration,
        bounce: widenBounce,
      );

  /// Reverse cue spring — same duration/bounce as [collapse].
  static CueMotion get cueCollapse => CueMotion.spring(
        duration: collapseDuration,
        bounce: collapseBounce,
      );

  // ── package: GlassTabBar.searchable ───────────────────────────────────

  /// Spring handed to `GlassTabBar.searchable` so tab-shrink + search-widen
  /// axes share motor’s Cupertino widen physics.
  static final SpringDescription searchMorphSpring =
      const CupertinoMotion.smooth(
        duration: widenDuration,
        extraBounce: widenBounce,
      ).description;

  // ── progress helpers (motor builder output) ───────────────────────────

  /// Maps morph progress 0→1 to a slight scale around 1.0.
  static double shellScale(double progress, {double min = 0.96}) {
    return min + (1.0 - min) * progress.clamp(0.0, 1.0);
  }

  /// Mid-morph “inflate” — peaks at progress 0.5, settles to 1.0 at ends.
  ///
  /// Gives the island a liquid breathe while the package pill widens.
  static double morphBreathe(
    double progress, {
    double peak = 0.022,
  }) {
    final t = progress.clamp(0.0, 1.0);
    return 1.0 + peak * math.sin(t * math.pi);
  }

  /// Vertical lift (px) while search is open — floats the island slightly.
  static double morphLift(double progress, {double maxLift = 3.5}) {
    final t = progress.clamp(0.0, 1.0);
    // Smoothstep for soft in/out.
    final s = t * t * (3.0 - 2.0 * t);
    return -maxLift * s;
  }
}
