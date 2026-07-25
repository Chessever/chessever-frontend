import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';

import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:heroine/heroine.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart' as skel;

/// A player card widget matching the Figma design.
///
/// Two modes:
/// - [showFavoriteButton] = true: Shows heart icon on the right (for players/favorites lists)
/// - [showFavoriteButton] = false: Shows score on the right (for standings)
class FigmaPlayerCard extends ConsumerWidget {
  final PlayerStandingModel player;

  /// Nullable so search results can render immediately while the overall
  /// standing rank is still being resolved asynchronously. A shimmer
  /// placeholder is shown in the rank slot until the number arrives.
  final int? rank;
  final bool isFavorite;
  final bool showFavoriteButton;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;
  final ValueChanged<LongPressStartDetails>? onLongPress;

  /// When set, the avatar is wrapped in a [Heroine] so the photo can fly
  /// into a detail screen that uses the same tag (e.g. miniature scorecard).
  final String? avatarHeroTag;

  /// The score on the right comes from a second source in some lists (the
  /// miniatures leaderboard resolves W-L per row from gamebase). Set this while
  /// that lookup is still out and the slot shimmers instead of sitting empty.
  final bool matchScorePending;

  /// Holds the score slot at one width for every row of the list. Lists whose
  /// records vary in length (`5W-2L` next to `172W-41L`) need it so the name
  /// column ends on the same x in every row, and so a record arriving after
  /// first paint does not shove that row's name sideways.
  final bool reserveMatchScoreSlot;

  const FigmaPlayerCard({
    super.key,
    required this.player,
    required this.rank,
    this.isFavorite = false,
    this.showFavoriteButton = true,
    required this.onTap,
    this.onToggleFavorite,
    this.onLongPress,
    this.avatarHeroTag,
    this.matchScorePending = false,
    this.reserveMatchScoreSlot = false,
  });

  /// The longest record the leaderboard produces. Both the reserved width and
  /// the pending placeholder are measured from this one string, so they cannot
  /// drift apart.
  static const _widestMatchScore = '000W-000L';

