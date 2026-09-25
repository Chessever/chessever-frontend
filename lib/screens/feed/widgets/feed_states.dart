import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// First-load placeholder laid out on the exact [FeedLayout] geometry, so the
/// real board drops into the space the skeleton board already occupies.
class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tone = colors.skeleton;
    final toneDeep = colors.surface;
    return Semantics(
      label: 'Loading Feed',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final l = FeedLayout.resolve(
            constraints,
            MediaQuery.textScalerOf(context),
            evalWidth: 20.w,
          );
          Widget bar(double width, double height) => Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(3),
            ),
          );
          Widget playerRow(double nameWidth) => SizedBox(
            height: l.rowHeight,
            child: Row(
              children: [
                SizedBox(width: l.evalWidth + 5),
                bar(12, 10),
                const SizedBox(width: 8),
                bar(nameWidth, 10),
              ],
            ),
          );

          return Padding(
            padding: EdgeInsets.only(left: l.contentLeft),
            child: SizedBox(
              width: l.contentWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: FeedLayout.topGap),
                  // The post header is one line.
                  SizedBox(
                    height: l.metaHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: bar(180, 10),
                    ),
                  ),
                  const SizedBox(height: FeedLayout.gap),
                  playerRow(150),
                  const SizedBox(height: FeedLayout.gap),
                  Row(
                    children: [
                      Container(
                        width: l.evalWidth,
                        height: l.board,
                        color: toneDeep,
                      ),
                      SizedBox.square(
                        dimension: l.board,
                        child: CustomPaint(
                          painter: _SkeletonBoardPainter(
                            light: tone,
                            dark: toneDeep,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FeedLayout.gap),
                  playerRow(170),
                  const SizedBox(height: FeedLayout.infoGap),
                  SizedBox(
                    height: l.infoHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: bar(72, 14),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SkeletonBoardPainter extends CustomPainter {
  _SkeletonBoardPainter({required this.light, required this.dark});

  final Color light;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    final sq = size.width / 8;
    final lightPaint = Paint()..color = light;
    final darkPaint = Paint()..color = dark;
    for (var r = 0; r < 8; r++) {
      for (var f = 0; f < 8; f++) {
        canvas.drawRect(
          Rect.fromLTWH(f * sq, r * sq, sq, sq),
          (r + f).isEven ? lightPaint : darkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SkeletonBoardPainter old) =>
      old.light != light || old.dark != dark;
}

/// Calm full-page message for an empty feed or a failed load.
class FeedMessage extends StatelessWidget {
  const FeedMessage({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.textLgBold.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppTypography.textSmRegular.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            FeedPressable(
              semanticsLabel: actionLabel,
              onTap: onAction,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.surfaceRecessed,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  actionLabel,
                  style: AppTypography.textSmMedium.copyWith(
                    height: 1.2,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
