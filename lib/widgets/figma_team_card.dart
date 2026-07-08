import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';

/// A team standings row that mirrors [FigmaPlayerCard]'s skeleton (rank →
/// avatar → name/sub-row → score) so the team table feels identical to the
/// individual standings, plus a chevron and an expandable list of player rows.
class FigmaTeamCard extends StatelessWidget {
  final TeamStandingModel team;
  final int rank;
  final bool isExpanded;
  final VoidCallback onToggle;

  /// The team's individual standings rows, built by the caller (typically
  /// [FigmaPlayerCard]s) and revealed when [isExpanded].
  final List<Widget> playerRows;

  const FigmaTeamCard({
    super.key,
    required this.team,
    required this.rank,
    required this.isExpanded,
    required this.onToggle,
    required this.playerRows,
  });

  /// Up to two leading letters from the first significant words of the team
  /// name (quotes/punctuation stripped), for the avatar slot.
  String _teamInitials(String name) {
    final words =
        name
            .replaceAll(RegExp("[\"'`.,()\\-]"), ' ')
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
    if (words.isEmpty) {
      return name.isNotEmpty
          ? name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase()
          : '';
    }
    if (words.length == 1) {
      final w = words.first;
      return w.substring(0, w.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onToggle,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF1F1F1F), width: 1),
              ),
            ),
            child: Row(
              children: [
                // Rank number
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
                // Team initials avatar
                PlayerInitialsAvatar(
                  initials: _teamInitials(team.teamName),
                  size: 56.w,
                  borderRadius: 8.br,
                ),
                SizedBox(width: 12.w),
                // Team name + collected score sub-row
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
                      Text(
                        '${team.gamePointsLabel} pts · ${team.recordLabel}',
                        style: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Match points (primary team score)
                Padding(
                  padding: EdgeInsets.only(left: 8.w),
                  child: Text(
                    team.matchPoints.toString(),
                    style: AppTypography.textMdMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(width: 4.w),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20.ic,
                  color: context.colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        // Expandable player rows
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child:
              isExpanded
                  ? Column(mainAxisSize: MainAxisSize.min, children: playerRows)
                  : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
