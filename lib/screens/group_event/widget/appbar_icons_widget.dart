import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class AppBarIcons extends StatelessWidget {
  final VoidCallback onTap;
  final String image;
  final EdgeInsetsGeometry? padding;

  const AppBarIcons({
    super.key,
    required this.image,
    required this.onTap,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 32.h,
        width: 32.w,
        padding: padding ?? EdgeInsets.all(6.sp),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(4.br),
        ),
        // The bundled glyphs (three-dots etc.) ship with a white fill so
        // they read on the dark `surface`. In light theme that becomes
        // white-on-white and the button disappears, so we recolour to
        // `iconPrimary`. Dark theme keeps the asset's original fill.
        child: SvgPicture.asset(
          image,
          colorFilter: context.isLightTheme
              ? ColorFilter.mode(
                  context.colors.iconPrimary,
                  BlendMode.srcIn,
                )
              : null,
        ),
      ),
    );
  }
}
