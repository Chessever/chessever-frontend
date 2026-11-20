import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class AppBarIcons extends StatelessWidget {
  final VoidCallback onTap;
  final String image;
  final EdgeInsetsGeometry? padding;

  /// False drops the tile: the bare glyph on a 44pt tap target, with no ink
  /// splash that would draw a box around it on press.
  final bool boxed;

  /// Bare only: see [AppBarIconSurface.glyphShift].
  final double glyphShift;

  const AppBarIcons({
    super.key,
    required this.image,
    required this.onTap,
    this.padding,
    this.boxed = true,
    this.glyphShift = 0,
  });

  @override
  Widget build(BuildContext context) {
    final surface = AppBarIconSurface(
      padding: padding,
      boxed: boxed,
      glyphShift: glyphShift,
      // The bundled glyphs (three-dots etc.) ship with a white fill so
      // they read on the dark `surface`. In light theme that becomes
      // white-on-white and the button disappears, so we recolour to
      // `iconPrimary`. Dark theme keeps the asset's original fill.
      child: SvgPicture.asset(
        image,
        colorFilter: context.isLightTheme
            ? ColorFilter.mode(context.colors.iconPrimary, BlendMode.srcIn)
            : null,
      ),
    );
    if (!boxed) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: surface,
      );
    }
    return InkWell(onTap: onTap, child: surface);
  }
}

/// The common surface of the header's view, menu and tree controls.
class AppBarIconSurface extends StatelessWidget {
  const AppBarIconSurface({
    super.key,
    required this.child,
    this.padding,
    this.boxed = true,
    this.glyphShift = 0,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// False keeps the glyph's size and inset but drops the filled tile, and
  /// centres it in a square of at least [minTapTarget].
  final bool boxed;

  /// Bare only: how far the glyph is drawn toward the end edge (negative:
  /// toward the start) inside a tap target that does not move. Lets a glyph
  /// sit close to a neighbour while both targets stay whole, side by side.
  final double glyphShift;

  /// The smallest side of a bare control's tap target.
  static const double minTapTarget = 44;

  /// The glyph's box (the tile, when boxed).
  static double get glyphWidth => 32.w;
  static double get glyphHeight => 32.h;

  /// A bare control's tap target, across.
  static double get bareWidth => math.max(minTapTarget, glyphWidth);

  /// How far a bare control's tap target reaches past each side of the tile
  /// it replaces. A row that gives this back from its gaps keeps every glyph
  /// exactly where it was.
  static double get bareReach => (bareWidth - glyphWidth) / 2;

  @override
  Widget build(BuildContext context) {
    final glyph = Container(
      height: glyphHeight,
      width: glyphWidth,
      padding: padding ?? EdgeInsets.all(6.sp),
      decoration: boxed
          ? BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(4.br),
            )
          : null,
      child: child,
    );
    if (boxed) return glyph;
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return SizedBox(
      width: bareWidth,
      height: math.max(minTapTarget, glyphHeight),
      child: Center(
        child: glyphShift == 0
            ? glyph
            : Transform.translate(
                offset: Offset(rtl ? -glyphShift : glyphShift, 0),
                child: glyph,
              ),
      ),
    );
  }
}
