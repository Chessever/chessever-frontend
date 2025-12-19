import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:motor/motor.dart';

/// Behavior after swipe action is triggered.
enum SwipeActionBehavior {
  /// Card dismisses with slide-out animation (for delete/remove actions)
  dismiss,
  /// Card bounces back with success flash (for add/save actions)
  bounceBack,
}

/// Swipe-to-action card with smooth spring physics and configurable animations.
///
/// Supports two behaviors:
/// - [SwipeActionBehavior.dismiss]: Card slides out and disappears (for delete)
/// - [SwipeActionBehavior.bounceBack]: Card bounces back with success flash (for add)
class SwipeActionCard extends StatefulWidget {
  const SwipeActionCard({
    super.key,
    required this.dismissKey,
    required this.child,
    required this.onAction,
    required this.icon,
    required this.backgroundColor,
    this.label,
    this.enabled = true,
    this.dismissDirection = DismissDirection.endToStart,
    this.dismissThreshold = 0.28,
    this.borderRadius = 12,
    this.behavior = SwipeActionBehavior.bounceBack,
  });

  final Key dismissKey;
  final Widget child;
  final Future<void> Function() onAction;

  final IconData icon;
  final Color backgroundColor;
  final String? label;

  final bool enabled;
  final DismissDirection dismissDirection;
  final double dismissThreshold;
  final double borderRadius;
  final SwipeActionBehavior behavior;

  @override
  State<SwipeActionCard> createState() => _SwipeActionCardState();
}

class _SwipeActionCardState extends State<SwipeActionCard>
    with SingleTickerProviderStateMixin {
  double _dragExtent = 0;
  bool _isDismissing = false;
  bool _isVisible = true;
  bool _showSuccessFlash = false;

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_isDismissing || !widget.enabled) return;

    setState(() {
      if (widget.dismissDirection == DismissDirection.endToStart) {
        _dragExtent =
            (_dragExtent + details.delta.dx).clamp(-double.infinity, 0);
      } else {
        _dragExtent =
            (_dragExtent + details.delta.dx).clamp(0, double.infinity);
      }
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_isDismissing || !widget.enabled) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final threshold = screenWidth * widget.dismissThreshold;

    if (_dragExtent.abs() > threshold) {
      _triggerAction();
    } else {
      // Spring back
      setState(() => _dragExtent = 0);
    }
  }

  Future<void> _triggerAction() async {
    if (widget.behavior == SwipeActionBehavior.dismiss) {
      await _dismissCard();
    } else {
      await _bounceBackWithSuccess();
    }
  }

  Future<void> _dismissCard() async {
    setState(() => _isDismissing = true);

    // Wait for slide-out animation
    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;
    setState(() => _isVisible = false);

    // Call the action after the exit animation completes
    await widget.onAction();
  }

  Future<void> _bounceBackWithSuccess() async {
    // First bounce back
    setState(() {
      _dragExtent = 0;
      _showSuccessFlash = true;
    });

    // Call the action
    await widget.onAction();

    // Hide success flash after a delay
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      setState(() => _showSuccessFlash = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) {
      // Return an animating-out placeholder that collapses
      return SizedBox(height: 0, child: widget.child)
          .animate()
          .fadeOut(duration: 200.ms)
          .slideX(begin: 0, end: -0.3, duration: 200.ms, curve: Curves.easeIn);
    }

    final isRtl = widget.dismissDirection == DismissDirection.endToStart;

    return GestureDetector(
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      child: Stack(
        children: [
          // Background action indicator
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius.br),
              child: Container(
                color: widget.backgroundColor,
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Align(
                  alignment:
                      isRtl ? Alignment.centerRight : Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isRtl && widget.label != null) ...[
                        Text(
                          widget.label!,
                          style: AppTypography.textSmMedium.copyWith(
                            color: kWhiteColor,
                          ),
                        ),
                        SizedBox(width: 10.w),
                      ],
                      Icon(widget.icon, color: kWhiteColor, size: 22.sp),
                      if (!isRtl && widget.label != null) ...[
                        SizedBox(width: 10.w),
                        Text(
                          widget.label!,
                          style: AppTypography.textSmMedium.copyWith(
                            color: kWhiteColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Success flash overlay
          if (_showSuccessFlash)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius.br),
                child: Container(color: widget.backgroundColor),
              )
                  .animate()
                  .fadeIn(duration: 100.ms)
                  .then()
                  .fadeOut(duration: 300.ms, delay: 100.ms),
            ),

          // Foreground card with spring animation
          SingleMotionBuilder(
            motion:
                _isDismissing
                    ? CupertinoMotion.snappy()
                    : CupertinoMotion.bouncy(),
            value:
                _isDismissing
                    ? (isRtl
                        ? -MediaQuery.of(context).size.width
                        : MediaQuery.of(context).size.width)
                    : _dragExtent,
            builder: (context, offsetX, child) {
              return Transform.translate(offset: Offset(offsetX, 0), child: child);
            },
            child:
                _isDismissing
                    ? widget.child
                        .animate()
                        .fadeOut(duration: 250.ms, curve: Curves.easeOut)
                    : widget.child,
          ),
        ],
      ),
    );
  }
}
