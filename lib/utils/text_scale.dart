import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Largest system text scale the app honours.
///
/// iOS's standard Text Size steps top out at 1.35 (xxxLarge) and Android's at
/// 2.0; the iOS accessibility sizes reach ~3.1. Every standard step up to here
/// renders as the user asked. Above it, dense chess surfaces (boards, clocks,
/// game cards, standings) cannot keep their structure, so the app caps the
/// scale at the root ([AppTextScaleCap]). At the default size (1.0) nothing
/// changes.
const double kMaxAppTextScale = 1.5;

/// Tighter cap for compact, information-dense pieces that sit in fixed
/// geometry: board coordinates, clocks, score badges, tiny status chips.
const double kDenseTextScale = 1.2;

extension TextScaleContext on BuildContext {
  /// How much larger than the default the user's text renders, never below
  /// 1.0.
  ///
  /// Multiply a fixed extent that holds text (a row height, a chip height)
  /// by this so the box grows with its text. At the default text size it is
  /// exactly 1.0, so the default layout stays pixel-identical; smaller-than-
  /// default settings never shrink a box.
  double get textGrowth {
    final scaled = MediaQuery.textScalerOf(this).scale(14) / 14;
    return math.max(1.0, scaled);
  }

  /// [base] grown with the user's text size. Identity at the default size.
  double textExtent(double base) => base * textGrowth;

  /// The user's text scaler, for [TextPainter] measurements that must match
  /// what a [Text] widget in this context will actually paint.
  TextScaler get textScaler => MediaQuery.textScalerOf(this);
}

/// Caps text scaling for [child] at [maxScale].
///
/// Use on dense, fixed-geometry pieces where larger text cannot fit
/// (see [kDenseTextScale]). Identity whenever the user's scale is at or below
/// [maxScale], including the default size.
class CappedTextScale extends StatelessWidget {
  const CappedTextScale({
    super.key,
    this.maxScale = kDenseTextScale,
    required this.child,
  });

  final double maxScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxScale,
      child: child,
    );
  }
}

/// Root cap: applies [kMaxAppTextScale] to everything under the app's
/// navigator (routes, dialogs, sheets, overlays).
class AppTextScaleCap extends StatelessWidget {
  const AppTextScaleCap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kMaxAppTextScale,
      child: child,
    );
  }
}
