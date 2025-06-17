import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/board_settings_provider.dart';
import '../utils/svg_asset.dart';
import '../widgets/settings_dialog.dart';

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

    return SettingsDialog(
      title: 'Board Colour',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        child: Row(
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
          // SVG Board Preview with fixed dimensions as requested
          SizedBox(
            width: 58,
            height: 88,
            child: SvgPicture.asset(
              svgAsset,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          // Selection indicator
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
              color: isSelected ? checkMarkColor : Colors.transparent,
            ),
            child: isSelected
                ? const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 20,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
