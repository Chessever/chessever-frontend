import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';

class ChessSvgBottomNavbar extends StatelessWidget {
  final String svgPath;
  final double width;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool isActive;
  final String? depthText;

  const ChessSvgBottomNavbar({
    super.key,
    required this.svgPath,
    required this.width,
    required this.onPressed,
    this.onLongPress,
    this.isActive = false,
    this.depthText,
  });

  @override
  Widget build(BuildContext context) {
    // Determine icon color - white when active/enabled, transparent white when inactive
    final Color iconColor;
    if (onPressed == null) {
      iconColor = kWhiteColor70;
    } else if (isActive) {
      iconColor = kWhiteColor; // Use white when active, like arrow buttons
    } else {
      iconColor = kWhiteColor70; // Use transparent white when inactive
    }

    final depthStyle = TextStyle(
      color: iconColor,
      fontSize: 9.f,
      fontWeight: FontWeight.w600,
      height: 1.0,
      shadows: [
        Shadow(
          color: Colors.black.withValues(alpha: 0.35),
          offset: Offset(0, 1.sp),
          blurRadius: 2.sp,
        ),
      ],
    );

    final bool showDepth = depthText != null && depthText!.isNotEmpty;

    return GestureDetector(
      onTap: onPressed,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        height: 40.h, // Button container height - no space for text
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Center the icon vertically in the button area
            Center(
              child: SvgWidget(
                svgPath,
                height: 24.h,
                width: 24.w,
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              ),
            ),
            // Position depth text BELOW the button area (outside safe area)
            if (showDepth)
              Positioned(
                bottom: -15.h, // Push below with nice gap
                child: Text(depthText!, style: depthStyle),
              ),
          ],
        ),
      ),
    );
  }
}

class ChessSvgBottomNavbarWithLongPress extends StatelessWidget {
  final String svgPath;
  final double width;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;
  final bool showBadge;

  const ChessSvgBottomNavbarWithLongPress({
    super.key,
    required this.svgPath,
    required this.width,
    required this.onPressed,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      onLongPressStart:
          onLongPressStart != null ? (_) => onLongPressStart!() : null,
      onLongPressEnd: onLongPressEnd != null ? (_) => onLongPressEnd!() : null,
      onLongPressCancel: onLongPressEnd,
      child: SizedBox(
        width: width,
        height: 40.h, // Match ChessSvgBottomNavbar height
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Center(
              child: SvgWidget(
                svgPath,
                height: 24.h,
                width: 24.w,
                colorFilter: ColorFilter.mode(
                  onPressed != null ? kWhiteColor : kWhiteColor70,
                  BlendMode.srcIn,
                ),
              ),
            ),
            // Show red dot badge on top-right corner if showBadge is true
            if (showBadge && onPressed != null)
              Positioned(top: -4.h, right: 4.w, child: _UnseenMovesBadge()),
          ],
        ),
      ),
    );
  }
}

/// Blinking red dot badge for navigation buttons
class _UnseenMovesBadge extends StatefulWidget {
  const _UnseenMovesBadge();

  @override
  State<_UnseenMovesBadge> createState() => _UnseenMovesBadgeState();
}

class _UnseenMovesBadgeState extends State<_UnseenMovesBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 8.w,
          height: 8.h,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: _animation.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: _animation.value * 0.5),
                blurRadius: 3,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

class ChessIconBottomNavbar extends StatelessWidget {
  final IconData iconData;
  final VoidCallback? onPressed;

  const ChessIconBottomNavbar({
    super.key,
    required this.iconData,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: EdgeInsets.all(8.sp),
        child: Icon(iconData, size: 24.ic),
      ),
    );
  }
}
