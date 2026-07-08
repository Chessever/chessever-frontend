import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_result_style.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One round for a team: a compact header (round number, opponent, board-point
/// score, colour-coded W/D/L) followed by the round's individual games rendered
/// with the regular [GameCardWrapperWidget] (the same player-vs-player card used
/// on the Games tab — tap opens the board). Shared by the expandable team
/// standings row and the team score card.
class TeamRoundGroup extends ConsumerWidget {
  final TeamMatch match;

  /// 0-based position in the sorted match list; displayed as round `index + 1`.
  final int index;

  const TeamRoundGroup({super.key, required this.match, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultColor = teamResultColor(context, match.result);
    final orderedGames = [for (final b in match.boardGames) b.game];
    final gamesData = GamesScreenModel(
      gamesTourModels: orderedGames,
      pinnedGamedIs: const [],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          child: Row(
            children: [
              Text(
                'Round ${index + 1}',
                style: AppTypography.textSmBold.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'vs ${match.opponentTeam}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                match.scoreLabel,
                style: AppTypography.textSmBold.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                teamResultLetter(match.result),
                style: AppTypography.textSmBold.copyWith(color: resultColor),
              ),
            ],
          ),
        ),
        for (var i = 0; i < orderedGames.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: GameCardWrapperWidget(
              key: ValueKey('team_game_${orderedGames[i].gameId}'),
              game: orderedGames[i],
              gamesData: gamesData,
              gameIndex: i,
              isChessBoardVisible: false,
              // Results refresh when the matches provider re-emits on a result
              // change; avoid 70 live subscriptions per expanded team.
              streamEnabled: false,
            ),
          ),
      ],
    );
  }
}
