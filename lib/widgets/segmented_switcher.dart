import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
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

  // Scroll state for the scrollable (team) variant, so the selected tab is
  // kept centered in the strip — revealing the tabs on either side.
  final ScrollController _scrollController = ScrollController();
  double _segmentWidth = 0;
  double _viewportWidth = 0;
  int? _lastCenteredIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.currentSelection ?? widget.initialSelection;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

  /// Scrolls so the selected segment sits centered in the strip. Jumps on the
  /// first pass (avoids a 0→target flash), animates on later selections.
  void _centerSelectedSegment() {
    if (!_scrollController.hasClients || _segmentWidth <= 0) return;
    if (_lastCenteredIndex == _selectedIndex) return;
    final target = (_selectedIndex * _segmentWidth + _segmentWidth / 2) -
        _viewportWidth / 2;
    final clamped = target.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    final first = _lastCenteredIndex == null;
    _lastCenteredIndex = _selectedIndex;
    if (first) {
      _scrollController.jumpTo(clamped);
    } else {
      _scrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _onSelectionChanged(int index, {bool fromExternal = false}) {
    if (!mounted) return;
    final isReselect = index == _selectedIndex;

    if (!isReselect) {
      setState(() {
        _selectedIndex = index;
      });
    }

    if (fromExternal) return;
    if (isReselect && !widget.notifyOnReselect) return;
    widget.onSelectionChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.backgroundColor ?? context.colors.background;
    final selectedBackgroundColor =
        widget.selectedBackgroundColor ?? context.colors.background;
    final textColor = widget.textColor ?? context.colors.tabInactive;
    final selectedTextColor = widget.selectedTextColor ?? context.colors.textPrimary;
    final borderRadius = widget.borderRadius ?? 8.br;

    final defaultTextStyle =
        widget.textStyle ??
        AppTypography.textSmMedium.copyWith(color: textColor);
    final defaultSelectedTextStyle =
        widget.selectedTextStyle ??
        AppTypography.textSmMedium.copyWith(color: selectedTextColor);

    if (widget.isScrollable) {
      // Each segment is exactly one third of the strip width, so the visible
      // area always shows 3 tabs — identical to the fixed layout — and any
      // extra tab (the team "Players" tab) is revealed by horizontal scroll.
      return LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / 3;
          _segmentWidth = segmentWidth;
          _viewportWidth = constraints.maxWidth;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _centerSelectedSegment(),
          );
          return Container(
            height: 40.h,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: List.generate(widget.options.length, (index) {
                  final isSelected = index == _selectedIndex;
                  final textOpacity = isSelected ? 1.0 : 0.7;
                  final style = (isSelected
                          ? defaultSelectedTextStyle
                          : defaultTextStyle)
                      .copyWith(
                        color: (isSelected ? selectedTextColor : textColor)
                            .withOpacity(textOpacity),
                      );

                  return GestureDetector(
                    onTap: () => _onSelectionChanged(index),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOutCubic,
                      width: segmentWidth,
                      alignment: Alignment.center,
                      padding: EdgeInsets.symmetric(vertical: 8.h),
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? selectedBackgroundColor
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(borderRadius),
                      ),
                      child:
                          widget.optionLabels != null
                              ? DefaultTextStyle.merge(
                                style: style,
                                child: widget.optionLabels![index],
                              )
                              : Text(
                                widget.options[index],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: style,
                              ),
                    ),
                  );
                }),
              ),
            ),
          );
        },
      );
    }

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
              final style = (isSelected
                      ? defaultSelectedTextStyle
                      : defaultTextStyle)
                  .copyWith(
                    color: (isSelected ? selectedTextColor : textColor)
                        .withOpacity(textOpacity),
                  );

              return Expanded(
                child: GestureDetector(
                  onTap: () => _onSelectionChanged(index),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    child:
                        widget.optionLabels != null
                            ? DefaultTextStyle.merge(
                              style: style,
                              child: widget.optionLabels![index],
                            )
                            : Text(
                              widget.options[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style,
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
