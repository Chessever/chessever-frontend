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
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
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

    // Watch the current time control filter
    final gamesState = ref.watch(playerProfileGamesKeyProvider(_playerKey));
    final currentTimeControl = gamesState.filter.timeControl;
    final hasActiveFilter = currentTimeControl != GameTimeControlFilter.all;

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

          // Filter out Fischer Random/Chess960 events
          final filteredEvents = events.where((event) {
            final nameLower = event.tourName.toLowerCase();
            return !nameLower.contains('fischer random') &&
                !nameLower.contains('chess960') &&
                !nameLower.contains('chess 960') &&
                !nameLower.contains('frc ') &&
                !nameLower.contains(' frc') &&
                !nameLower.startsWith('frc');
          }).toList();

          // Sort events by start date (most recent first)
          final sortedEvents = List<PlayerEventData>.from(filteredEvents)
            ..sort((a, b) {
              final aDate = a.startDate ?? DateTime(1900);
              final bDate = b.startDate ?? DateTime(1900);
              return bDate.compareTo(aDate);
            });

          return _EventsListContent(
            events: sortedEvents,
            fideId: widget.fideId,
            timeControlFilter: currentTimeControl,
            hasActiveFilter: hasActiveFilter,
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
    this.timeControlFilter = GameTimeControlFilter.all,
    this.hasActiveFilter = false,
  });

  final List<PlayerEventData> events;
  final int? fideId;
  final GameTimeControlFilter timeControlFilter;
  final bool hasActiveFilter;

  /// Check if an event matches the time control filter
  bool _eventMatchesTimeControl(GroupEventCardModel? eventCard) {
    if (timeControlFilter == GameTimeControlFilter.all) return true;
    if (eventCard == null) return true; // Show events without card data when filtering

    final eventTimeControl = eventCard.timeControl?.toLowerCase() ?? '';

    switch (timeControlFilter) {
      case GameTimeControlFilter.classical:
        return eventTimeControl.contains('classical') ||
            eventTimeControl.contains('standard');
      case GameTimeControlFilter.rapid:
        return eventTimeControl.contains('rapid');
      case GameTimeControlFilter.blitz:
        return eventTimeControl.contains('blitz') ||
            eventTimeControl.contains('bullet');
      case GameTimeControlFilter.all:
        return true;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the event cards provider (only if fideId is available)
    final eventCardsAsync = fideId != null
        ? ref.watch(playerEventCardsProvider(fideId!))
        : const AsyncValue<Map<String, GroupEventCardModel>>.data({});

    return eventCardsAsync.when(
      data: (eventCards) {
        // Filter events based on time control
        final filteredEvents = hasActiveFilter
            ? events.where((event) {
                final eventCard = eventCards[event.tourId];
                return _eventMatchesTimeControl(eventCard);
              }).toList()
            : events;

        // Calculate statistics from filtered events
        final totalGames = filteredEvents.fold<int>(0, (sum, e) => sum + e.gamesPlayed);
        final totalScore = filteredEvents.fold<double>(0, (sum, e) => sum + (e.score ?? 0));
        final avgScore = totalGames > 0 ? totalScore / totalGames : 0.0;

        final horizontalPadding = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);

        // Build list items
        final headerItemCount = hasActiveFilter ? 2 : 1; // Filter banner + stats header

        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16.h),
          itemCount: filteredEvents.isEmpty && hasActiveFilter
              ? headerItemCount + 1 // header + empty state
              : filteredEvents.length + headerItemCount,
          itemBuilder: (context, index) {
            // Filter banner
            if (hasActiveFilter && index == 0) {
              return _FilterActiveBanner(
                timeControl: timeControlFilter,
                totalEvents: events.length,
                filteredEvents: filteredEvents.length,
              );
            }

            // Stats header
            final statsHeaderIndex = hasActiveFilter ? 1 : 0;
            if (index == statsHeaderIndex) {
              return _StatsHeader(
                totalEvents: filteredEvents.length,
                totalGames: totalGames,
                avgScore: avgScore,
              );
            }

            // Empty state for filtered results
            if (filteredEvents.isEmpty && hasActiveFilter) {
              return _buildNoFilterResultsState(context, timeControlFilter);
            }

            final eventIndex = index - headerItemCount;
            final event = filteredEvents[eventIndex];
            final eventCard = eventCards[event.tourId];

            if (eventCard != null) {
              return Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: _PlayerEventCard(
                  eventCard: eventCard,
                  playerEventData: event,
                  index: eventIndex,
                ),
              );
            }
            // Fallback to custom card if GroupEventCardModel not available
            return Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: _FallbackEventCard(
                event: event,
                index: eventIndex,
                onTap: () => _navigateToTournament(context, ref, event),
              ),
            );
          },
        );
      },
      loading: () {
        // Calculate statistics from all events while loading cards
        final totalGames = events.fold<int>(0, (sum, e) => sum + e.gamesPlayed);
        final totalScore = events.fold<double>(0, (sum, e) => sum + (e.score ?? 0));
        final avgScore = totalGames > 0 ? totalScore / totalGames : 0.0;

        final horizontalPadding = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);
        final headerItemCount = hasActiveFilter ? 2 : 1;

        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16.h),
          itemCount: events.length + headerItemCount,
          itemBuilder: (context, index) {
            if (hasActiveFilter && index == 0) {
              return _FilterActiveBanner(
                timeControl: timeControlFilter,
                totalEvents: events.length,
                filteredEvents: events.length, // Show all while loading
              );
            }

            final statsHeaderIndex = hasActiveFilter ? 1 : 0;
            if (index == statsHeaderIndex) {
              return _StatsHeader(
                totalEvents: events.length,
                totalGames: totalGames,
                avgScore: avgScore,
              );
            }

            final eventIndex = index - headerItemCount;
            final event = events[eventIndex];

            return Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: _FallbackEventCard(
                event: event,
                index: eventIndex,
                onTap: () => _navigateToTournament(context, ref, event),
              ),
            );
          },
        );
      },
      error: (_, __) {
        // Same as loading - show fallback cards
        final totalGames = events.fold<int>(0, (sum, e) => sum + e.gamesPlayed);
        final totalScore = events.fold<double>(0, (sum, e) => sum + (e.score ?? 0));
        final avgScore = totalGames > 0 ? totalScore / totalGames : 0.0;

        final horizontalPadding = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);
        final headerItemCount = hasActiveFilter ? 2 : 1;

        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16.h),
          itemCount: events.length + headerItemCount,
          itemBuilder: (context, index) {
            if (hasActiveFilter && index == 0) {
              return _FilterActiveBanner(
                timeControl: timeControlFilter,
                totalEvents: events.length,
                filteredEvents: events.length,
              );
            }

            final statsHeaderIndex = hasActiveFilter ? 1 : 0;
            if (index == statsHeaderIndex) {
              return _StatsHeader(
                totalEvents: events.length,
                totalGames: totalGames,
                avgScore: avgScore,
              );
            }

            final eventIndex = index - headerItemCount;
            final event = events[eventIndex];

            return Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: _FallbackEventCard(
                event: event,
                index: eventIndex,
                onTap: () => _navigateToTournament(context, ref, event),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNoFilterResultsState(BuildContext context, GameTimeControlFilter timeControl) {
    const filterRedColor = Color(0xFFEF4444);
    return Center(
      child: Padding(
        padding: EdgeInsets.only(top: 40.h),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 56.sp,
              color: filterRedColor.withValues(alpha: 0.5),
            ),
            SizedBox(height: 12.h),
            Text(
              'No ${timeControl.displayText} events',
              style: AppTypography.textMdMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.85),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'This player has no ${timeControl.displayText.toLowerCase()} tournaments.\nTap the time control card to clear filter.',
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.55),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
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

/// Filter active banner showing which time control filter is applied
class _FilterActiveBanner extends StatelessWidget {
  const _FilterActiveBanner({
    required this.timeControl,
    required this.totalEvents,
    required this.filteredEvents,
  });

  final GameTimeControlFilter timeControl;
  final int totalEvents;
  final int filteredEvents;

  static const _filterRedColor = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: _filterRedColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10.br),
        border: Border.all(
          color: _filterRedColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8.w,
            height: 8.w,
            decoration: const BoxDecoration(
              color: _filterRedColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              'Showing ${timeControl.displayText} events only',
              style: AppTypography.textSmMedium.copyWith(
                color: kWhiteColor,
              ),
            ),
          ),
          Text(
            '$filteredEvents of $totalEvents',
            style: AppTypography.textXsMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.1, end: 0);
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

/// Fallback/skeleton event card that matches EventCard layout exactly
/// Used when GroupEventCardModel is not yet available (loading state)
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
    // Match the exact layout of EventCard._buildPhoneCard + _PlayerEventCard
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          // Main card - matches EventCard._buildPhoneCard layout
          Container(
            decoration: BoxDecoration(
              color: kBlack2Color,
              borderRadius: BorderRadius.circular(8.br),
            ),
            padding: EdgeInsets.all(6.sp),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Image placeholder - matches _EventImage dimensions
                _SkeletonEventImage(),
                SizedBox(width: 12.w),

                // Content in the middle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Event name
                      Text(
                        event.tourName,
                        style: AppTypography.textSmMedium.copyWith(
                          color: kWhiteColor,
                          fontSize: 14.sp,
                          height: 1.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),

                      SizedBox(height: 4.h),

                      // Event details placeholder (date, time control)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (event.startDate != null) ...[
                            Flexible(
                              child: Text(
                                _formatDate(event.startDate!),
                                style: AppTypography.textXsMedium.copyWith(
                                  color: kWhiteColor70,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ] else ...[
                            // Skeleton for date
                            Container(
                              width: 60.w,
                              height: 12.h,
                              decoration: BoxDecoration(
                                color: kLightBlack,
                                borderRadius: BorderRadius.circular(4.br),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(width: 8.w),

                // Star placeholder - matches _StarWidget size
                SizedBox(
                  width: 30.w,
                  height: 40.h,
                  child: Center(
                    child: Container(
                      width: 20.w,
                      height: 20.h,
                      decoration: BoxDecoration(
                        color: kLightBlack,
                        borderRadius: BorderRadius.circular(4.br),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Player stats row - matches _PlayerEventCard layout
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
                      '${event.gamesPlayed} ${event.gamesPlayed == 1 ? 'game' : 'games'}',
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                if (event.score != null)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8.w,
                      vertical: 3.h,
                    ),
                    decoration: BoxDecoration(
                      color: _getScoreColor(
                        event.score!,
                        event.gamesPlayed,
                      ).withValues(alpha: 0.2),
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

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Color _getScoreColor(double score, int totalGames) {
    if (totalGames == 0) return kWhiteColor;
    final percentage = score / totalGames;
    if (percentage >= 0.6) return kGreenColor;
    if (percentage >= 0.4) return kWhiteColor;
    return Colors.redAccent;
  }
}

/// Skeleton event image that matches _EventImage dimensions exactly
/// Uses SkeletonWidget with shimmer effect for smooth loading transition
class _SkeletonEventImage extends StatelessWidget {
  const _SkeletonEventImage();

  @override
  Widget build(BuildContext context) {
    // Use same sizing logic as _EventImage.getImageWidth
    double imageWidth = 90.w;
    if (ResponsiveHelper.isTablet) {
      if (ResponsiveHelper.isLandscape) {
        imageWidth = 70.w;
      } else {
        imageWidth = 80.w;
      }
    }

    return SizedBox(
      width: imageWidth,
      child: AspectRatio(
        aspectRatio: 3 / 2,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6.br),
          child: SkeletonWidget(
            child: Container(
              decoration: BoxDecoration(
                color: kLightBlack,
                borderRadius: BorderRadius.circular(6.br),
              ),
            ),
          ),
        ),
      ),
    );
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
