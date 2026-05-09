import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
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

    final isTablet = ResponsiveHelper.isTablet;

    final depthStyle = TextStyle(
      color: iconColor,
      fontSize: isTablet ? 11.0 : 10.f,
      fontWeight: FontWeight.w600,
      height: 1.0,
      leadingDistribution: TextLeadingDistribution.even,
      shadows: [
        Shadow(
          color: Colors.black.withValues(alpha: 0.35),
          offset: Offset(0, 1.sp),
          blurRadius: 2.sp,
        ),
      ],
    );

    final bool showDepth = depthText != null && depthText!.isNotEmpty;
    final isTabletLandscape = isTablet && ResponsiveHelper.isLandscape;

    // On tablet, use a column layout to avoid overlap
    // On phone, use the original positioned layout
    if (isTablet && showDepth) {
      return GestureDetector(
        onTap:
            onPressed != null
                ? () {
                  HapticFeedbackService.buttonPress();
                  onPressed!();
                }
                : null,
        onLongPress: onLongPress,
        // Absorb horizontal drags on tablet landscape to prevent PageView interference
        onHorizontalDragStart: isTabletLandscape ? (_) {} : null,
        onHorizontalDragUpdate: isTabletLandscape ? (_) {} : null,
        onHorizontalDragEnd: isTabletLandscape ? (_) {} : null,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 2.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgWidget(
                    svgPath,
                    height: 24.h,
                    width: 24.w,
                    colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                  ),
                  SizedBox(height: 2.h),
                  Text(depthText!, style: depthStyle),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap:
          onPressed != null
              ? () {
                HapticFeedbackService.buttonPress();
                onPressed!();
              }
              : null,
      onLongPress: onLongPress,
      // Absorb horizontal drags on tablet landscape to prevent PageView interference
      onHorizontalDragStart: isTabletLandscape ? (_) {} : null,
      onHorizontalDragUpdate: isTabletLandscape ? (_) {} : null,
      onHorizontalDragEnd: isTabletLandscape ? (_) {} : null,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        height: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Center the icon vertically and horizontally
            Center(
              child: SvgWidget(
                svgPath,
                height: 24.h,
                width: 24.w,
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              ),
            ),
            // Position depth text BELOW the button area with proper gap
            if (showDepth)
              Positioned(
                bottom: 4.h, // keep within bar bounds
                left: 0,
                right: 0,
                child: Center(child: Text(depthText!, style: depthStyle)),
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
    // On tablet landscape, absorb horizontal drags to prevent them from
    // triggering the PageView half-swipe bug when tapping buttons.
    final isTabletLandscape =
        ResponsiveHelper.isTablet && ResponsiveHelper.isLandscape;

    return GestureDetector(
      onTap:
          onPressed != null
              ? () {
                HapticFeedbackService.buttonPress();
                onPressed!();
              }
              : null,
      onLongPressStart:
          onLongPressStart != null ? (_) => onLongPressStart!() : null,
      onLongPressEnd: onLongPressEnd != null ? (_) => onLongPressEnd!() : null,
      onLongPressCancel: onLongPressEnd,
      // Absorb horizontal drags on tablet landscape to prevent PageView interference
      onHorizontalDragStart: isTabletLandscape ? (_) {} : null,
      onHorizontalDragUpdate: isTabletLandscape ? (_) {} : null,
      onHorizontalDragEnd: isTabletLandscape ? (_) {} : null,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        height: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Icon + badge grouped together so badge hugs the icon, not the full button
            Center(
              child: SizedBox(
                width: 32.w,
                height: 32.h,
                child: Stack(
                  clipBehavior: Clip.none,
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
                    if (showBadge && onPressed != null)
                      Positioned(
                        top: -2.h,
                        right: -2.w,
                        child: _UnseenMovesBadge(),
                      ),
                  ],
                ),
              ),
            ),
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
      onTap:
          onPressed != null
              ? () {
                HapticFeedbackService.buttonPress();
                onPressed!();
              }
              : null,
      child: Container(
        padding: EdgeInsets.all(8.sp),
        child: Icon(iconData, size: 24.ic),
      ),
    );
  }
}
