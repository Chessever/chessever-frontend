import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';


class ChessProgressBar extends StatelessWidget {
  const ChessProgressBar({
    required this.asyncValue,
    super.key,
  });

  final AsyncValue<double> asyncValue;

  @override
  Widget build(BuildContext context) {
    final isEvaluating = asyncValue.isLoading;
    final progress = isEvaluating ? 0.0 : asyncValue.value!;
    return SizedBox(
      width: 48.w,
      height: 12.h,
      child: Stack(
        children: [
          // Background container
          Container(
            width: 48.w,
            height: 12.h,
            decoration: BoxDecoration(
              color: kBlack2Color,
              borderRadius: BorderRadius.all(Radius.circular(4.br)),
            ),
          ),
          // Progress container
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: (48.w * progress).clamp(0.0, 48.w),
            height: 12.h,
            decoration: BoxDecoration(
              color: kWhiteColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4.br),
                bottomLeft: Radius.circular(4.br),
                topRight:
                    progress >= 0.99 ? Radius.circular(4.br) : Radius.zero,
                bottomRight:
                    progress >= 0.99 ? Radius.circular(4.br) : Radius.zero,
              ),
            ),
          ),
          // Loading indicator when evaluating
          if (isEvaluating)
            Container(
              width: 48.w,
              height: 12.h,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.3),
                borderRadius: BorderRadius.all(Radius.circular(4.br)),
              ),
              child: Center(
                child: SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
