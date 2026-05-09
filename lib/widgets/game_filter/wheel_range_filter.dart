import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motor/motor.dart';

/// A range filter that uses two wheel scroll views styled like input fields.
/// Replaces the standard RangeSlider for better usability and precise control.
class WheelRangeFilter extends StatefulWidget {
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
  State<WheelRangeFilter> createState() => _WheelRangeFilterState();
}

class _WheelRangeFilterState extends State<WheelRangeFilter> {
  late RangeValues _range;

  @override
  void initState() {
    super.initState();
    _range = _normalizeRange(widget.currentStart, widget.currentEnd);
  }

  @override
  void didUpdateWidget(covariant WheelRangeFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentStart != widget.currentStart ||
        oldWidget.currentEnd != widget.currentEnd ||
        oldWidget.minValue != widget.minValue ||
        oldWidget.maxValue != widget.maxValue) {
      final nextRange = _normalizeRange(widget.currentStart, widget.currentEnd);
      if (_range != nextRange) {
        _range = nextRange;
      }
    }
  }

  RangeValues _normalizeRange(double start, double end) {
    final clampedStart = start.clamp(widget.minValue, widget.maxValue);
    final clampedEnd = end.clamp(widget.minValue, widget.maxValue);
    if (clampedStart <= clampedEnd) {
      return RangeValues(clampedStart, clampedEnd);
    }
    return RangeValues(clampedEnd, clampedStart);
  }

  void _updateRange(RangeValues nextRange) {
    final normalized = _normalizeRange(nextRange.start, nextRange.end);
    if (_range != normalized) {
      setState(() {
        _range = normalized;
      });

      // Only notify parent if the change is significant to avoid rounding loops
      if ((normalized.start - widget.currentStart).abs() > 0.001 ||
          (normalized.end - widget.currentEnd).abs() > 0.001) {
        widget.onChanged(normalized);
      }
    }
  }

  void _updateStart(double value) {
    final nextEnd = value > _range.end ? value : _range.end;
    _updateRange(RangeValues(value, nextEnd));
  }

  void _updateEnd(double value) {
    final nextStart = value < _range.start ? value : _range.start;
    _updateRange(RangeValues(nextStart, value));
  }

  @override
  Widget build(BuildContext context) {
    final step = (widget.maxValue - widget.minValue) / widget.divisions;

    return Row(
      children: [
        // Minimum Value Wheel
        Expanded(
          child: _WheelInput(
            key: ValueKey('start-${widget.minValue}-${widget.maxValue}'),
            minValue: widget.minValue,
            maxValue: widget.maxValue,
            initialValue: _range.start,
            step: step,
            onChanged: _updateStart,
          ),
        ),

        // Separator
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: Text(
            '-',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textSecondary.withValues(alpha: 0.5),
            ),
          ),
        ),

        // Maximum Value Wheel
        Expanded(
          child: _WheelInput(
            key: ValueKey('end-${widget.minValue}-${widget.maxValue}'),
            minValue: widget.minValue,
            maxValue: widget.maxValue,
            initialValue: _range.end,
            step: step,
            onChanged: _updateEnd,
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
    if (mounted && !_focusNode.hasFocus && _isEditing) {
      _submitEdit();
    }
  }

  void _startEditing() {
    HapticFeedbackService.light();
    setState(() {
      _isEditing = true;
      _textController.text = _values[_selectedIndex].round().toString();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _textController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _textController.text.length,
      );
      _focusNode.requestFocus();
    });
  }

  void _submitEdit() {
    if (!_isEditing || !mounted) return;
    final text = _textController.text;
    final val = double.tryParse(text);

    int nextIndex;
    if (val != null) {
      final clamped = val.clamp(widget.minValue, widget.maxValue);
      nextIndex = _findClosestIndex(clamped);
    } else {
      // Revert to initial value if input is invalid
      nextIndex = _findClosestIndex(widget.initialValue);
    }

    setState(() {
      _selectedIndex = nextIndex;
      _isEditing = false;
    });

    widget.onChanged(_values[_selectedIndex]);
    _scheduleControllerSync();
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

  int _nearestLoopingTarget(int index) {
    if (!_controller.hasClients || _values.isEmpty) {
      return index;
    }

    final current = _controller.selectedItem;
    final cycle = _values.length;
    final offset = ((current - index) / cycle).round();
    return index + offset * cycle;
  }

  void _scheduleControllerSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients || _values.isEmpty) return;
      final target = _nearestLoopingTarget(_selectedIndex);
      if (target != _controller.selectedItem) {
        _controller.jumpToItem(target);
      }
    });
  }

  @override
  void didUpdateWidget(_WheelInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minValue != widget.minValue ||
        oldWidget.maxValue != widget.maxValue ||
        oldWidget.step != widget.step) {
      _generateValues();
    }

    final index = _findClosestIndex(widget.initialValue);
    if (_selectedIndex != index && !_isEditing) {
      setState(() {
        _selectedIndex = index;
      });
    }

    if (!_isEditing) {
      _scheduleControllerSync();
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
      onTapUp:
          _isEditing
              ? null
              : (details) {
                // Find if they tapped the upper half or lower half of the widget
                final renderBox = context.findRenderObject() as RenderBox;
                final localPosition = renderBox.globalToLocal(
                  details.globalPosition,
                );
                final height = renderBox.size.height;
                if (!_controller.hasClients) return;

                // Only trigger if they tap away from the center (to avoid double-firing with item taps)
                if (localPosition.dy < height * 0.3) {
                  // Tapped top section -> scroll up to previous item
                  _controller.animateToItem(
                    _controller.selectedItem - 1,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                  );
                } else if (localPosition.dy > height * 0.7) {
                  // Tapped bottom section -> scroll down to next item
                  _controller.animateToItem(
                    _controller.selectedItem + 1,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                  );
                }
              },
      child: Container(
        height: 48.h,
        decoration: BoxDecoration(
          color: context.colors.surface,
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
                    final normalizedIndex =
                        (index % _values.length + _values.length) %
                        _values.length;

                    if (normalizedIndex == _selectedIndex) return;

                    HapticFeedbackService.selection();
                    setState(() {
                      _selectedIndex = normalizedIndex;
                    });
                    widget.onChanged(_values[normalizedIndex]);
                  },
                  childDelegate: ListWheelChildLoopingListDelegate(
                    children: List.generate(_values.length, (index) {
                      final isSelected = index == _selectedIndex;

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (!isSelected) {
                            if (!_controller.hasClients) {
                              setState(() {
                                _selectedIndex = index;
                              });
                              widget.onChanged(_values[index]);
                              _scheduleControllerSync();
                              return;
                            }

                            final target = _nearestLoopingTarget(index);

                            _controller.animateToItem(
                              target,
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
                                  context.colors.textSecondary,
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
                    }),
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
                                context.colors.surface.withValues(alpha: 0),
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
                                context.colors.surface.withValues(alpha: 0),
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
                      color: context.colors.textSecondary.withValues(alpha: 0.3),
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
                    autofocus: true,
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(
                        widget.maxValue.round().toString().length,
                      ),
                    ],
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (text) {
                      if (text.isEmpty) return;
                      final val = double.tryParse(text);
                      if (val != null) {
                        // Only auto-update parent if the value is "complete" (e.g. 4 digits for years)
                        // This prevents jarring normalization jumps during early typing
                        // while ensuring that valid-length values are saved immediately.
                        final isComplete =
                            text.length >=
                            widget.minValue.round().toString().length;

                        if (isComplete) {
                          final clamped = val.clamp(
                            widget.minValue,
                            widget.maxValue,
                          );
                          final index = _findClosestIndex(clamped);
                          if (index != _selectedIndex) {
                            setState(() => _selectedIndex = index);
                            widget.onChanged(_values[index]);
                          }
                        }
                      }
                    },
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
