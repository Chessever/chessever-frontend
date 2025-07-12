import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';

class ChessBoardBottomNavbar extends StatelessWidget {
  final String svgPath;
  final VoidCallback? onPressed;

  const ChessBoardBottomNavbar({
    super.key,
    required this.svgPath,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: EdgeInsets.all(8.sp),
        child: SvgWidget(
          svgPath,
          height: 24.h,
          width: 24.w,
          colorFilter: ColorFilter.mode(
            onPressed != null ? kWhiteColor : kWhiteColor70,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
