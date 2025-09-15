import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_typography.dart';

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
    _selectedIndex = widget.currentSelection ?? widget.initialSelection;
  }

  @override
  void didUpdateWidget(SegmentedSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentSelection != null &&
        widget.currentSelection != _selectedIndex &&
        mounted) {
      _onSelectionChanged(widget.currentSelection!, fromExternal: true);
    }
  }

  void _onSelectionChanged(int index, {bool fromExternal = false}) {
    if (index == _selectedIndex || !mounted) return;

    setState(() {
      _selectedIndex = index;
    });

    if (!fromExternal) {
      widget.onSelectionChanged(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.backgroundColor ?? kBackgroundColor;
    final selectedBackgroundColor =
        widget.selectedBackgroundColor ?? kBackgroundColor;
    final textColor = widget.textColor ?? kInactiveTabColor;
    final selectedTextColor = widget.selectedTextColor ?? kWhiteColor;
    final borderRadius = widget.borderRadius ?? 8.br;

    final defaultTextStyle =
        widget.textStyle ??
        AppTypography.textSmMedium.copyWith(color: textColor);
    final defaultSelectedTextStyle =
        widget.selectedTextStyle ??
        AppTypography.textSmMedium.copyWith(color: selectedTextColor);

    return Container(
      height: 40.h,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: List.generate(widget.options.length, (index) {
                final isSelected = index == _selectedIndex;
                final isFirst = index == 0;
                final isLast = index == widget.options.length - 1;

                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    decoration: BoxDecoration(
                      color:
                          isSelected
                              ? selectedBackgroundColor
                              : Colors.transparent,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(isFirst ? 12.0.br : 0.0),
                        bottomLeft: Radius.circular(isFirst ? 12.0.br : 0.0),
                        bottomRight: Radius.circular(isLast ? 12.0.br : 0.0),
                        topRight: Radius.circular(isLast ? 12.0.br : 0.0),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          Row(
            children: List.generate(widget.options.length, (index) {
              final isSelected = index == _selectedIndex;
              final textOpacity = isSelected ? 1.0 : 0.7;

              return Expanded(
                child: GestureDetector(
                  onTap: () => _onSelectionChanged(index),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    child: Text(
                      widget.options[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (isSelected
                              ? defaultSelectedTextStyle
                              : defaultTextStyle)
                          .copyWith(
                            color: (isSelected ? selectedTextColor : textColor)
                                .withOpacity(textOpacity),
                          ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
