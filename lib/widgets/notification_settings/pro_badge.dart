import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Small pill badge marking a feature as premium-only ("PRO").
class ProBadge extends StatelessWidget {
  const ProBadge({super.key, this.label = 'PRO'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
      decoration: BoxDecoration(
        color: kPrimaryColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4.br),
        border: Border.all(color: kPrimaryColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: AppTypography.textSmRegular.copyWith(
          color: kPrimaryColor,
          fontSize: 9.f,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
