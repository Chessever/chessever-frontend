import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';

class GenericErrorWidget extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const GenericErrorWidget({super.key, this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Call sites pass copy that already reads as a full sentence (usually via
    // `userFacingError`), so it is rendered verbatim — an "Error: " prefix in
    // front of "No internet connection." reads as a stutter.
    final text =
        (message != null && message!.isNotEmpty)
            ? message!
            : 'Something went wrong';

    // Deliberately plain: fixed logical pixels and no ResponsiveHelper. This is
    // the fallback that renders when something else already failed, so it must
    // not carry dependencies that can fail with it.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: colors.brand,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
