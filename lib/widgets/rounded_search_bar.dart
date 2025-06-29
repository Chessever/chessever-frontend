import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/filter_popup.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart'; // Import for gradient and colors

class RoundedSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final Function(String)? onChanged;
  final String hintText;
  final bool autofocus;
  final VoidCallback? onFilterTap;
  final VoidCallback? onProfileTap;
  final String profileInitials;

  const RoundedSearchBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.hintText = 'Search tournaments or players',
    this.autofocus = false,
    this.onFilterTap,
    this.onProfileTap,
    this.profileInitials = 'VD',
  });

  void _showFilterPopup(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => const FilterPopup(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Profile circle with initials - outside the search bar background
        GestureDetector(
          onTap: onProfileTap,
          child: Container(
            width: 32.w,
            height: 32.h,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: kProfileInitialsGradient,
            ),
            child: Center(
              child: Text(
                profileInitials.toUpperCase(),
                style: TextStyle(
                  color: kBlack2Color, // Changed to kBlack2Color as requested
                  fontWeight: FontWeight.bold,
                  fontSize: 12.f,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 20.w), // Adjusted spacing to match Figma design (was 8)
        // Search bar container - starts after the profile avatar
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: kBlack2Color,
              // Using theme constant instead of hardcoded 0xFF1A1A1C
              borderRadius: BorderRadius.circular(
                4.br,
              ), // Changed to 4 as requested
            ),
            padding: EdgeInsets.symmetric(horizontal: 4.sp, vertical: 8.sp),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: 6.sp),
                  child: SvgWidget(
                    SvgAsset.searchIcon,
                    height: 16.h,
                    width: 16.w,
                  ),
                ),
                SizedBox(width: 4.w),

                // Text field
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    autofocus: autofocus,
                    textAlignVertical: TextAlignVertical.center,
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor,
                    ),
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
                if (onFilterTap != null)
                  Padding(
                    padding: EdgeInsets.only(right: 10.sp),
                    child: InkWell(
                      onTap: () => _showFilterPopup(context),
                      borderRadius:
                          BorderRadius.zero, // Removed circular corners
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
        ),
      ],
    );
  }
}
