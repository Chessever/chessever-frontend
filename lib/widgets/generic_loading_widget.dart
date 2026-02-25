import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Clean loading indicator that matches app design.
/// Use [size] to control the indicator size.
/// Use [centered] to wrap in a Center widget.
class GenericLoadingWidget extends StatelessWidget {
  const GenericLoadingWidget({
    super.key,
    this.size,
    this.color,
    this.centered = false,
    this.strokeWidth,
  });

  final double? size;
  final Color? color;
  final bool centered;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final indicator = SizedBox(
      width: size ?? 28.w,
      height: size ?? 28.w,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth ?? 2.5,
        valueColor: AlwaysStoppedAnimation<Color>(color ?? kPrimaryColor),
      ),
    );

    if (centered) {
      return Center(child: indicator);
    }
    return indicator;
  }
}

/// Full-page loading state with optional message.
/// Use this for screen-level loading states.
class FullPageLoading extends StatelessWidget {
  const FullPageLoading({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GenericLoadingWidget(size: 32),
          if (message != null) ...[
            SizedBox(height: 16.h),
            Text(
              message!,
              style: TextStyle(
                color: kWhiteColor.withValues(alpha: 0.7),
                fontSize: 14.sp,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
