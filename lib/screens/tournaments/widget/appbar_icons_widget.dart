import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class AppBarIcons extends StatelessWidget {
  final Function() onTap;
  final String image;

  const AppBarIcons({super.key, required this.image, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 5.sp),
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(4.br),
        ),
        child: SvgPicture.asset(image, width: 19.w, height: 19.h),
      ),
    );
  }
}
