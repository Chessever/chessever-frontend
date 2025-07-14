import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/board_settings_provider.dart';
import '../utils/svg_asset.dart';
import '../theme/app_theme.dart';

// Update the BoardColorDialog to use blur effect
class BoardColorDialog extends ConsumerWidget {
  const BoardColorDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettings = ref.watch(boardSettingsProvider);

    // Define board colors
    final Color defaultColor = const Color(0xFF0FB4E5); // Teal/Default
    final Color brownColor = Colors.brown;
    final Color greyColor = Colors.grey;
    final Color greenColor = Colors.green;

    // Check which color is currently selected
    String selectedColor = 'default';
    if (boardSettings.boardColor == brownColor) {
      selectedColor = 'brown';
    } else if (boardSettings.boardColor == greyColor) {
      selectedColor = 'grey';
    } else if (boardSettings.boardColor == greenColor) {
      selectedColor = 'green';
    }

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Container(
        height: 259, // Fixed height of 259px as requested
        decoration: BoxDecoration(
          color: Color(0xff000000),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Small white bar at the top with adjusted size and spacing
            Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(top: 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            // Gap of 20px between white bar and board color text
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Title with updated typography
                  Text(
                    'Board Colour',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: kWhiteColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Color options row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildBoardColorOption(
                        context: context,
                        ref: ref,
                        svgAsset: SvgAsset.boardColorDefault,
                        label: 'Default',
                        color: defaultColor,
                        isSelected: selectedColor == 'default',
                      ),
                      _buildBoardColorOption(
                        context: context,
                        ref: ref,
                        svgAsset: SvgAsset.boardColorBrown,
                        label: 'Brown',
                        color: brownColor,
                        isSelected: selectedColor == 'brown',
                      ),
                      _buildBoardColorOption(
                        context: context,
                        ref: ref,
                        svgAsset: SvgAsset.boardColorGrey,
                        label: 'Grey',
                        color: greyColor,
                        isSelected: selectedColor == 'grey',
                      ),
                      _buildBoardColorOption(
                        context: context,
                        ref: ref,
                        svgAsset: SvgAsset.boardColorGreen,
                        label: 'Green',
                        color: greenColor,
                        isSelected: selectedColor == 'green',
                      ),
                    ],
                  ),

                  // Bottom padding for safe area
                  SizedBox(height: MediaQuery.of(context).padding.bottom),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardColorOption({
    required BuildContext context,
    required WidgetRef ref,
    required String svgAsset,
    required String label,
    required Color color,
    required bool isSelected,
  }) {
    // Specific green color for the check mark as requested
    const Color checkMarkColor = Color(0xFF247435);

    return GestureDetector(
      onTap: () {
        ref.read(boardSettingsProvider.notifier).setBoardColor(color);
        Navigator.of(context).pop();
      },
      child: Column(
        children: [
          // SVG Board Preview with fixed dimensions - changed to 32x32
          SizedBox(
            width: 32,
            height: 32,
            child: SvgPicture.asset(svgAsset, fit: BoxFit.contain),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          // Selection indicator - changed to 20x20
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              color: isSelected ? checkMarkColor : Colors.transparent,
            ),
            child:
                isSelected
                    ? const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 14,
                    ) // Smaller icon to match smaller circle
                    : null,
          ),
        ],
      ),
    );
  }
}
