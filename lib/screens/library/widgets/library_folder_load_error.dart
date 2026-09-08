import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Shared recovery action for Library destination pickers.
class LibraryFolderLoadError extends StatelessWidget {
  const LibraryFolderLoadError({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(20.sp),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Couldn’t load your databases',
            style: AppTypography.textSmMedium.copyWith(color: kRedColor),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 6.h),
          Text(
            'Check your connection and try again.',
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.65),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8.h),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
