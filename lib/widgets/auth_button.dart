import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import '../utils/app_typography.dart';

class AuthButton extends StatefulWidget {
  final String svgIconPath;
  final String signInTitle;
  final VoidCallback onPressed;
  final double height;
  final double? width;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const AuthButton({
    super.key,
    required this.svgIconPath,
    required this.signInTitle,
    required this.onPressed,
    this.height = 48, // 48px height as specified
    this.width,
    this.borderRadius = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  @override
  State<AuthButton> createState() => _AuthButtonState();
}

class _AuthButtonState extends State<AuthButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  bool _isPressed = false;

  @override
  void initState() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      upperBound: 0.05,
    );
    super.initState();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void onTapDown(TapDownDetails _) {
    _isPressed = true;
    _animationController.forward().then((value) {
      if (_isPressed) return;
      _animationController.reverse();
    });
  }

  void onTapUp(TapUpDetails _) {
    _isPressed = false;
    if (_animationController.isAnimating) return;
    _animationController.reverse();
  }

  void onTapCancel() {
    _isPressed = false;
    _animationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (cxt, child) {
        return Transform.scale(
          scale: 1 - _animationController.value,
          child: child,
        );
      },
      child: Container(
        height: widget.height.h,
        width: widget.width ?? MediaQuery.of(context).size.width,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: kWhiteColor, // Pure white background
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: [],
        ),
        child: InkWell(
          onTap: () {
            Future.delayed(
              Duration(milliseconds: 100),
            ).then((_) => widget.onPressed());
          },
          onTapDown: onTapDown,
          onTapCancel: onTapCancel,
          onTapUp: onTapUp,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgWidget(
                widget.svgIconPath,
                height: 20.h,
                width: 29.w,
                fallback: Icon(
                  Icons.apple,
                  size: 24.ic,
                  color: kBackgroundColor,
                ),
              ),
              SizedBox(width: 12.w),
              Text(
                widget.signInTitle,
                style: AppTypography.textLgMedium.copyWith(color: kBlackColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
