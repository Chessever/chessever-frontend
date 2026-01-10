import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Events tab showing tournaments the player has participated in
class PlayerEventsTab extends ConsumerStatefulWidget {
  const PlayerEventsTab({
    super.key,
    this.fideId,
    required this.playerName,
  });

  final int? fideId;
  final String playerName;

  @override
  ConsumerState<PlayerEventsTab> createState() => _PlayerEventsTabState();
}

class _PlayerEventsTabState extends ConsumerState<PlayerEventsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// Get the player profile key for provider lookups
  PlayerProfileKey get _playerKey => PlayerProfileKey(
        fideId: widget.fideId,
        playerName: widget.playerName,
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final eventsAsync = ref.watch(playerEventsKeyProvider(_playerKey));

    Widget content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        ref.invalidate(playerEventsKeyProvider(_playerKey));
        if (widget.fideId != null) {
          ref.invalidate(playerEventCardsProvider(widget.fideId!));
        }
      },
      color: kWhiteColor,
      backgroundColor: kBlack2Color,
      child: eventsAsync.when(
        data: (events) {
          if (events.isEmpty) {
            return _buildEmptyState();
          }

          // Sort events by start date (most recent first)
          final sortedEvents = List<PlayerEventData>.from(events)
            ..sort((a, b) {
              final aDate = a.startDate ?? DateTime(1900);
              final bDate = b.startDate ?? DateTime(1900);
              return bDate.compareTo(aDate);
            });

          return _EventsListContent(
            events: sortedEvents,
            fideId: widget.fideId,
          );
        },
        loading: () => _buildLoadingState(),
        error: (error, _) => _buildErrorState(error.toString()),
      ),
    );

    // Apply tablet max-width constraint
    if (ResponsiveHelper.isTablet) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: content,
        ),
      );
    }

    return content;
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80.w,
                height: 80.h,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      kWhiteColor.withValues(alpha: 0.15),
                      kWhiteColor.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20.br),
                ),
                child: Icon(
                  Icons.emoji_events_outlined,
                  color: kWhiteColor.withValues(alpha: 0.7),
                  size: 40.ic,
                ),
              ),
              SizedBox(height: 20.h),
              Text(
                'No tournaments found',
                style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
              ),
              SizedBox(height: 8.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 40.w),
                child: Text(
                  'This player has no recorded tournament participations.',
                  style: AppTypography.textSmRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48.w,
            height: 48.h,
            child: const CircularProgressIndicator(
              color: kWhiteColor,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Loading tournaments...',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildErrorState(String error) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64.w,
                height: 64.h,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16.br),
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  color: Colors.redAccent,
                  size: 32.ic,
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'Failed to load tournaments',
                style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
              ),
              SizedBox(height: 8.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32.w),
                child: Text(
                  error,
                  style: AppTypography.textSmRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: 24.h),
              GestureDetector(
                onTap: () {
                  HapticFeedbackService.buttonPress();
                  ref.invalidate(playerEventsKeyProvider(_playerKey));
                },
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    color: kWhiteColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8.br),
                  ),
                  child: Text(
                    'Retry',
                    style:
                        AppTypography.textSmMedium.copyWith(color: kWhiteColor),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

/// Content widget that shows statistics and event list
class _EventsListContent extends ConsumerWidget {
  const _EventsListContent({
    required this.events,
    this.fideId,
  });

  final List<PlayerEventData> events;
  final int? fideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Calculate statistics from events
    final totalGames = events.fold<int>(0, (sum, e) => sum + e.gamesPlayed);
    final totalScore = events.fold<double>(0, (sum, e) => sum + (e.score ?? 0));
    final avgScore = totalGames > 0 ? totalScore / totalGames : 0.0;

    // Watch the event cards provider (only if fideId is available)
    final eventCardsAsync = fideId != null
        ? ref.watch(playerEventCardsProvider(fideId!))
        : const AsyncValue<Map<String, GroupEventCardModel>>.data({});

    final horizontalPadding = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16.h),
      itemCount: events.length + 1, // +1 for header section
      itemBuilder: (context, index) {
        if (index == 0) {
          return _StatsHeader(
            totalEvents: events.length,
            totalGames: totalGames,
            avgScore: avgScore,
          );
        }

        final event = events[index - 1];

        return eventCardsAsync.when(
          data: (eventCards) {
            final eventCard = eventCards[event.tourId];
            if (eventCard != null) {
              return Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: _PlayerEventCard(
                  eventCard: eventCard,
                  playerEventData: event,
                  index: index - 1,
                ),
              );
            }
            // Fallback to custom card if GroupEventCardModel not available
            return Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: _FallbackEventCard(
                event: event,
                index: index - 1,
                onTap: () => _navigateToTournament(context, ref, event),
              ),
            );
          },
          loading: () => Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: _FallbackEventCard(
              event: event,
              index: index - 1,
              onTap: () => _navigateToTournament(context, ref, event),
            ),
          ),
          error: (_, __) => Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: _FallbackEventCard(
              event: event,
              index: index - 1,
              onTap: () => _navigateToTournament(context, ref, event),
            ),
          ),
        );
      },
    );
  }

  Future<void> _navigateToTournament(
    BuildContext context,
    WidgetRef ref,
    PlayerEventData event,
  ) async {
    HapticFeedbackService.buttonPress();
    try {
      final broadcast = await ref
          .read(groupBroadcastRepositoryProvider)
          .getGroupBroadcastById(event.tourId);
      ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;

      if (!context.mounted) return;
      if (ref.read(selectedBroadcastModelProvider) != null) {
        Navigator.pushNamed(context, '/tournament_detail_screen');
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open event')),
      );
    }
  }
}

