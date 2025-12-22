import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// Events tab showing tournaments the player has participated in
class PlayerEventsTab extends ConsumerStatefulWidget {
  const PlayerEventsTab({super.key, required this.fideId});

  final int fideId;

  @override
  ConsumerState<PlayerEventsTab> createState() => _PlayerEventsTabState();
}

class _PlayerEventsTabState extends ConsumerState<PlayerEventsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final eventsAsync = ref.watch(playerEventsProvider(widget.fideId));

    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        ref.invalidate(playerEventsProvider(widget.fideId));
      },
      color: kWhiteColor,
      backgroundColor: kBlack2Color,
      child: eventsAsync.when(
        data: (events) {
          if (events.isEmpty) {
            return _buildEmptyState();
          }

          // Sort events by games played (descending)
          final sortedEvents = List<PlayerEventData>.from(events)
            ..sort((a, b) => b.gamesPlayed.compareTo(a.gamesPlayed));

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            itemCount: sortedEvents.length + 1, // +1 for header
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: EdgeInsets.only(bottom: 16.h),
                  child: _buildHeader(events.length),
                );
              }

              final event = sortedEvents[index - 1];
              return Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: _EventCard(
                  event: event,
                  index: index - 1,
                  onTap: () => _navigateToTournament(event),
                ),
              );
            },
          );
        },
        loading: () => _buildLoadingState(),
        error: (error, _) => _buildErrorState(error.toString()),
      ),
    );
  }

  Widget _buildHeader(int totalEvents) {
    return Container(
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kPrimaryColor.withValues(alpha: 0.15),
            kPrimaryColor.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kPrimaryColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48.w,
            height: 48.h,
            decoration: BoxDecoration(
              color: kPrimaryColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12.br),
            ),
            child: Icon(
              Icons.emoji_events_outlined,
              color: kPrimaryColor,
              size: 24.ic,
            ),
          ),
          SizedBox(width: 16.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$totalEvents Tournaments',
                style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
              ),
              Text(
                'Events this player participated in',
                style: AppTypography.textXsRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.02, end: 0);
  }

  Future<void> _navigateToTournament(PlayerEventData event) async {
    HapticFeedbackService.buttonPress();
    try {
      final broadcast = await ref
          .read(groupBroadcastRepositoryProvider)
          .getGroupBroadcastById(event.tourId);
      ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;

      if (!mounted) return;
      if (ref.read(selectedBroadcastModelProvider) != null) {
        Navigator.pushNamed(context, '/tournament_detail_screen');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open event')),
      );
    }
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
                  ref.invalidate(playerEventsProvider(widget.fideId));
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

/// Event card widget displaying tournament information
class _EventCard extends StatelessWidget {
  const _EventCard({
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
        padding: EdgeInsets.all(16.sp),
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: kDividerColor),
        ),
        child: Row(
          children: [
            // Tournament icon
            Container(
              width: 48.w,
              height: 48.h,
              decoration: BoxDecoration(
                color: _getEventColor(index).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10.br),
              ),
              child: Icon(
                _getEventIcon(index),
                color: _getEventColor(index),
                size: 24.ic,
              ),
            ),

            SizedBox(width: 14.w),

            // Tournament info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.tourName,
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
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
                      if (event.score != null) ...[
                        SizedBox(width: 12.w),
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
                  if (event.startDate != null) ...[
                    SizedBox(height: 4.h),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 12.sp,
                          color: kWhiteColor.withValues(alpha: 0.4),
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          _formatDate(event.startDate!),
                          style: AppTypography.textXsRegular.copyWith(
                            color: kWhiteColor.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Arrow
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
        .slideX(begin: 0.02, end: 0);
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date).inDays;

    if (diff < 7) {
      return '${diff}d ago';
    } else if (diff < 30) {
      return '${diff ~/ 7}w ago';
    } else if (diff < 365) {
      return DateFormat('MMM yyyy').format(date);
    } else {
      return DateFormat('yyyy').format(date);
    }
  }

  Color _getEventColor(int index) {
    final colors = [
      const Color(0xFF4A90A4), // Blue
      const Color(0xFFD4AF37), // Gold
      const Color(0xFF6B8E23), // Green
      const Color(0xFF8B4513), // Brown
      const Color(0xFF8B008B), // Purple
      const Color(0xFFB8860B), // Dark Gold
    ];
    return colors[index % colors.length];
  }

  IconData _getEventIcon(int index) {
    final icons = [
      Icons.emoji_events_outlined,
      Icons.military_tech_outlined,
      Icons.workspace_premium_outlined,
      Icons.star_outline_rounded,
      Icons.diamond_outlined,
      Icons.auto_awesome_outlined,
    ];
    return icons[index % icons.length];
  }

  Color _getScoreColor(double score, int totalGames) {
    if (totalGames == 0) return kWhiteColor;
    final percentage = score / totalGames;
    if (percentage >= 0.6) return kGreenColor;
    if (percentage >= 0.4) return kWhiteColor;
    return Colors.redAccent;
  }
}
