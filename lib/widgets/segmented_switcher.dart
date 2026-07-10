import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Floating liquid-glass segment control used as outer category / mode tabs.
///
/// Backed by package [GlassSegmentedControl] (fixed or scrollable). Callers keep
/// the same API as before; the solid full-width strip is gone — the control is
/// a glass island sized to its content height only.
class SegmentedSwitcher extends StatefulWidget {
  final List<String> options;
  final int initialSelection;
  final int? currentSelection;
  final Function(int) onSelectionChanged;
  final Color? backgroundColor;
  final Color? selectedBackgroundColor;
  final Color? textColor;
  final Color? selectedTextColor;
  final double? borderRadius;
  final TextStyle? textStyle;
  final TextStyle? selectedTextStyle;
  final List<Widget>? optionLabels;
  final bool notifyOnReselect;

  /// When true, segments size to their content and scroll horizontally instead
  /// of splitting the width into equal thirds. Used for the 4-tab team layout.
  final bool isScrollable;

  const SegmentedSwitcher({
    super.key,
    required this.options,
    this.initialSelection = 0,
    this.currentSelection,
    required this.onSelectionChanged,
    this.backgroundColor,
    this.selectedBackgroundColor,
    this.textColor,
    this.selectedTextColor,
    this.borderRadius,
    this.textStyle,
    this.selectedTextStyle,
    this.optionLabels,
    this.notifyOnReselect = false,
    this.isScrollable = false,
  }) : assert(
         initialSelection >= 0 && initialSelection < options.length,
         'initialSelection must be within options range',
       ),
       assert(
         optionLabels == null || optionLabels.length == options.length,
         'optionLabels length must match options length',
       );

  @override
  State<SegmentedSwitcher> createState() => _SegmentedSwitcherState();
}

class _SegmentedSwitcherState extends State<SegmentedSwitcher> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.currentSelection ?? widget.initialSelection;
  }

  @override
  void didUpdateWidget(SegmentedSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentSelection != null &&
        widget.currentSelection != _selectedIndex &&
        mounted) {
      setState(() {
        _selectedIndex = widget.currentSelection!;
      });
    }
  }

  void _onSelectionChanged(int index) {
    if (!mounted) return;
    final isReselect = index == _selectedIndex;

    if (!isReselect) {
      setState(() {
        _selectedIndex = index;
      });
    }

    if (isReselect && !widget.notifyOnReselect) return;
    widget.onSelectionChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.textColor ?? context.colors.tabInactive;
    final selectedTextColor =
        widget.selectedTextColor ?? context.colors.textPrimary;

    final unselectedStyle =
        widget.textStyle ??
        AppTypography.textSmMedium.copyWith(color: textColor);
    final selectedStyle =
        widget.selectedTextStyle ??
        AppTypography.textSmMedium.copyWith(color: selectedTextColor);

    final segments = <GlassSegment>[
      for (final option in widget.options) GlassSegment(label: option),
    ];

    if (segments.isEmpty) {
      return const SizedBox.shrink();
    }

    // Single option → floating glass chip (not a segmented control).
    if (segments.length == 1) {
      return Align(
        alignment: Alignment.centerLeft,
        child: GlassChip(
          label: widget.options.first,
          selected: true,
          onTap: () => _onSelectionChanged(0),
          useOwnLayer: true,
          labelStyle: selectedStyle,
        ),
      );
    }

    // Package fixed control supports 2–5 well; 6+ must be scrollable.
    final useScrollable = widget.isScrollable || segments.length > 5;
    final index = _selectedIndex.clamp(0, segments.length - 1);

    // GlassSegmentedControl is itself a glass surface — do NOT wrap in
    // GlassCard/GlassContainer (package composition rule).
    if (useScrollable) {
      return GlassSegmentedControl.scrollable(
        segments: segments,
        selectedIndex: index,
        onSegmentSelected: _onSelectionChanged,
        height: 40.h,
        borderRadius: widget.borderRadius ?? 12.br,
        backgroundColor: widget.backgroundColor,
        indicatorColor: widget.selectedBackgroundColor,
        selectedTextStyle: selectedStyle,
        unselectedTextStyle: unselectedStyle,
        useOwnLayer: true,
      );
    }

    return GlassSegmentedControl(
      segments: segments,
      selectedIndex: index,
      onSegmentSelected: _onSelectionChanged,
      height: 40.h,
      borderRadius: widget.borderRadius ?? 12.br,
      backgroundColor: widget.backgroundColor,
      indicatorColor: widget.selectedBackgroundColor,
      selectedTextStyle: selectedStyle,
      unselectedTextStyle: unselectedStyle,
      useOwnLayer: true,
    );
  }
}
