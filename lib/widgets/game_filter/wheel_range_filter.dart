import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter/material.dart';

/// A range filter that uses two wheel scroll views styled like input fields.
/// Replaces the standard RangeSlider for better usability and precise control.
class WheelRangeFilter extends StatelessWidget {
  final double minValue;
  final double maxValue;
  final double currentStart;
  final double currentEnd;
  final int divisions;
  final Function(RangeValues) onChanged;

  const WheelRangeFilter({
    super.key,
    required this.minValue,
    required this.maxValue,
    required this.currentStart,
    required this.currentEnd,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final step = (maxValue - minValue) / divisions;

    return Row(
      children: [
        // Minimum Value Wheel
        Expanded(
          child: _WheelInput(
            key: ValueKey('start-$minValue-$maxValue'),
            minValue: minValue,
            maxValue: maxValue,
            initialValue: currentStart,
            step: step,
            onChanged: (val) {
              if (val > currentEnd) {
                onChanged(RangeValues(val, val));
              } else {
                onChanged(RangeValues(val, currentEnd));
              }
            },
          ),
        ),
        
        // Separator
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: Text(
            '-',
            style: AppTypography.textSmMedium.copyWith(
              color: kSecondaryTextColor.withValues(alpha: 0.5),
            ),
          ),
        ),
        
        // Maximum Value Wheel
        Expanded(
          child: _WheelInput(
            key: ValueKey('end-$minValue-$maxValue'),
            minValue: minValue,
            maxValue: maxValue,
            initialValue: currentEnd,
            step: step,
            onChanged: (val) {
              if (val < currentStart) {
                onChanged(RangeValues(val, val));
              } else {
                onChanged(RangeValues(currentStart, val));
              }
            },
          ),
        ),
      ],
    );
  }
}

class _WheelInput extends StatefulWidget {
  final double minValue;
  final double maxValue;
  final double initialValue;
  final double step;
  final ValueChanged<double> onChanged;

  const _WheelInput({
    super.key,
    required this.minValue,
    required this.maxValue,
    required this.initialValue,
    required this.step,
    required this.onChanged,
  });

  @override
  State<_WheelInput> createState() => _WheelInputState();
}

class _WheelInputState extends State<_WheelInput> {
  late FixedExtentScrollController _controller;
  late List<double> _values;

  @override
  void initState() {
    super.initState();
    _generateValues();
    final index = _findClosestIndex(widget.initialValue);
    _controller = FixedExtentScrollController(initialItem: index);
  }

  void _generateValues() {
    _values = [];
    double current = widget.minValue;
    // Using a small epsilon to handle floating point precision
    final epsilon = widget.step / 1000;
    while (current <= widget.maxValue + epsilon) {
      _values.add(current);
      current += widget.step;
    }
    
    // Safety check to ensure maxValue is included if not added due to precision
    if (_values.isEmpty || _values.last < widget.maxValue - epsilon) {
      _values.add(widget.maxValue);
    }
  }

  int _findClosestIndex(double value) {
    int closestIndex = 0;
    double minDiff = (value - _values[0]).abs();
    for (int i = 1; i < _values.length; i++) {
      double diff = (value - _values[i]).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestIndex = i;
      }
    }
    return closestIndex;
  }

  @override
  void didUpdateWidget(_WheelInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minValue != widget.minValue ||
        oldWidget.maxValue != widget.maxValue ||
        oldWidget.step != widget.step) {
      _generateValues();
    }

    // If initialValue changed from outside, jump to it
    if (oldWidget.initialValue != widget.initialValue) {
      final index = _findClosestIndex(widget.initialValue);
      if (index != _controller.selectedItem) {
        _controller.jumpToItem(index);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48.h,
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kDividerColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.br),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ListWheelScrollView.useDelegate(
              controller: _controller,
              itemExtent: 32.h,
              perspective: 0.002, // Very slight perspective for a cleaner look
              diameterRatio: 1.5,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: (index) {
                HapticFeedbackService.selection();
                widget.onChanged(_values[index]);
              },
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: _values.length,
                builder: (context, index) {
                  return Center(
                    child: Text(
                      _values[index].round().toString(),
                      style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
                    ),
                  );
                },
              ),
            ),
            
            // Fading gradients to simulate the "wheel inside a field" look
            IgnorePointer(
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            kBlack2Color,
                            kBlack2Color.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 24.h), // Clear center area
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            kBlack2Color,
                            kBlack2Color.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
