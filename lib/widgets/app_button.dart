import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';

class AppButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final double height;
  final double? width;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const AppButton({
    required this.text,
    required this.onPressed,
    this.height = 48,
    this.width,
    this.borderRadius = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton>
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
        height: widget.height,
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
          child: Center(
            child: Text(
              widget.text,
              style: AppTypography.textMdMedium.copyWith(color: kBlackColor),
            ),
          ),
        ),
      ),
    );
  }
}
