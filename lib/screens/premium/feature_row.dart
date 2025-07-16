import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/svg.dart';

class FeatureRow extends StatelessWidget {
  final String icon;
  final String text;
  final Color iconColor;

  const FeatureRow({
    required this.icon,
    required this.text,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SvgPicture.asset(icon, width: 16.w, height: 16.h),
        SizedBox(width: 5.w),
        Expanded(
          child: Text(
            text,
            style: AppTypography.textSmBold.copyWith(color: kBoardColorGrey),
          ),
        ),
      ],
    );
  }
}