  /// Right-hand score, held at a fixed width when the list asks for it. Measured
  /// rather than hardcoded so a large text scale widens the slot instead of
  /// clipping the number.
  Widget _buildMatchScore(BuildContext context) {
    final style = AppTypography.textMdMedium.copyWith(
      color: context.colors.textPrimary,
    );
    final pending = matchScorePending && (player.matchScore ?? '').isEmpty;
    final reserved =
        reserveMatchScoreSlot ? _measureMatchScoreSlot(context, style) : null;

    if (pending) {
      final bone = skel.Skeletonizer(
        enabled: true,
        effect: const skel.ShimmerEffect(
          baseColor: Color(0xFF2A2A2A),
          highlightColor: Color(0xFF3A3A3A),
        ),
        child: Text(_widestMatchScore, style: style),
      );
      // Held to exactly the reserved width: a bone is a placeholder, so it may
      // be pinned, and pinning it is what keeps the name column still when the
      // real record replaces it.
      return reserved == null ? bone : SizedBox(width: reserved, child: bone);
    }

    final score = _MatchScoreText(score: player.matchScore ?? '');
    if (reserved == null) return score;

    // A minimum, not a fixed width: a record longer than the reserved string
    // widens its own row instead of being clipped by the slot.
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: reserved),
      child: Align(alignment: Alignment.centerRight, child: score),
    );
  }

  double _measureMatchScoreSlot(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: _widestMatchScore, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  String _getInitials(String name) {
    final parts = name.split(',');
    if (parts.length > 1) {
      final first = parts[0].trim();
      final second = parts[1].trim();
      return '${first.isNotEmpty ? first[0] : ''}${second.isNotEmpty ? second[0] : ''}'
          .toUpperCase();
    }
    final words = name.trim().split(' ');
    if (words.length >= 2) {
      return '${words[0].isNotEmpty ? words[0][0] : ''}${words[1].isNotEmpty ? words[1][0] : ''}'
          .toUpperCase();
    }
    return name.isNotEmpty
        ? name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase()
        : '';
  }

  Widget _buildAvatar({
    required BuildContext context,
    required AsyncValue<String?> photoAsync,
    required String initials,
    required double avatarSize,
  }) {
    final tag = avatarHeroTag;
    final useHero = tag != null && tag.isNotEmpty;

    // Initials paint on the very first frame; the resolved photo (if any) swaps
    // in the instant its URL arrives. We never show a shimmer/blank box while
    // the FIDE photo URL is being fetched — the letters are the base layer.
    //
    // `valueOrNull` collapses loading + error + confirmed-absent all to null,
    // which PlayerInitialsAvatar renders as pure initials with zero network.
    // When the URL resolves, PlayerInitialsAvatar's own CachedNetworkImage
    // keeps the same initials as its placeholder *and* error fallback, so the
    // face is continuous: initials → photo, never initials → box → photo.
    final avatar = PlayerInitialsAvatar(
      photoUrl: photoAsync.valueOrNull,
      initials: initials,
      size: avatarSize,
      borderRadius: 8.br,
      title: player.title,
    );

    if (!useHero) return avatar;

    return Heroine(
      tag: tag,
      motion: const CupertinoMotion.smooth(),
      flightShuttleBuilder: const FadeShuttleBuilder(),
      child: avatar,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoAsync = ref.watch(playerPhotoProvider(player.fideId));
    final avatarSize = 56.w;
    final initials = _getInitials(player.name);
    final federationForFlag = player.countryCode.trim();
    final showFlag = FederationFlag.hasVisibleFlag(federationForFlag);

    return GestureDetector(
      onTap: onTap,
      onLongPressStart: onLongPress,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFF1F1F1F), width: 1),
          ),
        ),
        child: Row(
          children: [
            // Rank number — shows a shimmer placeholder while the overall
            // standing rank is still resolving for remote search results.
            SizedBox(
              width: 24.w,
              child:
                  rank != null
                      ? Text(
                        rank.toString(),
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textTertiary,
                        ),
                        textAlign: TextAlign.center,
                      )
                      : skel.Skeletonizer(
                        enabled: true,
                        effect: const skel.ShimmerEffect(
                          baseColor: Color(0xFF2A2A2A),
                          highlightColor: Color(0xFF3A3A3A),
                        ),
                        child: Text(
                          '00',
                          style: AppTypography.textSmMedium.copyWith(
                            color: context.colors.textTertiary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
            ),
            SizedBox(width: 12.w),
            // Player photo with title badge overlay
            _buildAvatar(
              context: context,
              photoAsync: photoAsync,
              initials: initials,
              avatarSize: avatarSize,
            ),
            SizedBox(width: 12.w),
            // Player info (name + flag/rating)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Player name
                  Text(
                    player.name,
                    style: AppTypography.textSmBold.copyWith(
                      color: context.colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
                  // Flag + Rating (+ optional change)
                  Row(
                    children: [
                      // Country flag
                      if (showFlag)
                        Padding(
                          padding: EdgeInsets.only(right: 6.w),
                          child: SizedBox(
                            width: 18.w,
                            height: 12.h,
                            child: FederationFlag(
                              federation: federationForFlag,
                              height: 12.h,
                              width: 18.w,
                              borderRadius: BorderRadius.circular(2.br),
                            ),
                          ),
                        ),
                      // Rating
                      Text(
                        player.score.toString(),
                        style: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                      // Rating change (if any)
                      if (player.scoreChange != 0)
                        Text(
                          player.scoreChange > 0
                              ? '+${player.scoreChange}'
                              : '${player.scoreChange}',
                          style: AppTypography.textSmMedium.copyWith(
                            color:
                                player.scoreChange > 0
                                    ? kGreenColor
                                    : kRedColor,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Right side: either heart or score
            if (showFavoriteButton && onToggleFavorite != null)
              GestureDetector(
                onTap: onToggleFavorite,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: EdgeInsets.all(8.sp),
                  child: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color:
                        isFavorite
                            ? const Color(0xFFEF4444)
                            : context.colors.textTertiary,
                    size: 24.ic,
                  ),
                ),
              )
            else if (!showFavoriteButton)
              Padding(
                padding: EdgeInsets.only(left: 8.w),
                child: _buildMatchScore(context),
              ),
          ],
        ),
      ),
    );
  }
}

/// Standings use plain tournament scores (`5.0/9`); miniatures leaderboard
/// rows use `12W-4L`. Color W with brand primary and L with danger red so the
/// record reads like result chips elsewhere (board player rows, team W/D/L).
class _MatchScoreText extends StatelessWidget {
  const _MatchScoreText({required this.score});

  final String score;

  static final _winLoss = RegExp(r'^(\d+)W-(\d+)L$');

  @override
  Widget build(BuildContext context) {
    final base = AppTypography.textMdMedium;
    final match = _winLoss.firstMatch(score.trim());
    if (match == null) {
      return Text(
        score,
        style: base.copyWith(color: context.colors.textPrimary),
      );
    }

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(
            text: '${match.group(1)}W',
            style: base.copyWith(color: kPrimaryColor),
          ),
          TextSpan(
            text: '-',
            style: base.copyWith(color: context.colors.textSecondary),
          ),
          TextSpan(
            text: '${match.group(2)}L',
            style: base.copyWith(color: context.colors.danger),
          ),
        ],
      ),
    );
  }
}

/// Header row for standings lists matching the Figma design.
class FigmaStandingsHeader extends StatelessWidget {
  final bool showScore;

  const FigmaStandingsHeader({super.key, this.showScore = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      child: Row(
        children: [
          // # column
          SizedBox(
            width: 24.w,
            child: Text(
              '#',
              style: AppTypography.textXsMedium.copyWith(
                color: context.colors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(width: 12.w),
          // Player column
          Expanded(
            child: Text(
              'Player',
              style: AppTypography.textXsMedium.copyWith(
                color: context.colors.textTertiary,
              ),
            ),
          ),
          // Score column
          if (showScore)
            Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: Text(
                'Score',
                style: AppTypography.textXsMedium.copyWith(
                  color: context.colors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
