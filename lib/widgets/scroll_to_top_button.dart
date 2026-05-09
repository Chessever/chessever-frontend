import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// A floating action button that appears when scrolled past a threshold
/// and animates the scroll back to top when tapped.
class ScrollToTopButton extends StatefulWidget {
  final ScrollController scrollController;
  final double showThreshold;

  const ScrollToTopButton({
    super.key,
    required this.scrollController,
    this.showThreshold = 300,
  });

  @override
  State<ScrollToTopButton> createState() => _ScrollToTopButtonState();
}

class _ScrollToTopButtonState extends State<ScrollToTopButton> {
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final shouldShow = widget.scrollController.offset > widget.showThreshold;
    if (shouldShow != _isVisible) {
      setState(() {
        _isVisible = shouldShow;
      });
    }
  }

  void _scrollToTop() {
    HapticFeedback.mediumImpact();
    widget.scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_isVisible,
        child: Padding(
          padding: EdgeInsets.only(bottom: 16.h, right: 16.w),
          child:
              GestureDetector(
                    onTap: _scrollToTop,
                    child: Container(
                      width: 48.w,
                      height: 48.h,
                      decoration: BoxDecoration(
                        color: kPrimaryColor,
                        borderRadius: BorderRadius.circular(24.br),
                        boxShadow: [
                          BoxShadow(
                            color: kPrimaryColor.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: context.colors.textPrimary,
                        size: 28.sp,
                      ),
                    ),
                  )
                  .animate(target: _isVisible ? 1 : 0)
                  .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1))
                  .fadeIn(),
        ),
      ),
    );
  }
}
