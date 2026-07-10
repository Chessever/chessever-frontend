import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:flutter/material.dart';

/// Compact top chrome row: glass back island + title.
///
/// Follows liquid_glass_widgets iOS 26 guidance — glass on interactive
/// controls ([GlassBackButton]), not a solid full-width app-bar slab.
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
            const GlassBackButton(),
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
            // Symmetry spacer matching GlassBackButton size.
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}
