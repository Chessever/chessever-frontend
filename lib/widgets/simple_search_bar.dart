import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart';

class SimpleSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final Function(String)? onChanged;
  final String hintText;
  final bool autofocus;
  final VoidCallback? onFilterTap;
  final VoidCallback? onMenuTap;

  const SimpleSearchBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.hintText = 'Search tournaments or players',
    this.autofocus = false,
    this.onFilterTap,
    this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        height: 40.h,
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(4.br),
        ),
        padding: EdgeInsets.only(
          left: 6.sp,
          right: 6.sp,
          top: 4.sp,
          bottom: 4.sp,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Search icon aligned with text
            Padding(
              padding: EdgeInsets.only(left: 6.sp),
              child: SvgWidget(SvgAsset.searchIcon, height: 16.h, width: 16.w),
            ),
            SizedBox(width: 4.w),

            // Text field
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                autofocus: autofocus,
                textAlignVertical: TextAlignVertical.center,
                style: AppTypography.textXsRegular.copyWith(color: kWhiteColor),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: AppTypography.textXsRegular.copyWith(
                    color: kWhiteColor70,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),

            // Filter icon
            if (onFilterTap != null || onMenuTap != null)
              Padding(
                padding: EdgeInsets.only(right: 10.sp),
                child: InkWell(
                  onTap: onFilterTap ?? onMenuTap,
                  borderRadius: BorderRadius.zero,
                  child: SvgWidget(
                    SvgAsset.listFilterIcon,
                    height: 24.h,
                    width: 24.w,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
