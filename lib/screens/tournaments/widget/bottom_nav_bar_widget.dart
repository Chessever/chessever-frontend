import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';

class BottomNavBarWidget extends StatelessWidget {
  const BottomNavBarWidget({
    required this.isSelected,
    required this.onTap,
    required this.svgIcon,
    required this.title,
    required this.width,
    super.key,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final String svgIcon;
  final String title;
  final double width;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      splashColor: kWhiteColor,
      onTap: onTap,
      child: Container(
        width: width,
        padding: EdgeInsets.symmetric(vertical: 8.sp),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgWidget(
              height: 20.h,
              width: 20.w,
              svgIcon,
              colorFilter: ColorFilter.mode(
                isSelected ? kWhiteColor : kDarkGreyColor,
                BlendMode.srcIn,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              title,
              style: AppTypography.textMdMedium.copyWith(
                color: isSelected ? kWhiteColor : kDarkGreyColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
