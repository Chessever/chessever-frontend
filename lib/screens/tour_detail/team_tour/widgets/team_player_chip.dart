import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_player_nav.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Compact avatar + name chip for a team player. Tapping opens the player's
/// score card within the current event. Mirrors the compact player chips used
/// in the library / gamebase database.
class TeamPlayerChip extends ConsumerWidget {
  final PlayerStandingModel player;

  const TeamPlayerChip({super.key, required this.player});

  String _initials(String name) {
    final parts = name.split(',');
    if (parts.length > 1) {
      final a = parts[0].trim();
      final b = parts[1].trim();
      return '${a.isNotEmpty ? a[0] : ''}${b.isNotEmpty ? b[0] : ''}'
          .toUpperCase();
    }
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty
        ? name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase()
        : '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoAsync = ref.watch(playerPhotoProvider(player.fideId));
    final initials = _initials(player.name);
    final label =
        (player.title != null && player.title!.isNotEmpty)
            ? '${player.title} ${player.name}'
            : player.name;

    return GestureDetector(
      onTap: () => openPlayerScoreCard(context, ref, player),
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: BoxConstraints(maxWidth: 190.w),
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(20.br),
          border: Border.all(
            color: context.colors.textPrimary.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlayerInitialsAvatar(
              photoUrl: photoAsync.valueOrNull,
              initials: initials,
              size: 26.w,
              borderRadius: 13.br,
              title: player.title,
            ),
            SizedBox(width: 7.w),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textXsMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
