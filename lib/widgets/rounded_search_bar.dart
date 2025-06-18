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
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: kProfileInitialsGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                profileInitials.toUpperCase(),
                style: TextStyle(
                  color: kBlack2Color, // Changed to kBlack2Color as requested
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(
          width: 21,
        ), // Adjusted spacing to match Figma design (was 8)
        // Search bar container - starts after the profile avatar
        Expanded(
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color:
                  kBlack2Color, // Using theme constant instead of hardcoded 0xFF1A1A1C
              borderRadius: BorderRadius.circular(
                4,
              ), // Changed to 4 as requested
            ),
            padding: const EdgeInsets.only(
              left: 6,
              right: 6,
              top: 4,
              bottom: 4,
            ),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.center, // Ensure vertical centering
              children: [
                // Search icon aligned with text
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: SvgWidget(SvgAsset.searchIcon, height: 16, width: 16),
                ),
                const SizedBox(width: 4),

                // Text field
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    autofocus: autofocus,
                    textAlignVertical:
                        TextAlignVertical
                            .center, // Added to center text vertically
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor,
                    ),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: AppTypography.textXsRegular.copyWith(
                        color:
                            kWhiteColor70, // Using kWhiteColor70 instead of white with opacity
                      ),
                      border: InputBorder.none,

                      isDense: true, // Makes the input field more compact
                      contentPadding:
                          EdgeInsets
                              .zero, // Removed padding to allow proper centering
                    ),
                  ),
                ),

                // Filter icon
                if (onFilterTap != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: () => _showFilterPopup(context),
                      borderRadius:
                          BorderRadius.zero, // Removed circular corners
                      child: SvgWidget(
                        SvgAsset.listFilterIcon,
                        height: 24,
                        width: 24,
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