/// Statistics header section - similar design to about tab
class _StatsHeader extends StatelessWidget {
  const _StatsHeader({
    required this.totalEvents,
    required this.totalGames,
    required this.avgScore,
  });

  final int totalEvents;
  final int totalGames;
  final double avgScore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tournament Statistics',
          style: AppTypography.textSmBold.copyWith(color: kWhiteColor),
        ),
        SizedBox(height: 12.h),
        Container(
          padding: EdgeInsets.all(16.sp),
          decoration: BoxDecoration(
            color: kBlack2Color,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Row(
            children: [
              _StatBox(
                value: totalEvents.toString(),
                label: 'Events',
                color: kPrimaryColor,
              ),
              SizedBox(width: 12.w),
              _StatBox(
                value: totalGames.toString(),
                label: 'Games',
                color: kWhiteColor70,
              ),
              SizedBox(width: 12.w),
              _StatBox(
                value: '${(avgScore * 100).toStringAsFixed(1)}%',
                label: 'Avg Score',
                color: _getScoreColor(avgScore),
              ),
            ],
          ),
        ),
        SizedBox(height: 24.h),
        Text(
          'Participated Events',
          style: AppTypography.textSmBold.copyWith(color: kWhiteColor),
        ),
        SizedBox(height: 12.h),
      ],
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.02, end: 0);
  }

  Color _getScoreColor(double score) {
    if (score >= 0.6) return kGreenColor;
    if (score >= 0.4) return kWhiteColor;
    return Colors.redAccent;
  }
}

