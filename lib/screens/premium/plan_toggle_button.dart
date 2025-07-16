import 'dart:ui';

import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/widgets.dart';

class PlanToggleButton extends StatelessWidget {
  final bool isSelected;
  final String text;
  final VoidCallback onTap;

  const PlanToggleButton({
    required this.isSelected,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20.sp, vertical: 8.sp),
        decoration: BoxDecoration(
          // color: isSelected ? kBoardColorGrey : Colors.transparent,
          border: Border.all(color: isSelected ? kBlackColor : kBoardColorGrey),
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? kBoardColorGrey : kWhiteColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
