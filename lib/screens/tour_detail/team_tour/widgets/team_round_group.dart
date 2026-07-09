import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart' show kGreenColor2, kRedColor;
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// One collapsible match for a team: soft card with team names flanking a
/// centered score pill (Games-tab style), that expands — with a motor spring —
/// to the match's individual games as [GameCardWrapperWidget] cards.
/// Shared by the expandable team standings row and the team score card.
class TeamRoundGroup extends StatefulWidget {
  final TeamMatch match;

  /// Selected team (shown on the left of the matchup).
  final String teamName;

  /// 0-based position in the sorted match list (kept for stable keys / ordering).
  final int index;

  const TeamRoundGroup({
    super.key,
    required this.match,
    required this.teamName,
    required this.index,
  });

  @override
  State<TeamRoundGroup> createState() => _TeamRoundGroupState();
}

class _TeamRoundGroupState extends State<TeamRoundGroup> {
  bool _expanded = false;
  bool _renderBody = false;

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) _renderBody = true;
    });
    if (!_expanded) {
      // Keep the games mounted through the collapse spring, then drop them so
      // a collapsed team doesn't hold dozens of live game cards.
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_expanded) setState(() => _renderBody = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final colors = context.colors;

    // Per-side score colors: winner green, loser red, draw/ongoing neutral.
    final Color ourScoreColor;
    final Color oppScoreColor;
    switch (match.result) {
      case TeamMatchResult.win:
        ourScoreColor = kGreenColor2;
        oppScoreColor = kRedColor;
      case TeamMatchResult.loss:
        ourScoreColor = kRedColor;
        oppScoreColor = kGreenColor2;
      case TeamMatchResult.draw:
        ourScoreColor = colors.textPrimary;
        oppScoreColor = colors.textPrimary;
      case TeamMatchResult.ongoing:
        ourScoreColor = colors.textTertiary;
        oppScoreColor = colors.textTertiary;
    }

    // RepaintBoundary so the height spring composites a cached layer of the
    // (heavy) game cards each frame instead of repainting them.
    final body =
        _renderBody
            ? RepaintBoundary(child: _RoundGames(match: match))
            : const SizedBox(width: double.infinity);

    final chevronSize = 20.ic;

    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12.br),
            child: InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(12.br),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 12.h),
                child: Row(
                  children: [
                    // Phantom spacer mirrors trailing chevron so the score pill
                    // stays optically centered (same trick as Games match card).
                    SizedBox(width: chevronSize),
                    Expanded(
                      child: Text(
                        widget.teamName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textSmMedium.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: 6.w),
                      padding: EdgeInsets.symmetric(
                        horizontal: 10.w,
                        vertical: 6.h,
                      ),
                      decoration: BoxDecoration(
                        color: colors.textPrimary.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8.br),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            match.ourPointsLabel,
                            style: AppTypography.textSmBold.copyWith(
                              color: ourScoreColor,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 5.w),
                            child: Text(
                              '–',
                              style: AppTypography.textSmMedium.copyWith(
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                          Text(
                            match.opponentPointsLabel,
                            style: AppTypography.textSmBold.copyWith(
                              color: oppScoreColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        match.opponentTeam,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: AppTypography.textSmMedium.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: chevronSize,
                      child: Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: chevronSize,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SingleMotionBuilder(
            motion: const CupertinoMotion.smooth(),
            value: _expanded ? 1.0 : 0.0,
            child: body,
            builder: (context, t, child) {
              final tc = t.clamp(0.0, 1.0);
              if (tc <= 0.001) return const SizedBox(width: double.infinity);
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: tc,
                  child: child,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RoundGames extends StatelessWidget {
  final TeamMatch match;

  const _RoundGames({required this.match});

  @override
  Widget build(BuildContext context) {
    final orderedGames = [for (final b in match.boardGames) b.game];
    final gamesData = GamesScreenModel(
      gamesTourModels: orderedGames,
      pinnedGamedIs: const [],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(0, 8.h, 0, 2.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < orderedGames.length; i++)
            RepaintBoundary(
              child: Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: GameCardWrapperWidget(
                  key: ValueKey('team_game_${orderedGames[i].gameId}'),
                  game: orderedGames[i],
                  gamesData: gamesData,
                  gameIndex: i,
                  isChessBoardVisible: false,
                  // Results refresh when the matches provider re-emits; avoid a
                  // live subscription per card across many rounds.
                  streamEnabled: false,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
