import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';

/// The one filter count: a coin of the brand's tonal accent with the page's
/// colour for its number, ringed by whatever it sits on so it reads cleanly
/// on a shoulder. Worn by the search button, the search header's Filters
/// (`SearchModeFilterButton`) and the filter glyph inside a search field; a
/// toolbar glyph's count (`QuickToggleIconButton`) should wear it too.
///
/// The digit is the toolbar's: 10pt on the 16pt coin (11 on the 20pt one),
/// following the system text size up to 1.15x, where the coin still holds
/// it.
class SearchCountBadge extends StatelessWidget {
  const SearchCountBadge({
    super.key,
    required this.count,
    this.diameter = 20,
    this.ringColor,
  });

  final int count;

  /// The coin's height (and least width): 16 on a 20pt glyph, 20 on a
  /// floating button.
  final double diameter;

  /// What it sits on; the page's background by default.
  final Color? ringColor;

  /// The digit's size on a coin of [diameter].
  static double digitSize(double diameter) =>
      10 + ((diameter - 16) / 4).clamp(0.0, 2.0);

  /// How far the digit follows the system text size: past this it would
  /// crowd the coin's ring.
  static const double maxTextScale = 1.15;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ring = diameter >= 20 ? 2.0 : 1.5;
    final label = count > 9 ? '9+' : '$count';
    return Container(
      constraints: BoxConstraints(minWidth: diameter, minHeight: diameter),
      // A round coin for one digit (centred in it); "9+" stretches it into
      // a capsule with room at its ends.
      padding: EdgeInsets.symmetric(
        horizontal: label.length > 1 ? diameter / 4 : 0,
      ),
      decoration: BoxDecoration(
        color: colors.accentText,
        borderRadius: BorderRadius.circular(diameter / 2),
        border: Border.all(color: ringColor ?? colors.background, width: ring),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textScaler: MediaQuery.textScalerOf(
          context,
        ).clamp(maxScaleFactor: maxTextScale),
        textAlign: TextAlign.center,
        style: AppTypography.textXsMedium.copyWith(
          color: colors.background,
          fontSize: digitSize(diameter),
          height: 1,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
