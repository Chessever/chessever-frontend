import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';

/// Result card over the bottom of the board once a clip reaches its last ply.
///
/// "Next game" fills left to right over the auto-advance window driven by
/// [countdown]; reaching the end moves the feed on by itself.
class FeedEndCard extends StatelessWidget {
  const FeedEndCard({
    required this.result,
    required this.detail,
    required this.countdown,
    required this.onReplay,
    required this.onNext,
    super.key,
  });

  final String result;
  final String detail;
  final Animation<double> countdown;
  final VoidCallback onReplay;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('feed_end_card'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: colors.popup.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (result.isNotEmpty) ...[
                Text(
                  result,
                  style: AppTypography.displayXsBold.copyWith(
                    fontSize: 24,
                    height: 28 / 24,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmMedium.copyWith(
                    fontSize: 13,
                    height: 18 / 13,
                    color: colors.textPrimaryMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _EndButton(
                  label: 'Replay',
                  fill: colors.surfaceRecessed,
                  ink: colors.textPrimary,
                  weight: FontWeight.w500,
                  onTap: onReplay,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _EndButton(
                  label: 'Next game',
                  fill: colors.textPrimary,
                  ink: colors.background,
                  weight: FontWeight.w700,
                  onTap: onNext,
                  progress: countdown,
                  progressColor: _countdownFill(
                    plate: colors.textPrimary,
                    ink: colors.background,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The auto-advance fill: the label's own [ink] laid over the [plate] at the
/// lowest alpha whose edge reads at 3:1 against the unfilled plate (WCAG
/// 1.4.11) while the [ink] label crossing it keeps 4.5:1. Resolves to 0.38 on
/// paper and 0.45 on black, so it tracks the tokens instead of a guess.
Color _countdownFill({required Color plate, required Color ink}) {
  Color at(double alpha) =>
      Color.alphaBlend(ink.withValues(alpha: alpha), plate);
  for (var step = 20; step <= 80; step++) {
    final fill = at(step / 100);
    if (wcagContrast(fill, plate) >= 3.1 && wcagContrast(ink, fill) >= 4.5) {
      return fill;
    }
  }
  return at(0.4);
}

/// Flat 44px button. The press is [FeedPressable]'s: it gives a little and
/// dims, nothing jumps. [progress] paints the auto-advance fill under the
/// label.
class _EndButton extends StatelessWidget {
  const _EndButton({
    required this.label,
    required this.fill,
    required this.ink,
    required this.weight,
    required this.onTap,
    this.progress,
    this.progressColor,
  });

  final String label;
  final Color fill;
  final Color ink;
  final FontWeight weight;
  final VoidCallback onTap;
  final Animation<double>? progress;
  final Color? progressColor;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    return FeedPressable(
      semanticsLabel: label,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 44,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: fill),
              if (progress != null)
                AnimatedBuilder(
                  animation: progress,
                  builder: (context, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress.value.clamp(0.0, 1.0),
                    child: ColoredBox(color: progressColor!),
                  ),
                ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: AppTypography.textSmMedium.copyWith(
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: weight,
                        color: ink,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
