import 'dart:ui';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// Shows a smooth alert modal with Motor-powered spring animations.
/// Features blur backdrop and scale+fade entrance animation.
Future<T?> showAlertModal<T>({
  required BuildContext context,
  required Widget child,
  double horizontalPadding = 24,
  double verticalPadding = 0,
  Color? backgroundColor,
  bool barrierDismissible = true,
  Color barrierColor = Colors.black54,
  bool useBlur = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero, // Motor handles animation
    pageBuilder: (context, animation, secondaryAnimation) {
      return _SmoothAlertWrapper<T>(
        horizontalPadding: horizontalPadding,
        verticalPadding: verticalPadding,
        backgroundColor: backgroundColor,
        barrierDismissible: barrierDismissible,
        barrierColor: barrierColor,
        useBlur: useBlur,
        child: child,
      );
    },
  );
}

class _SmoothAlertWrapper<T> extends StatefulWidget {
  const _SmoothAlertWrapper({
    required this.child,
    required this.horizontalPadding,
    required this.verticalPadding,
    this.backgroundColor,
    required this.barrierDismissible,
    required this.barrierColor,
    required this.useBlur,
  });

  final Widget child;
  final double horizontalPadding;
  final double verticalPadding;
  final Color? backgroundColor;
  final bool barrierDismissible;
  final Color barrierColor;
  final bool useBlur;

  @override
  State<_SmoothAlertWrapper<T>> createState() => _SmoothAlertWrapperState<T>();
}

class _SmoothAlertWrapperState<T> extends State<_SmoothAlertWrapper<T>> {
  double _animationProgress = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _animationProgress = 1.0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      motion: const CupertinoMotion.bouncy(),
      value: _animationProgress,
      builder: (context, value, child) {
        final scale = 0.85 + (0.15 * value);
        final opacity = value.clamp(0.0, 1.0);
        final blurAmount = widget.useBlur ? 8 * value : 0.0;

        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap:
                widget.barrierDismissible ? () => Navigator.pop(context) : null,
            child: Stack(
              children: [
                // Backdrop with blur
                Positioned.fill(
                  child:
                      widget.useBlur
                          ? BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: blurAmount,
                              sigmaY: blurAmount,
                            ),
                            child: Container(
                              color: widget.barrierColor.withValues(
                                alpha: opacity * 0.7,
                              ),
                            ),
                          )
                          : Container(
                            color: widget.barrierColor.withValues(
                              alpha: opacity * 0.7,
                            ),
                          ),
                ),
                // Dialog content
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.horizontalPadding.w,
                      vertical: widget.verticalPadding.h,
                    ),
                    child: Opacity(
                      opacity: opacity,
                      child: Transform.scale(
                        scale: scale,
                        child: GestureDetector(
                          onTap: () {}, // Absorb tap
                          child: widget.child,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shows a confirmation dialog with smooth animations.
/// Returns true if confirmed, false if cancelled, null if dismissed.
Future<bool?> showSmoothConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmText = 'Confirm',
  String cancelText = 'Cancel',
  Color? confirmColor,
  bool isDangerous = false,
}) {
  return showAlertModal<bool>(
    context: context,
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.sp),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(color: context.colors.textPrimary.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 12.h),
          Text(
            message,
            style: TextStyle(
              color: context.colors.textPrimary.withValues(alpha: 0.7),
              fontSize: 14.sp,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24.h),
          Row(
            children: [
              Expanded(
                child: _DialogButton(
                  text: cancelText,
                  onTap: () => Navigator.pop(context, false),
                  isOutlined: true,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _DialogButton(
                  text: confirmText,
                  onTap: () => Navigator.pop(context, true),
                  color:
                      confirmColor ?? (isDangerous ? kRedColor : kPrimaryColor),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DialogButton extends StatefulWidget {
  const _DialogButton({
    required this.text,
    required this.onTap,
    this.color,
    this.isOutlined = false,
  });

  final String text;
  final VoidCallback onTap;
  final Color? color;
  final bool isOutlined;

  @override
  State<_DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.95),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onTap,
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.snappy(),
        value: _scale,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 14.h),
          decoration: BoxDecoration(
            color:
                widget.isOutlined
                    ? Colors.transparent
                    : (widget.color ?? kPrimaryColor),
            borderRadius: BorderRadius.circular(12.br),
            border:
                widget.isOutlined
                    ? Border.all(
                      color: context.colors.textPrimary.withValues(alpha: 0.3),
                      width: 1,
                    )
                    : null,
          ),
          child: Center(
            child: Text(
              widget.text,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
