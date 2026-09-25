import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/player_profile/widgets/lifted_row_menu.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_format.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_section.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:flutter/material.dart';

/// How many decisive games the card lists under the run.
const int kStreakRecentGames = 10;

/// The class's latest decisive games, newest first: the result square (same
/// tones as the run, [streakResultTone]), the opponent, the event and round,
/// the day. Each row opens its game.
class PlayerRecentGames extends StatelessWidget {
  const PlayerRecentGames({
    super.key,
    required this.run,
    required this.onOpenGame,
    this.gameActions,
  });

  final StreakClassRun run;
  final ValueChanged<StreakGame> onOpenGame;

  /// The long-press focus menu for one game row. Null leaves the rows
  /// tap-only.
  final List<LibraryMenuAction> Function(BuildContext rowContext, StreakGame g)?
  gameActions;

  @override
  Widget build(BuildContext context) {
    final games = run.games.reversed.take(kStreakRecentGames).toList();
    if (games.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: StreakSectionHead(
            title: 'Recent games',
            detail: '${run.timeClass.label}, decisive only',
          ),
        ),
        SizedBox(height: 4.w),
        for (final g in games)
          _GameRow(
            key: ValueKey('streak-recent-${g.gameId}'),
            game: g,
            onTap: () => onOpenGame(g),
            actions:
                gameActions == null
                    ? null
                    : (rowContext) => gameActions!(rowContext, g),
          ),
      ],
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({
    super.key,
    required this.game,
    required this.onTap,
    this.actions,
  });

  final StreakGame game;
  final VoidCallback onTap;
  final CardMenuActionsBuilder? actions;

  @override
  Widget build(BuildContext context) {
    final menu = actions;
    final row = _buildRow(context);
    if (menu == null) return row;
    // Long-press lifts the row into the shared focus menu.
    return LiftedRowMenu(actions: menu, onPreviewTap: onTap, child: row);
  }

  Widget _buildRow(BuildContext context) {
    final colors = context.colors;
    final g = game;
    final name = g.opponentName == null
        ? 'Unknown opponent'
        : streakDisplayName(g.opponentName!);
    final event = [
      if (g.tourName != null) g.tourName!,
      if (g.roundName != null) g.roundName!,
    ].join(' · ');
    final day = streakListDay(streakGameDayOf(g));
    final square = 28.w;
    final tone = streakResultTone(context, win: g.isWin);
    final nameStyle = streakText(
      context,
      size: 14,
      line: 18,
      weight: FontWeight.w600,
    );
    final eventStyle = streakText(
      context,
      size: 12,
      line: 16,
      color: colors.textPrimaryMuted,
    );

    return Semantics(
      button: true,
      label:
          '${g.isWin ? 'Won' : 'Lost'} against '
          '${g.opponentTitle != null ? '${g.opponentTitle} ' : ''}$name'
          '${g.opponentRating != null ? ', rated ${g.opponentRating}' : ''}'
          '${event.isNotEmpty ? ', $event' : ''}'
          '${day != null ? ', $day' : ''}. Opens the game.',
      excludeSemantics: true,
      child: TappableScale(
        scaleDown: 0.98,
        onTap: onTap,
        child: Container(
          color: Colors.transparent,
          constraints: BoxConstraints(minHeight: 60.w),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.w),
          child: Row(
            children: [
              Container(
                width: square,
                height: square,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.fill,
                  borderRadius: BorderRadius.circular(3.w),
                ),
                child: Text(
                  g.isWin ? '1' : '0',
                  style: streakText(
                    context,
                    size: 13,
                    line: 13,
                    weight: FontWeight.w700,
                    color: tone.ink,
                    tabular: true,
                  ).copyWith(leadingDistribution: TextLeadingDistribution.even),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The name gives way; the rating never splits, so a long
                    // name can't leave a half-shown Elo.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (g.opponentTitle != null)
                                  TextSpan(
                                    text: '${g.opponentTitle} ',
                                    style: TextStyle(
                                      color: colors.titleAccent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                TextSpan(text: name),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: nameStyle,
                          ),
                        ),
                        if (g.opponentRating != null) ...[
                          SizedBox(width: 5.w),
                          Text(
                            '${g.opponentRating}',
                            maxLines: 1,
                            softWrap: false,
                            style: nameStyle.copyWith(
                              color: colors.textPrimaryMuted,
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (g.tourName != null || g.roundName != null) ...[
                      SizedBox(height: 2.w),
                      // The event name gives way; the round stays whole
                      // (capped at half the line for freak-long labels).
                      LayoutBuilder(
                        builder: (context, box) => Row(
                          children: [
                            if (g.tourName != null)
                              Flexible(
                                child: Text(
                                  g.tourName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: eventStyle,
                                ),
                              ),
                            if (g.roundName != null)
                              g.tourName == null
                                  ? Flexible(
                                    child: Text(
                                      g.roundName!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: eventStyle,
                                    ),
                                  )
                                  : ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: box.maxWidth / 2,
                                    ),
                                    child: Text(
                                      ' · ${g.roundName}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: eventStyle,
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (day != null) ...[
                SizedBox(width: 12.w),
                Text.rich(
                  streakFigures(day),
                  maxLines: 1,
                  style: streakText(
                    context,
                    size: 12,
                    line: 16,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
