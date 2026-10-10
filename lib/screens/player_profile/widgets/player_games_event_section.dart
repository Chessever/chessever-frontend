import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/utils/twic_event_navigation.dart';
import 'package:chessever2/screens/player_profile/widgets/player_profile_resolved_event_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/time_utils.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The chevron that folds a section of a player's games away.
class PlayerGamesCollapseToggle extends StatelessWidget {
  const PlayerGamesCollapseToggle({
    super.key,
    required this.isCollapsed,
    required this.onTap,
    this.label = 'event games',
  });

  final bool isCollapsed;
  final VoidCallback onTap;

  /// What the section holds, for the screen reader (`Collapse event games`).
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isCollapsed ? 'Expand $label' : 'Collapse $label',
      child: InkWell(
        // Generous, square hit target so taps near the chevron toggle the
        // event instead of falling through to the card's open-event tap.
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44.w,
          height: 44.h,
          child: Center(
            child: Icon(
              isCollapsed
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              size: 20.sp,
              color: context.colors.textPrimary.withValues(alpha: 0.65),
            ),
          ),
        ),
      ),
    );
  }
}

/// How many games a section holds and what the player scored in them.
class PlayerGamesSectionStats extends StatelessWidget {
  const PlayerGamesSectionStats({
    super.key,
    required this.gameCount,
    required this.playerScore,
  });

  final int gameCount;
  final double playerScore;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              Icons.sports_esports_outlined,
              size: 14.sp,
              color: context.textInk(0.5),
            ),
            SizedBox(width: 4.w),
            Text(
              '$gameCount ${gameCount == 1 ? 'game' : 'games'}',
              style: AppTypography.textXsRegular.copyWith(
                color: context.textInk(0.5),
              ),
            ),
          ],
        ),
        if (gameCount > 0)
          PlayerGamesScorePill(gameCount: gameCount, playerScore: playerScore),
      ],
    );
  }
}

/// The player's points out of the games played, tinted by how they went.
class PlayerGamesScorePill extends StatelessWidget {
  const PlayerGamesScorePill({
    super.key,
    required this.gameCount,
    required this.playerScore,
  });

  final int gameCount;
  final double playerScore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: _getScoreColor(context).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4.br),
      ),
      child: Text(
        '${_formatScore(playerScore)}/$gameCount',
        style: AppTypography.textXsBold.copyWith(
          color: _getScoreColor(context),
        ),
      ),
    );
  }

  String _formatScore(double score) {
    if (score == score.truncateToDouble()) {
      return score.toInt().toString();
    }
    return score.toStringAsFixed(1);
  }

  Color _getScoreColor(BuildContext context) {
    if (gameCount == 0) return context.colors.textPrimary;
    final percentage = playerScore / gameCount;
    if (percentage >= 0.6) return context.colors.successStrong;
    if (percentage >= 0.4) return context.colors.textPrimary;
    return context.colors.danger;
  }
}

/// Event section header: EventCard (or fallback) + player stats row
class PlayerGamesEventSection extends ConsumerWidget {
  const PlayerGamesEventSection({
    super.key,
    this.eventData,
    required this.dataSource,
    required this.tourId,
    this.tourSlug,
    this.site,
    required this.gameCount,
    required this.playerScore,
    required this.isCollapsed,
    required this.onToggleCollapsed,
  });

  final PlayerEventData? eventData;
  final PlayerProfileDataSource dataSource;
  final String tourId;
  final String? tourSlug;
  final String? site;
  final int gameCount;
  final double playerScore;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = PlayerProfileEventCardRequest(
      dataSource: dataSource,
      tourId: tourId,
      tourName: eventData?.tourName ?? tourSlug ?? tourId,
      tourSlug: eventData?.tourSlug ?? tourSlug,
      broadcastSlug: eventData?.broadcastSlug,
      site: eventData?.site ?? site,
    );
    final fallbackCard = _buildSyncCommunityCard();

    return PlayerProfileResolvedEventCard(
      request: request,
      fallbackCard: fallbackCard,
      gamebaseKey: eventData?.canonicalKey ?? tourSlug ?? tourId,
      heroTagSuffix: '_player_games_$tourId',
      crossAxisAlignment: CrossAxisAlignment.stretch,
      onTap: (displayCard) => _navigateToEvent(context, ref, displayCard),
      trailingWidget: PlayerGamesCollapseToggle(
        isCollapsed: isCollapsed,
        onTap: onToggleCollapsed,
      ),
      statsRow: _buildStatsRow(context),
    );
  }

  Future<void> _navigateToEvent(
    BuildContext context,
    WidgetRef ref,
    GroupEventCardModel displayCard,
  ) {
    return openProfileEvent(
      context: context,
      ref: ref,
      dataSource: dataSource,
      tourId: tourId,
      eventName: eventData?.tourName ?? tourSlug ?? tourId,
      site: eventData?.site ?? site,
      broadcastSlug: eventData?.broadcastSlug,
      gamebaseKey: eventData?.canonicalKey ?? tourSlug ?? tourId,
      canonicalBroadcastId:
          displayCard.eventSource == EventSource.lichessBroadcast
              ? displayCard.id
              : null,
    );
  }

  /// Build a community event card synchronously from the data the header
  /// already has (event name, dates, location). Used so the card renders fully
  /// on first frame instead of flashing a short fallback while an async card
  /// provider resolves.
  GroupEventCardModel _buildSyncCommunityCard() {
    final title = (eventData?.tourName ?? tourSlug ?? tourId).trim();
    final id = 'twic_event_$tourId';
    final start = eventData?.startDate;
    final end = eventData?.endDate;
    // The card draws a clock only as its coin. Naming one it has no coin
    // for, or none, leaves that slot empty rather than printing a word.
    final clock = eventData?.dominantTimeControl;
    return GroupEventCardModel(
      id: id,
      title: title.isEmpty ? 'Event' : title,
      dates: TimeUtils.formatDateRange(start, end),
      maxAvgElo: eventData?.avgElo ?? eventData?.maxElo ?? 0,
      timeUntilStart: TimeUtils.timeUntilStart(start),
      tourEventCategory: GroupEventCardModel.getCategory(
        groupId: id,
        groupName: title,
        startDate: start,
        endDate: end,
        liveGroupIds: const [],
      ),
      timeControl:
          clock != null && TimeControlGlyph.assetForLabel(clock) != null
              ? clock
              : '',
      endDate: end,
      startDate: start,
      location: site ?? eventData?.site,
      searchTerms: [title],
      eventSource: EventSource.communityEvent,
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: 1.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(8.br),
          bottomRight: Radius.circular(8.br),
        ),
      ),
      child: PlayerGamesSectionStats(
        gameCount: gameCount,
        playerScore: playerScore,
      ),
    );
  }
}
