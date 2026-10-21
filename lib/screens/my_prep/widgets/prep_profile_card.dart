import 'dart:math' as math;

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
import 'package:motor/motor.dart';

/// Players and Standings' actual player row, with honest source indicators.
class PrepProfileCard extends ConsumerWidget {
  const PrepProfileCard({
    super.key,
    required this.profile,
    required this.onTap,
    this.fideId,
    this.preview = false,
    this.status,
    this.pendingSources = const [],
    this.name,
    this.action,
    this.badge,
    this.expanded,
    this.onExpand,
  });
  final PrepProfile profile;
  final VoidCallback onTap;
  final String? fideId;
  final bool preview;

  /// Shown instead of the profile's own name, where a list names every row
  /// the same way.
  final String? name;

  /// Ends the row in place of the more button, where a list gives every
  /// player the same direct action. The menu then stays on a long press.
  final Widget? action;

  /// Replaces the sync line while the row is busy with something else.
  final String? status;

  /// Sources the next open attaches, marked beside the attached ones.
  final List<PrepSource> pendingSources;

  /// A mark ahead of whatever ends the row, such as the heart of a player
  /// the reader follows.
  final Widget? badge;

  /// Whether the list shows this profile's sources under the card. Null
  /// where the list has no such listing; the row then ends as it always did.
  /// A list that has one rules each profile off below its sources, so the
  /// card leaves its own rule out.
  final bool? expanded;

  /// Lists or folds the sources. A profile with nothing to list keeps the
  /// button's slot empty, so every row's text ends on the same x.
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncing = ref.watch(
      prepSyncProvider.select(
        (s) => profile.accounts.any((a) => s.containsKey(a.key)),
      ),
    );
    final error = profile.accounts
        .map((a) => a.downloadError)
        .whereType<String>()
        .firstOrNull;
    final status =
        this.status ??
        (syncing ? 'Downloading games…' : null) ??
        error ??
        (profile.accounts.isEmpty
            ? 'No sources attached'
            : profile.lastSyncAtMs == null
            ? 'Ready to download'
            : prepGamesLabel(profile.gameCount));
    final sources = [
      ...profile.accounts.map((a) => a.source),
      ...pendingSources,
    ];
    final primary = profile.databaseAccount ?? profile.accounts.firstOrNull;
    final fide = profile.fideId ?? fideId;
    final name = this.name ?? profile.name;
    // Whatever ends a row fills the more button's slot, so every row's
    // text ends on the same x.
    final end =
        action ??
        (preview ? const SizedBox(width: 44) : CardMoreButton(size: 18.sp));
    return CardContextMenu(
      actions: (_) => preview ? [] : prepProfileMenu(context, ref, profile),
      onPreviewTap: onTap,
      child: FigmaPlayerCard(
        player: PlayerStandingModel(
          name: name,
          countryCode: profile.country ?? '',
          title: profile.title,
          score: primary?.bestRating ?? 0,
          scoreChange: 0,
          matchScore: null,
          fideId: int.tryParse(fide ?? ''),
        ),
        rank: null,
        showRank: false,
        reserveRankSpace: false,
        hideMissingRating: true,
        showDivider: expanded == null,
        avatar: PrepAvatar(
          name: name,
          size: 56.w,
          photoUrl: profile.avatarUrl,
          fideId: fide,
          title: profile.title,
        ),
        // Three marks can be wider than a narrow row; they shrink before
        // they overflow.
        detailWidget: LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: PrepSourceMarks(sources: sources, size: 14.sp),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: sources.isEmpty ? 0 : 8.w),
                  child: Builder(
                    builder: (context) {
                      final style = AppTypography.textXsRegular.copyWith(
                        color: error != null && !syncing && this.status == null
                            ? context.colors.danger
                            : context.colors.textSecondary,
                      );
                      return syncing || this.status != null
                          ? PrepShimmerText(status, style: style)
                          : Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style,
                            );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        trailing: expanded == null && badge == null
            ? end
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ?badge,
                  if (expanded case final open?)
                    if (onExpand case final toggle?)
                      _FoldButton(open: open, onPressed: toggle)
                    else
                      const SizedBox(width: 44),
                  end,
                ],
              ),
        onTap: onTap,
      ),
    );
  }
}

/// The chevron that lists a profile's sources under its card and folds them
/// away again, on the more button's target and press.
class _FoldButton extends StatelessWidget {
  const _FoldButton({required this.open, required this.onPressed});

  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      value: open ? 1.0 : 0.0,
      motion: kPrepToggleMotion,
      active: !MediaQuery.disableAnimationsOf(context),
      builder: (context, t, child) =>
          Transform.rotate(angle: math.pi * t.clamp(0.0, 1.0), child: child),
      child: CardActionButton(
        icon: Icons.expand_more_rounded,
        tooltip: open ? 'Hide sources' : 'Show sources',
        size: 22.sp,
        onPressed: onPressed,
      ),
    );
  }
}
