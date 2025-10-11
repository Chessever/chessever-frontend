import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart';

class SimpleSearchBar extends StatelessWidget {
  const SimpleSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onCloseTap,
    required this.onOpenFilter,
    this.hintText = '',
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCloseTap;
  final VoidCallback? onOpenFilter;
  final String hintText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 4.sp),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedRotation(
            turns: focusNode.hasFocus ? 0.25 : 0,
            duration: const Duration(milliseconds: 300),
            child: SvgWidget(
              SvgAsset.searchIcon,
              height: 20.h,
              width: 20.w,
              colorFilter: ColorFilter.mode(
                focusNode.hasFocus ? kPrimaryColor : Colors.grey[400]!,
                BlendMode.srcIn,
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              onChanged: onChanged,
              style: AppTypography.textMdRegular,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: AppTypography.textMdRegular,
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          // Show clear icon only when search bar has focus
          if (focusNode.hasFocus) ...[
            GestureDetector(
              onTap: onCloseTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: EdgeInsets.all(4.sp),
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close, size: 16.ic, color: kWhiteColor),
              ),
            ),
          ],

          if (onOpenFilter != null) ...[
            SizedBox(width: 8.w),
            GestureDetector(
              onTap: onOpenFilter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: EdgeInsets.all(8.sp),
                decoration: BoxDecoration(
                  color: kDarkGreyColor.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8.br),
                ),
                child: SvgWidget(
                  SvgAsset.listFilterIcon,
                  height: 20.h,
                  width: 20.w,
                  colorFilter: ColorFilter.mode(
                    focusNode.hasFocus ? kPrimaryColor : Colors.grey[400]!,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