/// Stat box widget
class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8.br),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: AppTypography.textMdBold.copyWith(color: color),
            ),
            SizedBox(height: 2.h),
            Text(
              label,
              style: AppTypography.textXsRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Player event card using standard EventCard with player stats overlay
class _PlayerEventCard extends ConsumerWidget {
  const _PlayerEventCard({
    required this.eventCard,
    required this.playerEventData,
    required this.index,
  });

  final GroupEventCardModel eventCard;
  final PlayerEventData playerEventData;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _navigateToTournament(context, ref),
      child: Column(
        children: [
          // Standard event card
          EventCard(
            tourEventCardModel: eventCard,
            heroTagSuffix: 'player-profile-$index',
          ),
          // Player stats row
          Container(
            margin: EdgeInsets.only(top: 1.h),
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: kBlack2Color,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(8.br),
                bottomRight: Radius.circular(8.br),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.sports_esports_outlined,
                      size: 14.sp,
                      color: kWhiteColor.withValues(alpha: 0.5),
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      '${playerEventData.gamesPlayed} ${playerEventData.gamesPlayed == 1 ? 'game' : 'games'}',
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                if (playerEventData.score != null)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8.w,
                      vertical: 3.h,
                    ),
                    decoration: BoxDecoration(
                      color: _getScoreColor(
                        playerEventData.score!,
                        playerEventData.gamesPlayed,
                      ).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4.br),
                    ),
                    child: Text(
                      '${playerEventData.score!.toStringAsFixed(1)}/${playerEventData.gamesPlayed}',
                      style: AppTypography.textXsBold.copyWith(
                        color: _getScoreColor(
                          playerEventData.score!,
                          playerEventData.gamesPlayed,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(
          duration: 200.ms,
          delay: Duration(milliseconds: (index % 10) * 50),
        )
        .slideY(begin: 0.02, end: 0);
  }

  Future<void> _navigateToTournament(BuildContext context, WidgetRef ref) async {
    HapticFeedbackService.buttonPress();
    try {
      final broadcast = await ref
          .read(groupBroadcastRepositoryProvider)
          .getGroupBroadcastById(playerEventData.tourId);
      ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;

      if (!context.mounted) return;
      if (ref.read(selectedBroadcastModelProvider) != null) {
        Navigator.pushNamed(context, '/tournament_detail_screen');
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open event')),
      );
    }
  }

  Color _getScoreColor(double score, int totalGames) {
    if (totalGames == 0) return kWhiteColor;
    final percentage = score / totalGames;
    if (percentage >= 0.6) return kGreenColor;
    if (percentage >= 0.4) return kWhiteColor;
    return Colors.redAccent;
  }
}

/// Fallback event card when GroupEventCardModel is not available
class _FallbackEventCard extends StatelessWidget {
  const _FallbackEventCard({
    required this.event,
    required this.index,
    required this.onTap,
  });

  final PlayerEventData event;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(12.sp),
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(8.br),
        ),
        child: Row(
          children: [
            // Event icon placeholder
            Container(
              width: 60.w,
              height: 40.h,
              decoration: BoxDecoration(
                color: kLightBlack,
                borderRadius: BorderRadius.circular(6.br),
              ),
              child: Icon(
                Icons.emoji_events_outlined,
                color: kWhiteColor.withValues(alpha: 0.5),
                size: 24.sp,
              ),
            ),
            SizedBox(width: 12.w),
            // Event info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.tourName,
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
                  Row(
                    children: [
                      Icon(
                        Icons.sports_esports_outlined,
                        size: 12.sp,
                        color: kWhiteColor.withValues(alpha: 0.5),
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        '${event.gamesPlayed} ${event.gamesPlayed == 1 ? 'game' : 'games'}',
                        style: AppTypography.textXsRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.5),
                        ),
                      ),
                      if (event.score != null) ...[
                        SizedBox(width: 8.w),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6.w,
                            vertical: 2.h,
                          ),
                          decoration: BoxDecoration(
                            color: _getScoreColor(event.score!, event.gamesPlayed)
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4.br),
                          ),
                          child: Text(
                            '${event.score!.toStringAsFixed(1)}/${event.gamesPlayed}',
                            style: AppTypography.textXsBold.copyWith(
                              color: _getScoreColor(
                                event.score!,
                                event.gamesPlayed,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: kWhiteColor.withValues(alpha: 0.3),
              size: 24.ic,
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(
          duration: 200.ms,
          delay: Duration(milliseconds: (index % 10) * 50),
        )
        .slideY(begin: 0.02, end: 0);
  }

  Color _getScoreColor(double score, int totalGames) {
    if (totalGames == 0) return kWhiteColor;
    final percentage = score / totalGames;
    if (percentage >= 0.6) return kGreenColor;
    if (percentage >= 0.4) return kWhiteColor;
    return Colors.redAccent;
  }
}

/// Provider to fetch GroupEventCardModel for player events
final playerEventCardsProvider = FutureProvider.family
    .autoDispose<Map<String, GroupEventCardModel>, int>((ref, fideId) async {
  try {
    final events = await ref.watch(playerEventsProvider(fideId).future);
    if (events.isEmpty) return {};

    // Get unique group_broadcast_ids from tours
    final groupBroadcastRepo = ref.read(groupBroadcastRepositoryProvider);
    final eventCards = <String, GroupEventCardModel>{};

    // Fetch all group broadcasts for these tours
    for (final event in events) {
      try {
        final broadcast = await groupBroadcastRepo.getGroupBroadcastById(event.tourId);
        final groupBroadcast = GroupBroadcast.fromJson({
          'id': broadcast.id,
          'created_at': DateTime.now().toIso8601String(),
          'name': broadcast.name,
          'search': broadcast.search,
          'max_avg_elo': broadcast.maxAvgElo,
          'date_start': broadcast.dateStart?.toIso8601String(),
          'date_end': broadcast.dateEnd?.toIso8601String(),
          'time_control': broadcast.timeControl,
        });

        eventCards[event.tourId] = GroupEventCardModel.fromGroupBroadcast(
          groupBroadcast,
          [], // No live events needed for player profile
        );
      } catch (_) {
        // Skip events that can't be loaded
      }
    }

    return eventCards;
  } catch (e) {
    debugPrint('[playerEventCardsProvider] Error: $e');
    return {};
  }
});
