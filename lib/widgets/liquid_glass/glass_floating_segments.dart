import 'package:chessever2/widgets/liquid_glass/liquid_tab_bar.dart';
import 'package:flutter/material.dart';

/// Mode tabs following the general liquid-glass rule: glued into one bar at the
/// top of the list, separating into individual gapped glass icon chips as the
/// user scrolls down. Backed by [LiquidTabBar], which animates the transition.
///
/// [expanded] `true` = at top (glued); `false` = scrolled (separated).
class GlassFloatingSegments extends StatelessWidget {
  const GlassFloatingSegments({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    this.expanded = true,
    this.notifyOnReselect = false,
    this.isScrollable = false,
    this.horizontalPadding,
    this.optionLabels,
    this.optionIcons,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool expanded;
  final bool notifyOnReselect;
  final bool isScrollable;
  final double? horizontalPadding;
  final List<Widget>? optionLabels;

  /// Optional per-tab icon revealed when the tabs separate on scroll.
  final List<IconData>? optionIcons;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();

    final pad = horizontalPadding ?? 12.0;
    final index = selectedIndex.clamp(0, options.length - 1);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: Align(
        alignment: Alignment.centerLeft,
        child: LiquidTabBar(
          options: options,
          icons: optionIcons,
          selectedIndex: index,
          onSelected: (i) {
            if (i == index && !notifyOnReselect) return;
            onSelected(i);
          },
          separated: !expanded,
        ),
      ),
    );
  }
}
