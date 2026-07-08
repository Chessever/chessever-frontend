import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_result_style.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// One collapsible round for a team: a header (round number, opponent, and the
/// board-point score coloured by the W/D/L result) that expands — with a motor
/// spring — to the round's individual games rendered as the regular
/// [GameCardWrapperWidget] cards (tap opens the board). Collapsed by default.
/// Shared by the expandable team standings row and the team score card.
class TeamRoundGroup extends StatefulWidget {
  final TeamMatch match;

  /// 0-based position in the sorted match list; displayed as round `index + 1`.
  final int index;

  const TeamRoundGroup({super.key, required this.match, required this.index});

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
    final resultColor = teamResultColor(context, match.result);

    // RepaintBoundary so the height spring composites a cached layer of the
    // (heavy) game cards each frame instead of repainting them.
    final body =
        _renderBody
            ? RepaintBoundary(child: _RoundGames(match: match))
            : const SizedBox(width: double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _toggle,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 10.h),
            child: Row(
              children: [
                Text(
                  'Round ${widget.index + 1}',
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
                // Board-point score, coloured by the match result.
                Text(
                  match.scoreLabel,
                  style: AppTypography.textSmBold.copyWith(color: resultColor),
                ),
                SizedBox(width: 6.w),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20.ic,
                  color: context.colors.textTertiary,
                ),
              ],
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
      padding: EdgeInsets.only(bottom: 6.h),
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
