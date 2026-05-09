import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// Primary button with Motor-powered spring animations.
/// Clean, minimal design with satisfying tactile feedback.
class AppButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final double? height;
  final double? width;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? textColor;
  final bool isLoading;
  final bool isOutlined;
  final Widget? icon;

  const AppButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.height,
    this.width,
    this.borderRadius = 12,
    this.padding,
    this.backgroundColor,
    this.textColor,
    this.isLoading = false,
    this.isOutlined = false,
    this.icon,
  });

  /// Creates a primary filled button
  factory AppButton.primary({
    Key? key,
    required String text,
    required VoidCallback onPressed,
    double? height,
    double? width,
    bool isLoading = false,
    Widget? icon,
  }) {
    return AppButton(
      key: key,
      text: text,
      onPressed: onPressed,
      height: height,
      width: width,
      backgroundColor: kPrimaryColor,
      textColor: kWhiteColor,
      isLoading: isLoading,
      icon: icon,
    );
  }

  /// Creates a secondary outlined button
  factory AppButton.secondary({
    Key? key,
    required String text,
    required VoidCallback onPressed,
    double? height,
    double? width,
    bool isLoading = false,
    Widget? icon,
  }) {
    return AppButton(
      key: key,
      text: text,
      onPressed: onPressed,
      height: height,
      width: width,
      isOutlined: true,
      textColor: kWhiteColor,
      isLoading: isLoading,
      icon: icon,
    );
  }

  /// Creates a danger button (red)
  factory AppButton.danger({
    Key? key,
    required String text,
    required VoidCallback onPressed,
    double? height,
    double? width,
    bool isLoading = false,
  }) {
    return AppButton(
      key: key,
      text: text,
      onPressed: onPressed,
      height: height,
      width: width,
      backgroundColor: kRedColor,
      textColor: kWhiteColor,
      isLoading: isLoading,
    );
  }

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails _) {
    setState(() => _scale = 0.96);
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _scale = 1.0);
  }

  void _onTapCancel() {
    setState(() => _scale = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.height ?? 52.h;
    final bgColor = widget.backgroundColor ?? kWhiteColor;
    final txtColor = widget.textColor ?? kBlackColor;

    return GestureDetector(
      onTapDown: widget.isLoading ? null : _onTapDown,
      onTapUp: widget.isLoading ? null : _onTapUp,
      onTapCancel: widget.isLoading ? null : _onTapCancel,
      onTap: widget.isLoading ? null : widget.onPressed,
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.snappy(),
        value: _scale,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          height: height,
          width: widget.width ?? double.infinity,
          padding: widget.padding ?? EdgeInsets.symmetric(horizontal: 24.w),
          decoration: BoxDecoration(
            color: widget.isOutlined ? Colors.transparent : bgColor,
            borderRadius: BorderRadius.circular(widget.borderRadius.br),
            border:
                widget.isOutlined
                    ? Border.all(
                      color: kWhiteColor.withValues(alpha: 0.3),
                      width: 1.5,
                    )
                    : null,
          ),
          child: Center(
            child:
                widget.isLoading
                    ? SizedBox(
                      width: 20.w,
                      height: 20.w,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(txtColor),
                      ),
                    )
                    : Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.icon != null) ...[
                          widget.icon!,
                          SizedBox(width: 8.w),
                        ],
                        Text(
                          widget.text,
                          style: AppTypography.textMdMedium.copyWith(
                            color: txtColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
          ),
        ),
      ),
    );
  }
}

/// Small icon button with Motor animation
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size,
    this.backgroundColor,
    this.iconColor,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double? size;
  final Color? backgroundColor;
  final Color? iconColor;
  final String? tooltip;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final size = widget.size ?? 44.w;

    Widget button = GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.9),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onPressed,
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.snappy(),
        value: _scale,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: widget.backgroundColor ?? kBlack2Color,
            borderRadius: BorderRadius.circular(size / 2),
          ),
          child: Center(
            child: Icon(
              widget.icon,
              size: size * 0.5,
              color: widget.iconColor ?? kWhiteColor,
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }

    return button;
  }
}

/// Tappable wrapper that adds Motor-powered scale animation to any widget
class TappableScale extends StatefulWidget {
  const TappableScale({
    super.key,
    required this.child,
    required this.onTap,
    this.scaleDown = 0.96,
  });

  final Widget child;
  final VoidCallback onTap;
  final double scaleDown;

  @override
  State<TappableScale> createState() => _TappableScaleState();
}

class _TappableScaleState extends State<TappableScale> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = widget.scaleDown),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onTap,
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.snappy(),
        value: _scale,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: widget.child,
      ),
    );
  }
}
