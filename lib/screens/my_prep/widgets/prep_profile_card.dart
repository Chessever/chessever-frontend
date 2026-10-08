import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Favorites and Standings' actual player row, with honest source indicators.
class PrepProfileCard extends ConsumerWidget {
  const PrepProfileCard({
    super.key,
    required this.profile,
    required this.onTap,
    this.fideId,
    this.preview = false,
  });
  final PrepProfile profile;
  final VoidCallback onTap;
  final String? fideId;
  final bool preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncing = ref.watch(
      prepSyncProvider.select(
        (s) => profile.accounts.any((a) => s.containsKey(a.key)),
      ),
    );
    final error = profile.accounts
        .map((a) => a.error)
        .whereType<String>()
        .firstOrNull;
    final status = syncing
        ? 'Downloading games…'
        : error ??
              (profile.accounts.isEmpty
                  ? 'No sources attached'
                  : profile.lastSyncAtMs == null
                  ? 'Ready to download'
                  : prepGamesLabel(profile.gameCount));
    final primary = profile.databaseAccount ?? profile.accounts.firstOrNull;
    final fide = profile.fideId ?? fideId;
    return CardContextMenu(
      actions: (_) => preview ? [] : prepProfileMenu(context, ref, profile),
      onPreviewTap: onTap,
      child: FigmaPlayerCard(
        player: PlayerStandingModel(
          name: profile.name,
          countryCode: profile.country ?? '',
          title: profile.title,
          score: primary?.bestRating ?? 0,
          scoreChange: 0,
          matchScore: null,
          fideId: int.tryParse(fide ?? ''),
        ),
        rank: null,
        showRank: false,
        hideMissingRating: true,
        avatar: PrepAvatar(
          name: profile.name,
          size: 56.w,
          photoUrl: profile.avatarUrl,
          fideId: fide,
          title: profile.title,
        ),
        detailWidget: Row(
          children: [
            PrepSourceMarks(
              sources: profile.accounts.map((a) => a.source),
              size: 14.sp,
            ),
            if (profile.accounts.isNotEmpty) SizedBox(width: 8.w),
            Expanded(
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textXsRegular.copyWith(
                  color: error != null && !syncing
                      ? context.colors.danger
                      : context.colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        trailing: preview
            ? const SizedBox(width: 16)
            : CardMoreButton(size: 18.sp),
        onTap: onTap,
      ),
    );
  }
}
