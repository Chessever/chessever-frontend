import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Compact liquid-glass title pill that sits beside [GlassBackButton].
///
/// Sizes to its content (optional icon + label) instead of claiming a full
/// app-bar title line. Caps width so long titles ellipsize cleanly.
class GlassTitleChip extends StatelessWidget {
  const GlassTitleChip({
    super.key,
    required this.label,
    this.icon,
    this.height = 40,
    this.maxWidth = 220,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.textStyle,
  });

  final String label;

  /// Optional leading icon (e.g. heart for Favorites).
  final Widget? icon;

  final double height;

  /// Soft cap so a long title never forces a full-bleed top row.
  final double maxWidth;

  final EdgeInsetsGeometry padding;

  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final style =
        textStyle ??
        AppTypography.textMdMedium.copyWith(
          color: context.colors.textPrimary,
          height: 1.1,
        );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        minHeight: height,
        maxHeight: height,
      ),
      child: GlassContainer(
        useOwnLayer: true,
        height: height,
        padding: padding,
        alignment: Alignment.center,
        shape: LiquidRoundedSuperellipse(borderRadius: height / 2),
        quality: GlassQuality.standard,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              icon!,
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
