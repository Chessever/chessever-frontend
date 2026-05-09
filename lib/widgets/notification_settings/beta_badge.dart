import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Small pill badge — used to mark features as "BETA" or similar.
class BetaBadge extends StatelessWidget {
  const BetaBadge({super.key, this.label = 'BETA'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(4.br),
      ),
      child: Text(
        label,
        style: AppTypography.textSmRegular.copyWith(
          color: const Color(0xFF9E9E9E),
          fontSize: 9.f,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
