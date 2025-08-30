import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class AppBarIcons extends StatelessWidget {
  final Function() onTap;
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
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(4.br),
        ),
        child: SvgPicture.asset(image),
      ),
    );
  }
}
