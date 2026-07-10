import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Compact top chrome row: glass back island + title.
///
/// Follows liquid_glass_widgets iOS 26 guidance — glass on interactive
/// controls ([GlassIconButton]), not a solid full-width app-bar slab.
class AppBarWithTitle extends StatelessWidget {
  const AppBarWithTitle({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            GlassIconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_outlined,
                color: context.colors.iconPrimary,
              ),
              onPressed: () => Navigator.of(context).pop(),
              size: 40,
              iconSize: 18,
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textMdRegular.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            // Symmetry spacer matching GlassIconButton size.
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}
