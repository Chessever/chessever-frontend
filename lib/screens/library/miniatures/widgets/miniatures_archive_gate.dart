import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryPadlock;
import 'package:chessever2/screens/library/miniatures/miniatures_access.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart'
    show WallPressable;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The Miniatures date control while the archive is locked:
/// "‹  Today · Wed 23 Sep  ›".
///
/// Today is the free day, so the label always reads Today. The earlier-day
/// chevron carries the For You padlock and opens the paywall ([onEarlier]);
/// the next-day chevron is inert, since Today is the newest day there is.
/// The control stays on screen the whole time, so the boundary is visible
/// before anyone taps it.
class MiniaturesDateControl extends StatelessWidget {
  const MiniaturesDateControl({super.key, required this.onEarlier, this.now});

  final VoidCallback onEarlier;

  /// Pins "today" in tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final date = DateFormat('EEE d MMM').format(now ?? DateTime.now());
    // Both chevrons get the same slot, so the label sits dead centre.
    final side = 56.w;

    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Earlier days, in the Miniatures archive, Premium',
          excludeSemantics: true,
          child: WallPressable(
            key: const ValueKey('miniatures_date_earlier'),
            pressScale: 0.94,
            onTap: onEarlier,
            child: SizedBox(
              width: side,
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 22.sp,
                    color: colors.textSecondary,
                  ),
                  const DiscoveryPadlock(),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Semantics(
            label: 'Today, $date',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Today',
                    style: AppTypography.textSmMedium.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: '  ·  $date',
                    style: AppTypography.textSmRegular.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        Semantics(
          button: true,
          enabled: false,
          label: 'Next day',
          excludeSemantics: true,
          child: SizedBox(
            width: side,
            height: 44,
            child: Center(
              child: Icon(
                Icons.chevron_right_rounded,
                size: 22.sp,
                color: colors.dividerStrong,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Where a locked Miniatures list ends: one honest sentence and the Premium
/// line, "Explore the Miniatures archive", as the target.
///
/// [todayEmpty] says there is nothing to show for Today, so the sentence
/// leads with that instead of pointing at a list that is not there.
class MiniaturesArchiveBoundary extends StatelessWidget {
  const MiniaturesArchiveBoundary({
    super.key,
    required this.onExplore,
    this.todayEmpty = false,
  });

  final VoidCallback onExplore;
  final bool todayEmpty;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      container: true,
      label: 'Miniatures archive',
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (todayEmpty) ...[
              Text(
                'No miniatures yet today',
                style: AppTypography.textSmMedium.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              SizedBox(height: 4.h),
            ],
            Text(
              'Earlier days are in the Premium archive.',
              style: AppTypography.textSmRegular.copyWith(
                color: colors.textSecondary,
                height: 1.42,
              ),
            ),
            Semantics(
              button: true,
              label: '$kMiniaturesArchiveCta, Premium',
              excludeSemantics: true,
              child: WallPressable(
                key: const ValueKey('miniatures_archive_cta'),
                pressScale: 0.98,
                onTap: onExplore,
                child: ConstrainedBox(
                  // 44dp tap target, independent of the scaled text size.
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      const DiscoveryPadlock(width: 9, height: 11),
                      SizedBox(width: 8.w),
                      Flexible(
                        child: Text(
                          kMiniaturesArchiveCta,
                          style: AppTypography.textSmMedium.copyWith(
                            color: context.colors.accentText,
                          ),
                        ),
                      ),
                    ],
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
