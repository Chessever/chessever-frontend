import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One prepared person: picture, name, their accounts, and how fresh the
/// downloaded games are. Long-press (or •••) opens its actions.
class PrepProfileCard extends ConsumerWidget {
  const PrepProfileCard({
    super.key,
    required this.profile,
    required this.onTap,
    this.fideId,
  });

  final PrepProfile profile;
  final VoidCallback onTap;
  final String? fideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
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
              (profile.lastSyncAtMs == null
                  ? 'Not downloaded yet'
                  : '${prepGamesLabel(profile.gameCount)} · '
                        '${prepSyncedAgo(profile.lastSyncAtMs).replaceFirst('Updated ', '')}');

    final card = TappableScale(
      scaleDown: 0.98,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(12.sp),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Row(
          children: [
            PrepAvatar(
              name: profile.name,
              size: 52.sp,
              photoUrl: profile.avatarUrl,
              fideId: fideId,
              title: profile.title,
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      PrepFlag(country: profile.country),
                      Flexible(
                        child: Text(
                          profile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.textMdBold.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4.h),
                  Row(
                    children: [
                      PrepSourceMarks(
                        sources: profile.accounts.map((a) => a.source),
                        size: 16.sp,
                      ),
                      SizedBox(width: 6.w),
                      Expanded(
                        child: Text(
                          profile.accounts.map((a) => a.username).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.textXsRegular.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4.h),
                  Row(
                    children: [
                      if (syncing) ...[
                        SizedBox.square(
                          dimension: 10.sp,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: colors.textSecondary,
                          ),
                        ),
                        SizedBox(width: 6.w),
                      ],
                      Expanded(
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.textXsRegular.copyWith(
                            color: error != null && !syncing
                                ? colors.danger
                                : colors.textTertiary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 4.w),
            CardMoreButton(size: 18.sp),
          ],
        ),
      ),
    );

    return CardContextMenu(
      actions: (menuContext) => prepProfileMenu(context, ref, profile),
      onPreviewTap: onTap,
      child: Semantics(
        button: true,
        label: '${profile.name}, $status',
        child: card,
      ),
    );
  }
}
