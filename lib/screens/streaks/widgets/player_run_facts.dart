import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_format.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// The run in three facts, one table: the strongest opponent beaten in it,
/// the average opponent beaten, and the best run this class has on record.
/// Rows with nothing to say (no live run) are left out, never shown as "–".
class PlayerRunFacts extends StatelessWidget {
  const PlayerRunFacts({super.key, required this.run});

  final StreakClassRun run;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final live = run.currentStreak > 0;
    final valueStyle = streakText(
      context,
      size: 13,
      line: 18,
      weight: FontWeight.w700,
    );
    final best = run.bestStreak;
    final bestAt = run.bestStreakAt;

    final rows = <Widget>[
      if (live && (run.runOppBest != null || run.runOppBestName != null))
        _FactRow(
          key: const ValueKey('streak-fact-strongest'),
          label: 'Strongest win',
          value: Text.rich(
            TextSpan(
              children: [
                if (run.runOppBestTitle != null)
                  TextSpan(
                    text: '${run.runOppBestTitle} ',
                    style: TextStyle(color: colors.titleAccent),
                  ),
                if (run.runOppBestName != null)
                  TextSpan(text: streakDisplayName(run.runOppBestName!)),
                if (run.runOppBest != null)
                  streakFigures(
                    run.runOppBestName != null
                        ? '  ${run.runOppBest}'
                        : '${run.runOppBest}',
                    style: TextStyle(
                      color: run.runOppBestName != null
                          ? colors.textPrimaryMuted
                          : null,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: valueStyle,
          ),
        ),
      if (live && run.runOppAvg != null)
        _FactRow(
          key: const ValueKey('streak-fact-average'),
          label: 'Average opponent beaten',
          value: Text.rich(
            streakFigures('${run.runOppAvg}'),
            textAlign: TextAlign.right,
            style: valueStyle,
          ),
        ),
      _FactRow(
        key: const ValueKey('streak-fact-best'),
        label: 'Best ever',
        value: Text.rich(
          streakFigures(
            best <= 0
                ? 'None yet'
                : bestAt == null
                ? '$best'
                : '$best · ${streakMonthYear(bestAt.toUtc())}',
          ),
          textAlign: TextAlign.right,
          style: valueStyle,
        ),
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(4.w),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.w),
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }
}

/// Widest the label may run, as a share of the row. Below it the label keeps
/// its natural width and the value takes the rest; at large text sizes the
/// label wraps (then ellipsizes) inside it, so the value always keeps room.
const double _kLabelMaxShare = 0.6;

class _FactRow extends StatelessWidget {
  const _FactRow({super.key, required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final gap = 16.w;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 40.w),
      // Centres the row in the 40dp slot; the row itself is baseline-aligned
      // so a wrapped label's first line sits level with the value.
      child: Align(
        alignment: Alignment.centerLeft,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final labelMax = (constraints.maxWidth - gap) * _kLabelMaxShare;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: labelMax < 0 ? 0 : labelMax,
                  ),
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: streakText(
                      context,
                      size: 13,
                      line: 18,
                      color: context.colors.textPrimaryMuted,
                    ),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: Align(alignment: Alignment.centerRight, child: value),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
