import 'package:chessever2/screens/my_space/widgets/pixel_flame.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_format.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Luminance greyscale for the cold flame in light mode.
const ColorFilter _ash = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// Flame + a numeral that fills the width + the level word: the one number
/// the page exists to show. A cold class keeps the flame, dimmed, and says so
/// in words instead of a level.
class PlayerStreakHero extends StatelessWidget {
  const PlayerStreakHero({
    super.key,
    required this.run,
    required this.timeClass,
  });

  /// Null when the player has no decisive games in [timeClass].
  final StreakClassRun? run;
  final StreakTimeClass timeClass;

  @override
  Widget build(BuildContext context) {
    final n = run?.currentStreak ?? 0;
    final best = run?.bestStreak ?? 0;
    final live = n > 0;
    final label = timeClass.label.toLowerCase();
    // A 104pt numeral grows past the width at large accessibility sizes; the
    // flame and the words underneath still scale.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15);

    final flame = Padding(
      padding: EdgeInsets.only(right: 10.w),
      // A cold class keeps its flame, dimmed and still.
      child: TickerMode(
        enabled: live,
        child: live
            ? PixelFlame(streak: n, size: 80.w)
            : context.isLightTheme
            // Faded red over the pale page reads as a pink smudge, so in light
            // the cold flame goes to grey ash. Dark keeps its dull embers.
            ? ColorFiltered(
                colorFilter: _ash,
                child: Opacity(
                  opacity: 0.45,
                  child: PixelFlame(streak: n, size: 80.w),
                ),
              )
            : Opacity(
                opacity: 0.35,
                child: PixelFlame(streak: n, size: 80.w),
              ),
      ),
    );

    final String word;
    final String line;
    if (live) {
      word = streakLevel(n).word;
      line = '${streakWinsWord(timeClass, n)} in a row';
    } else {
      word = 'No live run';
      line = best > 0
          ? 'Best ever $best ${streakWinsWord(timeClass, best)} in a row'
          : run == null
          ? 'No decisive $label games yet'
          : 'No $label run yet';
    }

    return Semantics(
      container: true,
      label: live
          ? '$n ${streakWinsWord(timeClass, n)} in a row. $word.'
          : '$word in $label. $line.',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                // Baseline alignment puts the flame's bottom on the digits'
                // baseline, so both stand on one line at any size.
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: flame,
                ),
                TextSpan(text: '$n'),
              ],
            ),
            key: const ValueKey('streak-player-count'),
            textScaler: scaler,
            maxLines: 1,
            style: streakDisplay(
              context,
              size: 104,
              letterSpacing: 2,
              color: live
                  ? context.colors.textPrimary
                  : context.colors.textPrimaryMuted,
            ),
          ),
          SizedBox(height: 10.w),
          Text(
            word,
            textAlign: TextAlign.center,
            style: streakText(
              context,
              size: 16,
              line: 20,
              weight: FontWeight.w700,
              color: live
                  ? StreakFire.warmInk(context)
                  : context.colors.textSecondary,
            ),
          ),
          SizedBox(height: 2.w),
          Text.rich(
            streakFigures(line),
            key: const ValueKey('streak-player-line'),
            textAlign: TextAlign.center,
            style: streakText(
              context,
              size: 13,
              line: 18,
              color: context.colors.textPrimaryMuted,
            ),
          ),
        ],
      ),
    );
  }
}
