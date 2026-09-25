import 'package:chessever2/screens/my_space/widgets/pixel_flame.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_format.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/material.dart';

/// Classical · Rapid · Blitz, three equal cards: the live count (with a still
/// flame once it is on the wall) and the best ever. Tapping a card switches
/// the whole page to that class.
class PlayerClassScoreboard extends StatelessWidget {
  const PlayerClassScoreboard({
    super.key,
    required this.player,
    required this.selected,
    required this.onSelect,
  });

  final PlayerStreaks player;
  final StreakTimeClass selected;
  final ValueChanged<StreakTimeClass> onSelect;

  @override
  Widget build(BuildContext context) {
    // The cards grow with the reader's text size instead of clipping at a
    // fixed height; IntrinsicHeight + stretch keeps all three the same height
    // so the counts and the "Best N" lines stay on one shared row.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tc in StreakTimeClass.values) ...[
            if (tc.index > 0) SizedBox(width: 8.w),
            Expanded(
              child: _ClassCard(
                timeClass: tc,
                run: player.run(tc),
                selected: tc == selected,
                onTap: () => onSelect(tc),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({
    required this.timeClass,
    required this.run,
    required this.selected,
    required this.onTap,
  });

  final StreakTimeClass timeClass;
  final StreakClassRun? run;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final n = run?.currentStreak ?? 0;
    final hot = n >= kStreakWallMin;
    final numberStyle = streakText(
      context,
      size: 28,
      line: 28,
      weight: FontWeight.w700,
      tabular: true,
      color: run != null && n > 0
          ? colors.textPrimary
          : context.textInk(0.5),
    );
    final sub = run == null ? 'No games' : 'Best ${run!.bestStreak}';

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${timeClass.label}: '
          '${run == null ? 'no games' : '$n in a row, best ${run!.bestStreak}'}',
      excludeSemantics: true,
      child: TappableScale(
        key: ValueKey('streak-class-${timeClass.wire}'),
        scaleDown: 0.97,
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: 96.w),
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: selected ? colors.surfaceRecessed : colors.surface,
            borderRadius: BorderRadius.circular(4.w),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StreakClassIcon(timeClass: timeClass, size: 13.w),
                  SizedBox(width: 6.w),
                  Flexible(
                    child: Text(
                      timeClass.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: streakText(
                        context,
                        size: 12,
                        line: 16,
                        color: selected
                            ? colors.textPrimary
                            : colors.textPrimaryMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (hot)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: Padding(
                            padding: EdgeInsets.only(right: 5.w),
                            // The design keeps the scoreboard flames still;
                            // only the hero burns.
                            child: TickerMode(
                              enabled: false,
                              child: PixelFlame(streak: n, size: 22.w),
                            ),
                          ),
                        ),
                      TextSpan(text: run == null ? '–' : '$n'),
                    ],
                  ),
                  maxLines: 1,
                  style: numberStyle,
                ),
              ),
              SizedBox(height: 6.w),
              Text.rich(
                streakFigures(sub),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: streakText(
                  context,
                  size: 11,
                  line: 14,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The app's time-control mark (owl, rabbit, bolt). [TimeControlGlyph] swaps
/// in the paper twins on the light theme, so all three keep their contrast.
class StreakClassIcon extends StatelessWidget {
  const StreakClassIcon({
    super.key,
    required this.timeClass,
    required this.size,
  });

  final StreakTimeClass timeClass;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = switch (timeClass) {
      StreakTimeClass.standard => PngAsset.classicalIcon,
      StreakTimeClass.rapid => PngAsset.rapidIcon,
      StreakTimeClass.blitz => PngAsset.blitzIcon,
    };
    return TimeControlGlyph(asset, size: size);
  }
}
