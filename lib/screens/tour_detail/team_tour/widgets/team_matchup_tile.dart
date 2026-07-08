import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/screens/standings/widget/scoreboard_card_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_result_style.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One round's matchup for a team, reusing [ScoreboardCardWidget] (the same
/// component as the individual score card): round number, opponent team name,
/// the board-point split (e.g. "5 – 3½") and a W/D/L-coloured result circle
/// showing the team's earned points. Below it, one coloured circle per board —
/// tapping a circle opens that game in the chessboard.
///
/// Shared by the team score card and the expandable team standings row.
class TeamMatchupTile extends ConsumerWidget {
  final TeamMatch match;
  final int index;

  const TeamMatchupTile({super.key, required this.match, required this.index});

  void _openBoard(BuildContext context, WidgetRef ref, int boardIndex) {
    ref.read(gameCardWrapperProvider).navigateToChessBoard(
      context: context,
      orderedGames: [for (final b in match.boardGames) b.game],
      gameIndex: boardIndex,
      onReturnFromChessboard: (_) {},
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultColor = teamResultColor(context, match.result);

    final footer =
        match.boardGames.isEmpty
            ? null
            : Padding(
              padding: EdgeInsets.only(top: 10.h),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6.w,
                  runSpacing: 6.w,
                  children: [
                    for (var i = 0; i < match.boardGames.length; i++)
                      _BoardCircle(
                        board: match.boardGames[i],
                        onTap: () => _openBoard(context, ref, i),
                      ),
                  ],
                ),
              ),
            );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12.br),
      child: ScoreboardCardWidget(
        index: index,
        leadingLabel: match.roundLabel,
        countryCode: '',
        name: match.opponentTeam,
        score: 0,
        showRating: false,
        trailingLabel: match.scoreLabel,
        matchScore: match.ourPointsLabel,
        resultColor: resultColor,
        isFirst: true,
        isLast: true,
        onTap: () {},
        footer: footer,
      ),
    );
  }
}

class _BoardCircle extends StatelessWidget {
  final TeamBoardGame board;
  final VoidCallback onTap;

  const _BoardCircle({required this.board, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = teamResultColor(context, board.result);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28.w,
        height: 28.w,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1),
        ),
        child: Text(
          teamBoardGlyph(board.result),
          style: AppTypography.textXsMedium.copyWith(color: color),
        ),
      ),
    );
  }
}
