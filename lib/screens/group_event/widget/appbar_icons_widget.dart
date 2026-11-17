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

  const AppBarIcons({
    super.key,
    required this.image,
    required this.onTap,
    this.padding,
    this.boxed = true,
  });

  @override
  Widget build(BuildContext context) {
    final surface = AppBarIconSurface(
      padding: padding,
      boxed: boxed,
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
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// False keeps the glyph's size and inset but drops the filled tile, and
  /// centres it in a square of at least [minTapTarget].
  final bool boxed;

  /// The smallest side of a bare control's tap target.
  static const double minTapTarget = 44;

  /// How far a bare control's tap target reaches past each side of the tile
  /// it replaces. A row that gives this back from its gaps keeps every glyph
  /// exactly where it was.
  static double get bareReach => (math.max(minTapTarget, 32.w) - 32.w) / 2;

  @override
  Widget build(BuildContext context) {
    final glyph = Container(
      height: 32.h,
      width: 32.w,
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
    return SizedBox(
      width: math.max(minTapTarget, 32.w),
      height: math.max(minTapTarget, 32.h),
      child: Center(child: glyph),
    );
  }
}
