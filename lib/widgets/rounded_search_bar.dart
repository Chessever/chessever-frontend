import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/filter_popup.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/utils/app_typography.dart';

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
            width: 32, // Increased to match Figma design
            height: 32, // Increased to match Figma design
            decoration: BoxDecoration(
              color: const Color(0xFF00A3FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                profileInitials.toUpperCase(),
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Search bar container - starts after the profile avatar
        Expanded(
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: const Color(
                0xFF1A1A1C,
              ), // Updated exact color code from Figma
              borderRadius: BorderRadius.zero, // Removed circular corners
            ),
            padding: const EdgeInsets.only(left: 16, right: 12),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.center, // Ensure vertical centering
              children: [
                // Search icon aligned with text
                SvgWidget(SvgAsset.searchIcon, height: 16, width: 16),
                const SizedBox(width: 8),

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
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: AppTypography.textXsRegular.copyWith(
                        color: Colors.white.withOpacity(0.6),
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
                  InkWell(
                    onTap: () => _showFilterPopup(context),
                    borderRadius: BorderRadius.zero, // Removed circular corners
                    child: SvgWidget(
                      SvgAsset.listFilterIcon,
                      height: 16,
                      width: 16,
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
