import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

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
  int _selectedIndex = 0;

  bool _isEditing = false;
  late TextEditingController _textController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _generateValues();
    _selectedIndex = _findClosestIndex(widget.initialValue);
    _controller = FixedExtentScrollController(initialItem: _selectedIndex);
    _textController = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      _submitEdit();
    }
  }

  void _startEditing() {
    HapticFeedbackService.light();
    setState(() {
      _isEditing = true;
      _textController.text = _values[_selectedIndex].round().toString();
    });
    _textController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _textController.text.length,
    );
    _focusNode.requestFocus();
  }

  void _submitEdit() {
    if (!_isEditing) return;
    final text = _textController.text;
    double? val = double.tryParse(text);
    if (val != null) {
      val = val.clamp(widget.minValue, widget.maxValue);
      int index = _findClosestIndex(val);
      if (index != _selectedIndex) {
        setState(() {
          _selectedIndex = index;
        });
        _controller.jumpToItem(index);
        widget.onChanged(_values[index]);
      }
    }
    setState(() {
      _isEditing = false;
    });
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
        setState(() {
          _selectedIndex = index;
        });
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _textController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: _isEditing ? null : (details) {
        // Find if they tapped the upper half or lower half of the widget
        final renderBox = context.findRenderObject() as RenderBox;
        final localPosition = renderBox.globalToLocal(details.globalPosition);
        final height = renderBox.size.height;

        // Only trigger if they tap away from the center (to avoid double-firing with item taps)
        if (localPosition.dy < height * 0.3) {
          // Tapped top section -> scroll up to previous item
          if (_selectedIndex > 0) {
            _controller.animateToItem(
              _selectedIndex - 1,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
          }
        } else if (localPosition.dy > height * 0.7) {
          // Tapped bottom section -> scroll down to next item
          if (_selectedIndex < _values.length - 1) {
            _controller.animateToItem(
              _selectedIndex + 1,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
          }
        }
      },
      child: Container(
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
              if (!_isEditing) ...[
                ListWheelScrollView.useDelegate(
                  controller: _controller,
                  itemExtent: 32.h,
                  perspective:
                      0.002, // Very slight perspective for a cleaner look
                  diameterRatio: 1.5,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: (index) {
                    HapticFeedbackService.selection();
                    setState(() {
                      _selectedIndex = index;
                    });
                    widget.onChanged(_values[index]);
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: _values.length,
                    builder: (context, index) {
                      final isSelected = index == _selectedIndex;

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (!isSelected) {
                            _controller.animateToItem(
                              index,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                            );
                          } else {
                            _startEditing();
                          }
                        },
                        child: SingleMotionBuilder(
                          motion: const CupertinoMotion.smooth(),
                          value: isSelected ? 1.0 : 0.0,
                          builder: (context, value, _) {
                            final scale = 0.8 + (0.2 * value);
                            final opacity = 0.5 + (0.5 * value);
                            final color =
                                Color.lerp(
                                  kSecondaryTextColor,
                                  kWhiteColor,
                                  value,
                                )!;

                            return Transform.scale(
                              scale: scale,
                              child: Opacity(
                                opacity: opacity,
                                child: Center(
                                  child: Text(
                                    _values[index].round().toString(),
                                    style: AppTypography.textSmMedium.copyWith(
                                      color: color,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
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

                // Scroll indicator icon
                Positioned(
                  right: 12.w,
                  child: IgnorePointer(
                    child: Icon(
                      Icons.unfold_more_rounded,
                      color: kSecondaryTextColor.withValues(alpha: 0.3),
                      size: 16.ic,
                    ),
                  ),
                ),
              ] else
                Center(
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _submitEdit(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
