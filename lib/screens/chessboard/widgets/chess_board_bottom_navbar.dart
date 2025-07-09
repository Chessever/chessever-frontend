import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';

class ChessBoardBottomNavbar extends StatelessWidget {
  final String svgPath;
  final Function() onPressed;
  const ChessBoardBottomNavbar({
    super.key,
    required this.svgPath,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: SizedBox(
        width: 20.w,
        height: 15.w,
        // padding: EdgeInsets.all(16.sp),
        child: SvgWidget(
          svgPath,
          height: 24,
          width: 24,
          colorFilter: ColorFilter.mode(
            onPressed != null ? Colors.white : Colors.white.withOpacity(0.3),
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
