import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';

class BracketLoadingView extends StatelessWidget {
  const BracketLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading bracket',
      child: SkeletonWidget(
        child: ClipRect(
          child: LayoutBuilder(
            builder:
                (context, constraints) => Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    ..._skeletonColumn(context, left: 20, cardCount: 4),
                    ..._skeletonColumn(
                      context,
                      left: 296,
                      cardCount: 2,
                      topInset: 53,
                    ),
                  ],
                ),
          ),
        ),
      ),
    );
  }

  List<Widget> _skeletonColumn(
    BuildContext context, {
    required double left,
    required int cardCount,
    double topInset = 0,
  }) {
    const headerTop = 22.0;
    final firstCardTop = 60.0 + topInset;
    return [
      Positioned(
        left: left,
        top: headerTop,
        width: 112,
        height: 16,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.skeleton,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
      for (var index = 0; index < cardCount; index += 1)
        Positioned(
          left: left,
          top: firstCardTop + index * 110,
          width: 220,
          height: 92,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.divider),
            ),
          ),
        ),
    ];
  }
}

class BracketEmptyView extends StatelessWidget {
  const BracketEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      key: const ValueKey('knockout-bracket-empty'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: colors.brand.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.brand.withValues(alpha: 0.18)),
              ),
              child: Icon(
                Icons.account_tree_outlined,
                color: colors.brand,
                size: 27,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Bracket pairings aren’t available yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'InterDisplay',
                color: colors.textPrimary,
                fontSize: 15,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'They’ll appear here as the tournament publishes them.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'InterDisplay',
                color: colors.textSecondary,
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BracketErrorView extends StatelessWidget {
  const BracketErrorView({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      key: const ValueKey('knockout-bracket-error'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GenericErrorWidget(),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'InterDisplay',
                color: colors.textSecondary,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              key: const ValueKey('knockout-bracket-retry'),
              onPressed: () {
                HapticFeedbackService.buttonPress();
                onRetry();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                foregroundColor: colors.textPrimary,
                backgroundColor: colors.surfaceRecessed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
