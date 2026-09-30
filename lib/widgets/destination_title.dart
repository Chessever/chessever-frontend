import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// A bare destination mark and its name, centered together as one unit.
class DestinationTitle extends StatelessWidget {
  const DestinationTitle({super.key, required this.title, required this.icon});

  final String title;
  final Widget icon;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      ExcludeSemantics(
        child: IconTheme(
          data: IconThemeData(size: 22.sp, color: context.colors.iconPrimary),
          child: SizedBox.square(dimension: 22.sp, child: icon),
        ),
      ),
      SizedBox(width: 8.w),
      Flexible(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.textMdMedium.copyWith(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}
