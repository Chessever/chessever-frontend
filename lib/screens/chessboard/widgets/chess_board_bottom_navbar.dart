import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';

class ChessSvgBottomNavbar extends StatelessWidget {
  final String svgPath;
  final VoidCallback? onPressed;

  const ChessSvgBottomNavbar({
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

class ChessSvgBottomNavbarWithLongPress extends StatelessWidget {
  final String svgPath;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;

  const ChessSvgBottomNavbarWithLongPress({
    super.key,
    required this.svgPath,
    required this.onPressed,
    this.onLongPressStart,
    this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      onLongPressStart:
          onLongPressStart != null ? (_) => onLongPressStart!() : null,
      onLongPressEnd: onLongPressEnd != null ? (_) => onLongPressEnd!() : null,
      onLongPressCancel: onLongPressEnd,
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

class ChessIconBottomNavbar extends StatelessWidget {
  final IconData iconData;
  final VoidCallback? onPressed;

  const ChessIconBottomNavbar({
    super.key,
    required this.iconData,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: EdgeInsets.all(8.sp),
        child: Icon(iconData, size: 24.ic),
      ),
    );
  }
}
