import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';

/// Decorative backing cards never own taps or accessibility focus.
class NewsGroupCard extends StatelessWidget {
  const NewsGroupCard({super.key, required this.news, required this.child});
  final FeedNews news;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final count = news.groupArticleCount;
    if (count <= 1 || news.publisher.isPartner) return child;
    final layers = count == 2 ? 1 : 2;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = layers; i >= 1; i--)
          Positioned.fill(
            left: i * 4,
            top: i * 4,
            right: -i * 4,
            bottom: -i * 4,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: context.colors.textSecondary.withValues(
                        alpha: 0.35,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        child,
        Positioned(
          top: 10,
          left: 10,
          right: 10,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.topLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.background,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  child: Text(
                    '$count articles · Latest',
                    style: AppTypography.textXsMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
