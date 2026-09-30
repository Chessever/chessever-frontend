import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_format.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_section.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:flutter/material.dart';

/// Wins shown before the run folds behind a "+N" square (the site's fold).
const int kStreakRunFold = 14;

const int _kColumns = 7;

/// One cell of the run grid: a game, or the fold standing in for [hidden]
/// earlier wins.
@immutable
class StreakRunCell {
  const StreakRunCell.game(StreakGame this.game) : hidden = 0;
  const StreakRunCell.fold(this.hidden) : game = null;

  final StreakGame? game;
  final int hidden;

  bool get isFold => game == null;
}

/// The run as the site lists it: the anchor loss first, then every win. Past
/// [kStreakRunFold] wins the earlier ones collapse into one "+N" cell after
/// the loss, unless [expanded].
List<StreakRunCell> streakRunCells(
  StreakClassRun run, {
  bool expanded = false,
}) {
  final games = run.currentRunGames;
  final wins = [
    for (final g in games)
      if (g.isWin) g,
  ];
  final hidden = !expanded && wins.length > kStreakRunFold
      ? wins.length - kStreakRunFold
      : 0;
  if (hidden == 0) return [for (final g in games) StreakRunCell.game(g)];
  StreakGame? anchor;
  for (final g in games) {
    if (!g.isWin) {
      anchor = g;
      break;
    }
  }
  return [
    if (anchor != null) StreakRunCell.game(anchor),
    StreakRunCell.fold(hidden),
    for (final g in wins.sublist(hidden)) StreakRunCell.game(g),
  ];
}

/// "This run": a grid of squares, the anchor loss a plain tile with a red 0,
/// the wins a quiet green tint with the latest one step deeper (see
/// [streakResultTone]). Each square opens its game; the day it was played
/// sits under it, every label at one size.
class PlayerRunStrip extends StatefulWidget {
  const PlayerRunStrip({
    super.key,
    required this.run,
    required this.onOpenGame,
  });

  final StreakClassRun run;
  final ValueChanged<StreakGame> onOpenGame;

  @override
  State<PlayerRunStrip> createState() => _PlayerRunStripState();
}

class _PlayerRunStripState extends State<PlayerRunStrip> {
  bool _expanded = false;

