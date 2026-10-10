import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/services/player_opening_tree.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/services/game_tree/game_tree_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

/// The opening tree built from this profile's games: what they play from
/// the first move, and the full explorer board scoped to them.
class PrepOpeningsTab extends StatefulWidget {
  const PrepOpeningsTab({
    super.key,
    required this.profile,
    required this.analysis,
    required this.games,
    required this.filter,
  });

  final PrepProfile profile;
  final PrepAnalysis analysis;
  final List<PrepGame> games;
  final PrepFilter filter;

  @override
  State<PrepOpeningsTab> createState() => _PrepOpeningsTabState();
}

class _PrepOpeningsTabState extends State<PrepOpeningsTab> {
  PrepSide _side = PrepSide.white;

  bool get _mine => widget.profile.kind == PrepKind.mine;

  String? get _color => switch (_side) {
    PrepSide.white => 'white',
    PrepSide.black => 'black',
    PrepSide.both => null,
  };

  TimeControl? get _timeControl =>
      switch (prepExplorerTimeControl(widget.filter.speed)) {
        'blitz' => TimeControl.blitz,
        'rapid' => TimeControl.rapid,
        'classical' => TimeControl.classical,
        _ => null,
      };

  void _explore({List<String> moves = const []}) {
    HapticFeedbackService.cardTap();
    String? fen;
    if (moves.isNotEmpty) {
      Position position = Chess.initial;
      for (final uci in moves) {
        final move = Move.parse(uci);
        if (move == null || !position.isLegal(move)) break;
        position = position.play(move);
      }
      fen = position.fen;
    }
    openGameTreeExplorer(
      context,
      scopeId: widget.profile.id,
      title: widget.profile.name,
      country: widget.profile.country,
      playerTitle: widget.profile.title,
      timeControl: _timeControl,
      color: switch (_side) {
        PrepSide.white => GamebasePlayerColor.white,
        PrepSide.black => GamebasePlayerColor.black,
        PrepSide.both => null,
      },
      initialFen: fen,
      initialMoves: moves.isEmpty ? null : moves,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gutter = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);
    final criteria = PlayerOpeningTreeFilterCriteria(
      color: _color,
      timeControl: _timeControl,
    );
    final first = widget.analysis.tree.movesForFen(
      kInitialFEN,
      filters: criteria,
    );
    final total = first.fold<int>(0, (sum, m) => sum + m.total);
    final who = _mine ? 'you' : 'they';

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 4.h, gutter, 40.h),
      children: [
        PrepSidePicker(
          side: _side,
          mine: _mine,
          onChanged: (s) => setState(() => _side = s),
        ),
        SizedBox(height: 12.h),
        TappableScale(
          scaleDown: 0.98,
          onTap: _explore,
          child: Container(
            padding: EdgeInsets.all(16.sp),
            decoration: BoxDecoration(
              color: colors.textPrimary,
              borderRadius: BorderRadius.circular(12.br),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.account_tree_rounded,
                  color: colors.textInverse,
                  size: 22.sp,
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Open the opening explorer',
                        style: AppTypography.textSmBold.copyWith(
                          color: colors.textInverse,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        'Step through every line $who played, with the games '
                        'behind each move.',
                        style: AppTypography.textXsRegular.copyWith(
                          color: colors.textInverse.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: colors.textInverse,
                  size: 18.sp,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 20.h),
        Text(
          _side == PrepSide.black
              ? (_mine ? 'Your answers to White' : 'Their answers to White')
              : (_mine ? 'Your first moves' : 'Their first moves'),
          style: AppTypography.textMdBold.copyWith(color: colors.textPrimary),
        ),
        SizedBox(height: 4.h),
        Text(
          _side == PrepSide.black
              ? 'White’s first move in their Black games. Tap one to see '
                    'how they answer it.'
              : 'Tap a move to open the explorer on it.',
          style: AppTypography.textXsRegular.copyWith(
            color: colors.textSecondary,
          ),
        ),
        SizedBox(height: 12.h),
        if (first.isEmpty)
          Text(
            'No games in this selection.',
            style: AppTypography.textSmRegular.copyWith(
              color: colors.textSecondary,
            ),
          )
        else
          for (final move in first.take(10))
            _MoveRow(
              move: move,
              share: total == 0 ? 0 : move.total / total,
              mine: _side != PrepSide.black,
              onTap: () => _explore(moves: [move.uci]),
            ),
      ],
    );
  }
}

class _MoveRow extends StatelessWidget {
  const _MoveRow({
    required this.move,
    required this.share,
    required this.mine,
    required this.onTap,
  });

  final MoveAggregate move;
  final double share;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    String san;
    try {
      san = Chess.initial.makeSan(Move.parse(move.uci)!).$2;
    } catch (_) {
      san = move.uci;
    }
    final tally = PrepTally(
      wins: move.white,
      draws: move.draws,
      losses: move.black,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: TappableScale(
        scaleDown: 0.98,
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 56.w,
                child: Text(
                  '1. $san',
                  style: AppTypography.textMdBold.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${(share * 100).round()}%',
                          style: AppTypography.textSmBold.copyWith(
                            color: colors.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        SizedBox(width: 6.w),
                        Text(
                          prepGamesLabel(move.total),
                          style: AppTypography.textXsRegular.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6.h),
                    // White's results, as the explorer colours them.
                    PrepResultBar(tally: tally, height: 4),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              Icon(
                Icons.chevron_right_rounded,
                size: 20.sp,
                color: colors.iconSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
