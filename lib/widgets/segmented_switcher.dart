import 'package:chessever2/utils/responsive_helper.dart';
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

class _SegmentedSwitcherState extends State<SegmentedSwitcher>
    with TickerProviderStateMixin {
  late int _selectedIndex;
  late AnimationController _animationController;
  late AnimationController _textAnimationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _textFadeAnimation;

  // Track previous index for text animation direction
  int _previousIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialSelection;
    _previousIndex = widget.initialSelection;

    // Main slide animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    // Text fade animation controller for smoother text transitions
    _textAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // Smooth slide animation with custom curve
    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    ));

    // Text fade animation
    _textFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _textAnimationController,
      curve: Curves.easeInOut,
    ));

    // Start with animation completed
    _animationController.value = 1.0;
    _textAnimationController.value = 1.0;
  }

  @override
  void dispose() {
    _animationController.dispose();
    _textAnimationController.dispose();
    super.dispose();
  }

  void _onSelectionChanged(int index) {
    if (index == _selectedIndex) return;

    setState(() {
      _previousIndex = _selectedIndex;
      _selectedIndex = index;
    });

    // Start animations
    _animationController.reset();
    _textAnimationController.reset();

    _animationController.forward();
    _textAnimationController.forward();

    widget.onSelectionChanged(index);
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
      child: AnimatedBuilder(
        animation: Listenable.merge([_slideAnimation, _textFadeAnimation]),
        builder: (context, child) {
          return Stack(
            children: [
              // Animated selection indicator
              Positioned.fill(
                child: Row(
                  children: List.generate(widget.options.length, (index) {
                    final isSelected = index == _selectedIndex;
                    final isFirst = index == 0;
                    final isLast = widget.options.length - 1 == index;

                    final leftSize = isFirst ? 12.0.br : 0.0;
                    final rightSize = isLast ? 12.0.br : 0.0;

                    return Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOutCubic,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? selectedBackgroundColor.withOpacity(
                              0.3 + (0.7 * _slideAnimation.value))
                              : Colors.transparent,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(leftSize),
                            bottomLeft: Radius.circular(leftSize),
                            bottomRight: Radius.circular(rightSize),
                            topRight: Radius.circular(rightSize),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              // Text and touch targets
              Row(
                children: List.generate(widget.options.length, (index) {
                  final isSelected = index == _selectedIndex;
                  final wasPreviouslySelected = index == _previousIndex;

                  // Calculate text opacity based on selection state and animation
                  double textOpacity = 1.0;
                  if (isSelected) {
                    // Currently selected item fades in
                    textOpacity = 0.4 + (0.6 * _textFadeAnimation.value);
                  } else if (wasPreviouslySelected) {
                    // Previously selected item fades out
                    textOpacity = 1.0 - (0.6 * _textFadeAnimation.value);
                  } else {
                    // Other items remain at default opacity
                    textOpacity = 0.7;
                  }

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _onSelectionChanged(index),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        alignment: Alignment.center,
                        padding: EdgeInsets.symmetric(vertical: 8.h),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          style: (isSelected ? defaultSelectedTextStyle : defaultTextStyle)
                              .copyWith(
                            color: (isSelected ? selectedTextColor : textColor)
                                .withOpacity(textOpacity),
                          ),
                          child: Text(
                            widget.options[index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}