  @override
  void didUpdateWidget(PlayerRunStrip old) {
    super.didUpdateWidget(old);
    if (old.run.timeClass != widget.run.timeClass) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final cells = streakRunCells(run, expanded: _expanded);
    if (cells.isEmpty) return const SizedBox.shrink();
    final live = run.currentStreak > 0;
    // The year rides along when the run began before this one: a long
    // classical run often spans seasons, and 'since Mar 4' would misdate it.
    final since = live ? streakListDay(run.streakStartGameDay) : null;
    var lastWin = -1;
    for (var i = cells.length - 1; i >= 0; i--) {
      if (cells[i].game?.isWin ?? false) {
        lastWin = i;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StreakSectionHead(
          title: live ? 'This run' : 'Where it restarted',
          detail: since == null ? null : 'since $since',
        ),
        SizedBox(height: 12.w),
        LayoutBuilder(
          builder: (context, box) {
            final gap = 4.w;
            final side = (box.maxWidth - gap * (_kColumns - 1)) / _kColumns;
            final labels = _RunLabels.fit(
              context,
              texts: [for (final c in cells) _cellLabel(c)],
              side: side,
            );
            return Wrap(
              spacing: gap,
              runSpacing: 10.w,
              children: [
                for (var i = 0; i < cells.length; i++)
                  SizedBox(
                    width: side,
                    child: _RunCell(
                      cell: cells[i],
                      side: side,
                      label: labels,
                      latest: i == lastWin,
                      onTap: () {
                        final g = cells[i].game;
                        if (g == null) {
                          HapticFeedbackService.selection();
                          setState(() => _expanded = true);
                        } else {
                          widget.onOpenGame(g);
                        }
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The words under a square: the day, or 'earlier' under the fold.
String _cellLabel(StreakRunCell c) {
  final g = c.game;
  return g == null ? 'earlier' : streakSquareLabel(g);
}

/// One size for every label in the grid. A per-square FittedBox shrank each
/// day by its own width, so at 360dp with large text 'May 30' sat smaller
/// than 'Sep 5' and neighbours ran edge to edge. Here the widest label sets
/// the scale for all of them, a gutter stays between squares, and the row
/// keeps the height of an unshrunk line.
@immutable
class _RunLabels {
  const _RunLabels({
    required this.style,
    required this.scaler,
    required this.inset,
    required this.height,
  });

  factory _RunLabels.fit(
    BuildContext context, {
    required List<String> texts,
    required double side,
  }) {
    // Tabular for the whole label: it is only a month, a space and a day, so
    // the figures are all it changes, and the fit and the paint share one
    // style.
    final style = streakText(
      context,
      size: 11,
      line: 14,
      color: context.colors.textSecondary,
      tabular: true,
    );
    final ambient = MediaQuery.textScalerOf(context);
    final inset = 2.w;
    final room = side - inset * 2;
    final direction = Directionality.of(context);
    var widest = 0.0;
    for (final t in texts) {
      if (t.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: t, style: style),
        textDirection: direction,
        textScaler: ambient,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    final size = style.fontSize!;
    final scaled = ambient.scale(size);
    final fit = widest > room && room > 0 ? room / widest : 1.0;
    return _RunLabels(
      style: style,
      scaler: TextScaler.linear(scaled / size * fit),
      inset: inset,
      height: scaled * style.height!,
    );
  }

  final TextStyle style;

  /// The ambient text scale times the grid's fit.
  final TextScaler scaler;

  /// Clear space each side of a label, so neighbours never touch.
  final double inset;

  /// The row's height: one line at the ambient scale, before the fit.
  final double height;
}

class _RunCell extends StatelessWidget {
  const _RunCell({
    required this.cell,
    required this.side,
    required this.label,
    required this.latest,
    required this.onTap,
  });

  final StreakRunCell cell;
  final double side;
  final _RunLabels label;
  final bool latest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final g = cell.game;
    final Color? fill;
    final Color ink;
    final String mark;
    final String semantics;
    final text = _cellLabel(cell);
    if (g == null) {
      // The fold is a control, not a result: an empty outlined slot, so it
      // never reads as another score beside the anchor loss's filled 0.
      fill = null;
      ink = colors.textPrimaryMuted;
      mark = '+${cell.hidden}';
      semantics =
          'Show ${cell.hidden} earlier ${cell.hidden == 1 ? 'win' : 'wins'}';
    } else if (!g.isWin) {
      final tone = streakResultTone(context, win: false);
      fill = tone.fill;
      ink = tone.ink;
      mark = '0';
      semantics =
          'Loss${_when(g)}, the run starts after it. '
          '${_versus(g)}Opens the game.';
    } else {
      final tone = streakResultTone(context, win: true, latest: latest);
      fill = tone.fill;
      ink = tone.ink;
      mark = '1';
      semantics =
          'Win ${g.streakAfter > 0 ? g.streakAfter : ''}${_when(g)}. '
          '${_versus(g)}Opens the game.';
    }

    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      // excludeSemantics drops the GestureDetector's tap action, so the
      // node carries it itself or screen readers cannot activate the square.
      onTap: onTap,
      child: TappableScale(
        key: g == null
            ? const ValueKey('streak-run-fold')
            : ValueKey('streak-run-${g.gameId}'),
        scaleDown: 0.97,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: side,
              height: side,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                border: g == null
                    ? Border.all(color: colors.dividerStrong, width: 1.w)
                    : null,
                borderRadius: BorderRadius.circular(3.w),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 3.w),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    mark,
                    maxLines: 1,
                    style:
                        streakText(
                          context,
                          size: 13,
                          line: 13,
                          weight: FontWeight.w700,
                          color: ink,
                          tabular: true,
                        ).copyWith(
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 6.w),
            SizedBox(
              width: side,
              height: label.height,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: label.inset),
                child: Align(
                  alignment: Alignment.topCenter,
                  // The grid fit already sizes the label to its room; this
                  // only guards against a sub-pixel rounding overflow.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      text.isEmpty ? ' ' : text,
                      maxLines: 1,
                      softWrap: false,
                      textScaler: label.scaler,
                      style: label.style,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Spoken only: the event, its round and the full day (with the year when
  /// it is not this one), so the date under the square is never ambiguous.
  static String _when(StreakGame g) {
    final day = streakListDay(streakGameDayOf(g));
    final parts = [?g.tourName, ?g.roundName, ?day];
    return parts.isEmpty ? '' : ', ${parts.join(', ')}';
  }

  static String _versus(StreakGame g) {
    final name = g.opponentName;
    if (name == null) return '';
    final who = [
      if (g.opponentTitle != null) g.opponentTitle!,
      streakDisplayName(name),
    ].join(' ');
    return 'Against $who. ';
  }
}
