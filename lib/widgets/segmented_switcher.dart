import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_typography.dart';

class SegmentedSwitcher extends StatefulWidget {
  final List<String> options;
  final int initialSelection;
  final Function(int) onSelectionChanged;
  final Color? backgroundColor;
  final Color? selectedBackgroundColor;
  final Color? textColor;
  final Color? selectedTextColor;
  final double? borderRadius;
  final TextStyle? textStyle;
  final TextStyle? selectedTextStyle;

  const SegmentedSwitcher({
    super.key,
    required this.options,
    this.initialSelection = 0,
    required this.onSelectionChanged,
    this.backgroundColor,
    this.selectedBackgroundColor,
    this.textColor,
    this.selectedTextColor,
    this.borderRadius,
    this.textStyle,
    this.selectedTextStyle,
  }) : assert(
         initialSelection >= 0 && initialSelection < options.length,
         'initialSelection must be within options range',
       );

  @override
  State<SegmentedSwitcher> createState() => _SegmentedSwitcherState();
}

class _SegmentedSwitcherState extends State<SegmentedSwitcher> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialSelection;
  }

  @override
  Widget build(BuildContext context) {
    // Using the app theme black color instead of hardcoding
    final backgroundColor = widget.backgroundColor ?? kBackgroundColor;
    // Using pure black for the selected background as well
    final selectedBackgroundColor =
        widget.selectedBackgroundColor ?? kBackgroundColor;
    final textColor = widget.textColor ?? kInactiveTabColor;
    final selectedTextColor = widget.selectedTextColor ?? kWhiteColor;
    final borderRadius = widget.borderRadius ?? 8.0;

    final defaultTextStyle =
        widget.textStyle ??
        AppTypography.textSmMedium.copyWith(color: textColor);
    final defaultSelectedTextStyle =
        widget.selectedTextStyle ??
        AppTypography.textSmMedium.copyWith(color: selectedTextColor);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Row(
        children: List.generate(widget.options.length, (index) {
          final isSelected = index == _selectedIndex;
          final isFirst = index == 0;
          final isLast = widget.options.length - 1 == index;

          final leftSize = isFirst ? 12.0 : 0.0;
          final rightSize = isLast ? 12.0 : 0.0;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedIndex = index;
                });
                widget.onSelectionChanged(index);
              },
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selectedBackgroundColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(leftSize),
                    bottomLeft: Radius.circular(leftSize),
                    bottomRight: Radius.circular(rightSize),
                    topRight: Radius.circular(rightSize),
                  ),
                ),
                child: Text(
                  widget.options[index],
                  style:
                      isSelected ? defaultSelectedTextStyle : defaultTextStyle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
