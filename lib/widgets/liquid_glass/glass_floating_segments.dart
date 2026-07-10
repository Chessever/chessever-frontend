import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Mode tabs as floating liquid islands — never a sticky full-bleed slab.
///
/// - **[expanded] true** (page top): package segmented glass island
/// - **[expanded] false** (scrolled): horizontal row of [GlassChip]s
///
/// Content-height only; pair with [GlassIslandStack] for zero dead strip.
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
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool expanded;
  final bool notifyOnReselect;
  final bool isScrollable;
  final double? horizontalPadding;
  final List<Widget>? optionLabels;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();

    final pad = horizontalPadding ?? 12.0;
    final index = selectedIndex.clamp(0, options.length - 1);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.topCenter,
              children: <Widget>[
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          child:
              expanded
                  ? KeyedSubtree(
                    key: const ValueKey('segments-full'),
                    child: SegmentedSwitcher(
                      options: options,
                      optionLabels: optionLabels,
                      initialSelection: index,
                      currentSelection: index,
                      onSelectionChanged: onSelected,
                      notifyOnReselect: notifyOnReselect,
                      isScrollable: isScrollable,
                    ),
                  )
                  : KeyedSubtree(
                    key: const ValueKey('segments-chips'),
                    child: _FloatingChipRow(
                      options: options,
                      selectedIndex: index,
                      onSelected: onSelected,
                      notifyOnReselect: notifyOnReselect,
                    ),
                  ),
        ),
      ),
    );
  }
}

class _FloatingChipRow extends StatelessWidget {
  const _FloatingChipRow({
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    required this.notifyOnReselect,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool notifyOnReselect;

  @override
  Widget build(BuildContext context) {
    final selectedColor = context.colors.brand.withValues(alpha: 0.28);
    final labelStyle = AppTypography.textXsMedium.copyWith(
      color: context.colors.textPrimary,
    );
    final mutedStyle = AppTypography.textXsMedium.copyWith(
      color: context.colors.tabInactive,
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              GlassChip(
                label: options[i],
                selected: i == selectedIndex,
                selectedColor: selectedColor,
                useOwnLayer: true,
                labelStyle: i == selectedIndex ? labelStyle : mutedStyle,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                onTap: () {
                  if (i == selectedIndex && !notifyOnReselect) return;
                  onSelected(i);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
