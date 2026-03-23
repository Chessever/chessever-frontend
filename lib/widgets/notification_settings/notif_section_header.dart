import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Uppercase grey section label used between groups of settings tiles.
/// e.g. "ALERTS", "LIBRARY", "UPDATES"
class NotifSectionHeader extends StatelessWidget {
  const NotifSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h, left: 2.sp),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.textSmRegular.copyWith(
          color: const Color(0xFF888888),
          fontSize: 10.f,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
