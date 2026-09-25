import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/team_crest_avatar.dart';
import 'package:flutter/material.dart';

const Color _drawGrey = Color(0xFF9AA0A6);

/// A team standings row that mirrors [FigmaPlayerCard]'s skeleton (rank →
/// avatar → name/sub-row → score) so the team table feels identical to the
/// individual standings. Tapping the card body opens the team score card;
/// only the trailing chevron toggles the expanded player rows.
class FigmaTeamCard extends StatelessWidget {
  final TeamStandingModel team;
  final int rank;
  final bool isExpanded;

  /// Toggles the expanded player rows — bound to the chevron only.
  final VoidCallback onToggle;

  /// Opens the team score card — bound to the rest of the row (rank, avatar,
  /// name, score).
  final VoidCallback onTeamTap;

  /// Content revealed when [isExpanded] — the team's round-by-round matchups.
  final List<Widget> expandedChildren;

  /// Wraps the collapsed header row only (rank, crest, name, score, chevron),
  /// never [expandedChildren]. Lets a host attach a gesture, such as the
  /// long-press menu, whose measured box is exactly the header, so the
  /// expanded rows keep their own gestures.
  final Widget Function(Widget header)? wrapHeader;

  const FigmaTeamCard({
    super.key,
    required this.team,
    required this.rank,
    required this.isExpanded,
    required this.onToggle,
    required this.onTeamTap,
    required this.expandedChildren,
    this.wrapHeader,
  });

  @override
  Widget build(BuildContext context) {
    final header = Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.colors.divider, width: 1),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      child: Row(
        children: [
          // Card body → team score card.
          Expanded(
            child: GestureDetector(
              onTap: onTeamTap,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  SizedBox(
                    width: 24.w,
                    child: Text(
                      rank.toString(),
                      style: AppTypography.textSmMedium.copyWith(
                        color: context.colors.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  TeamCrestAvatar(
                    teamName: team.teamName,
                    size: 56.w,
                    borderRadius: 8.br,
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          team.teamName,
                          style: AppTypography.textSmBold.copyWith(
                            color: context.colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4.h),
                        RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: AppTypography.textSmRegular.copyWith(
                              color: context.colors.textSecondary,
                            ),
                            children: [
                              TextSpan(text: '${team.gamePointsLabel} pts · '),
                              TextSpan(
                                text: '${team.matchesWon}',
                                style: AppTypography.textSmMedium.copyWith(
                                  color: context.colors.accentText,
                                ),
                              ),
                              const TextSpan(text: ' · '),
                              TextSpan(
                                text: '${team.matchesDrawn}',
                                style: AppTypography.textSmMedium.copyWith(
                                  // #9AA0A6 is 2.5:1 on paper.
                                  color:
                                      context.isLightTheme
                                          ? context.colors.textSecondary
                                          : _drawGrey,
                                ),
                              ),
                              const TextSpan(text: ' · '),
                              TextSpan(
                                text: '${team.matchesLost}',
                                style: AppTypography.textSmMedium.copyWith(
                                  color: context.colors.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 8.w),
                    child: Text(
                      team.matchPoints.toString(),
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Chevron → expand/collapse only.
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(left: 4.w),
              child: Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 24.ic,
                color: context.colors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        wrapHeader?.call(header) ?? header,
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child:
              isExpanded
                  ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: expandedChildren,
                  )
                  : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
