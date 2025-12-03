/// Droplet-style animation curves for snappy, bubbly dropdown interactions
/// Uses physics-based spring motion with water droplet surface tension feel
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Collection of spring curve presets optimized for droplet-like dropdown animations
/// Creates snappy, responsive feel with organic elastic settling
class DropletCurves {
  DropletCurves._();

  /// Ultra-snappy pop curve for initial dropdown appearance
  /// High stiffness + low mass = instant response
  /// Slight overshoot (1.02x) creates satisfying "pop" effect
  static const Curve openPop = _DropletSpringCurve(
    stiffness: 520.0,
    damping: 26.0,
    mass: 0.75,
  );

  /// Bubbly settle curve for elastic snap-back after pop
  /// Lower damping creates 2-3 visible bounces for playful feel
  static const Curve openSettle = _DropletSpringCurve(
    stiffness: 380.0,
    damping: 16.0,
    mass: 1.0,
  );

  /// Organic border morph curve for water droplet effect
  /// Very low damping creates wobble/oscillation
  /// Higher mass adds momentum for organic movement
  static const Curve morphWobble = _DropletSpringCurve(
    stiffness: 280.0,
    damping: 12.0,
    mass: 1.3,
  );

  /// Surface tension settle - how the blob snaps back to clean shape
  /// Medium stiffness for natural tension feel
  static const Curve surfaceTension = _DropletSpringCurve(
    stiffness: 340.0,
    damping: 20.0,
    mass: 1.0,
  );

  /// Crisp close curve for rapid dropdown dismissal
  /// High stiffness + high damping = fast without bounce
  static const Curve close = _DropletSpringCurve(
    stiffness: 550.0,
    damping: 40.0,
    mass: 0.85,
  );

  /// Quick fade curve - for opacity animations
  /// Faster than default but still smooth
  static const Curve quickFade = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Inward pull curve for closing animation
  /// Subtle inward bulge before collapse
  static const Curve inwardPull = _DropletSpringCurve(
    stiffness: 400.0,
    damping: 30.0,
    mass: 1.0,
  );
}

/// Physics-based spring curve for droplet animations
/// Simulates real spring behavior with stiffness, damping, and mass
/// Output is clamped to [0, 1] for compatibility with Flutter's animation system
class _DropletSpringCurve extends Curve {
  final double stiffness;
  final double damping;
  final double mass;

  const _DropletSpringCurve({
    required this.stiffness,
    required this.damping,
    required this.mass,
  });

  @override
  double transformInternal(double t) {
    if (t == 0.0) return 0.0;
    if (t == 1.0) return 1.0;

    // Calculate spring physics parameters
    final omega = math.sqrt(stiffness / mass);
    final zeta = damping / (2 * mass * omega);

    double result;
    if (zeta < 1.0) {
      // Underdamped: creates bounce/overshoot (the droplet effect)
      final omegaD = omega * math.sqrt(1.0 - zeta * zeta);
      final envelope = math.exp(-zeta * omega * t);
      final phase = math.atan2(zeta * omega, omegaD);
      result = 1.0 - envelope * math.cos(omegaD * t + phase) / math.cos(phase);
    } else if (zeta == 1.0) {
      // Critically damped: fastest without overshoot
      final r = omega;
      result = 1.0 - math.exp(-r * t) * (1.0 + r * t);
    } else {
      // Overdamped: smooth approach
      final sqrtTerm = math.sqrt(zeta * zeta - 1.0);
      final r1 = omega * (zeta - sqrtTerm);
      final r2 = omega * (zeta + sqrtTerm);
      final c1 = r2 / (r2 - r1);
      final c2 = -r1 / (r2 - r1);
      result = 1.0 - (c1 * math.exp(-r1 * t) + c2 * math.exp(-r2 * t));
    }

    // Clamp to [0, 1] to prevent Flutter assertion errors when used with Interval
    return result.clamp(0.0, 1.0);
  }
}

/// Animation timing constants for droplet dropdown animations
class DropletTiming {
  DropletTiming._();

  /// Total open animation duration
  static const Duration openTotal = Duration(milliseconds: 350);

  /// Fast scale pop phase duration
  static const Duration scalePop = Duration(milliseconds: 180);

  /// Border morph wave duration
  static const Duration morphWave = Duration(milliseconds: 300);

  /// Opacity fade-in duration (quick)
  static const Duration fadeIn = Duration(milliseconds: 80);

  /// Total close animation duration (faster than open)
  static const Duration closeTotal = Duration(milliseconds: 200);

  /// Scale contract duration
  static const Duration scaleContract = Duration(milliseconds: 150);

  /// Opacity fade-out duration
  static const Duration fadeOut = Duration(milliseconds: 120);
}

/// Morph intensity presets for different dropdown sizes
class DropletMorphIntensity {
  DropletMorphIntensity._();

  /// Subtle morph for small dropdowns (badges, chips)
  static const double subtle = 0.04;

  /// Normal morph for standard dropdowns
  static const double normal = 0.06;

  /// Pronounced morph for larger panels
  static const double pronounced = 0.08;

  /// Maximum bulge ratio (as fraction of smaller dimension)
  static const double maxBulge = 0.10;
}
