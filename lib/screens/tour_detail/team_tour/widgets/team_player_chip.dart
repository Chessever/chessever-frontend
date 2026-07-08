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
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(10.br),
          border: Border.all(
            color: context.colors.textPrimary.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            // Circular; no title badge — the title already prefixes the name,
            // and a badge on a 26px avatar is cramped. isCircular makes the clip
            // exactly size/2 so it's a clean circle regardless of .w/.br scaling.
            PlayerInitialsAvatar(
              photoUrl: photoAsync.valueOrNull,
              initials: initials,
              size: 26.w,
              isCircular: true,
            ),
            SizedBox(width: 7.w),
            Expanded(
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

/// Lays team player chips out as a responsive grid: equal-width columns that
/// fill each row as much as possible and wrap to the next line on overflow.
class TeamPlayerChipsGrid extends StatelessWidget {
  final List<PlayerStandingModel> players;

  const TeamPlayerChipsGrid({super.key, required this.players});

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) return const SizedBox.shrink();
    final spacing = 6.w;
    final minChipWidth = 150.w;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        // As many columns as fit (min chip width), 1–4.
        final columns = (maxWidth / (minChipWidth + spacing))
            .floor()
            .clamp(1, 4);
        final chipWidth =
            (maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: 6.h,
          children: [
            for (final player in players)
              SizedBox(
                width: chipWidth,
                child: TeamPlayerChip(player: player),
              ),
          ],
        );
      },
    );
  }
}
