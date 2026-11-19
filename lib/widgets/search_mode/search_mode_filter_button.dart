import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search_mode/search_count_badge.dart';
import 'package:flutter/material.dart';

/// The search header's Filters: the list toolbar's own Filters glyph, drawn
/// and placed as the toolbar draws it beside the list (a bare 20pt
/// `tune_rounded` in a 44pt target, no tile behind it), in the toolbar's
/// tonal accent while any filter is on, with the app's one filter count
/// ([SearchCountBadge]) on its shoulder.
///
/// Put it last in a `SearchModeHeader`'s `trailing`: its glyph then lands on
/// the page's gutter. Count-less toggles beside it (Classical, the view
/// toggle) are the toolbar's own buttons.
class SearchModeFilterButton extends StatelessWidget {
  const SearchModeFilterButton({
    super.key,
    required this.count,
    required this.onTap,
    this.label = 'Filters',
    this.icon = Icons.tune_rounded,
  });

  /// Filters applied; the count is shown above 0, and the glyph takes the
  /// accent.
  final int count;

  /// Opens the page's filter sheet. Null dims the glyph.
  final VoidCallback? onTap;

  /// The tooltip and the accessible name (with ", N active" appended).
  final String label;

  /// The toolbar's Filters glyph unless the page's toolbar draws another.
  final IconData icon;

  /// The tap target, the toolbar's.
  static const double target = 44;

  /// The count's coin on a 20pt glyph, at the toolbar's spot for it.
  static const double badgeDiameter = 16;
  static const double badgeTop = 6;
  static const double badgeRight = 4;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    final active = count > 0;
    return Semantics(
      button: true,
      enabled: enabled,
      label: active ? '$label, $count active' : label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox.square(
            dimension: target,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: enabled ? 1 : 0.4,
                  child: Icon(
                    icon,
                    size: 20.ic,
                    color: active ? colors.accentText : colors.iconPrimary,
                  ),
                ),
                if (active)
                  Positioned(
                    top: badgeTop,
                    right: badgeRight,
                    child: SearchCountBadge(
                      count: count,
                      diameter: badgeDiameter,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
