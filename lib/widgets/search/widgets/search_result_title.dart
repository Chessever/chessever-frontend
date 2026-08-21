import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:flutter/material.dart';

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.result,
    required this.onTap,
    this.isPlayerResult = false,
    this.isFullWidth = false,
  });

  final SearchResult result;
  final VoidCallback onTap;
  final bool isPlayerResult;

  /// Retained for source compatibility with the previous two-column layout.
  final bool isFullWidth;

  @override
  Widget build(BuildContext context) {
    final label =
        isPlayerResult
            ? 'Open player ${result.player?.name ?? result.matchedText}'
            : 'Open event ${result.tournament.title}';
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
              child:
                  isPlayerResult
                      ? _buildPlayerContent(context)
                      : _buildTournamentContent(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerContent(BuildContext context) {
    final player = result.player;
    final displayName =
        player?.title?.isNotEmpty == true
            ? '${player!.title} ${player.name}'
            : (player?.name ?? result.matchedText);
    final subtitle = [
      if (player?.rating != null && player!.rating! > 0) '${player.rating}',
      if (player?.fed?.isNotEmpty == true) player!.fed!,
    ].join(' · ');

    return Row(
      children: [
        Icon(
          Icons.person_outline,
          size: 19.ic,
          color: context.colors.textSecondary,
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                SizedBox(height: 2.h),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 11.sp,
                  ),
                ),
              ],
            ],
          ),
        ),
        Icon(
          Icons.chevron_right,
          size: 19.ic,
          color: context.colors.textSecondary,
        ),
      ],
    );
  }

  Widget _buildTournamentContent(BuildContext context) {
    final tournament = result.tournament;
    return Row(
      children: [
        Icon(
          Icons.emoji_events_outlined,
          size: 19.ic,
          color: context.colors.textSecondary,
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tournament.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (tournament.dates.isNotEmpty) ...[
                SizedBox(height: 2.h),
                Text(
                  tournament.dates,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 11.sp,
                  ),
                ),
              ],
            ],
          ),
        ),
        Icon(
          Icons.chevron_right,
          size: 19.ic,
          color: context.colors.textSecondary,
        ),
      ],
    );
  }
}
