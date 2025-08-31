import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';

class EmptyWidget extends StatelessWidget {
  const EmptyWidget({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgWidget(SvgAsset.infoIcon, height: 24.h, width: 24.w),
        SizedBox(height: 12.h),
        Text(
          title,
          style: AppTypography.textXsRegular.copyWith(color: kWhiteColor70),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
