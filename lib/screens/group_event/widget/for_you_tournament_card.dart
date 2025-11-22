import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// Tournament card for For You tab - displays tournament info and handles navigation
class ForYouTournamentCard extends ConsumerWidget {
  const ForYouTournamentCard({
    super.key,
    required this.tourId,
    required this.tourName,
    required this.hasLiveGames,
    required this.gameCount,
    required this.isFirst,
  });

  final String tourId;
  final String tourName; // Fallback name from games
  final bool hasLiveGames;
  final int gameCount;
  final bool isFirst;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fetch the actual tournament data
    final tournamentAsync = ref.watch(_tournamentProvider(tourId));

    return tournamentAsync.when(
      data: (tournament) => _buildCard(context, ref, tournament),
      loading: () => _buildLoadingCard(),
      error: (_, __) => _buildFallbackCard(context, ref),
    );
  }

  Widget _buildCard(BuildContext context, WidgetRef ref, GroupBroadcast tournament) {
    return GestureDetector(
      onTap: () => _onTournamentTap(context, ref),
      child: Container(
        margin: EdgeInsets.only(
          top: isFirst ? 0 : 16.sp,
          bottom: 12.sp,
        ),
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(8.br),
          border: Border.all(
            color: hasLiveGames
                ? kRedColor.withValues(alpha: 0.2)
                : kDarkGreyColor.withValues(alpha: 0.3),
          ),
        ),
        padding: EdgeInsets.all(12.sp),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tournament name and status
            Row(
              children: [
                if (hasLiveGames) ...[
                  _LiveIndicator(),
                  SizedBox(width: 8.sp),
                ],
                Expanded(
                  child: Text(
                    tournament.name, // Use the properly formatted name
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                      fontSize: 14.sp,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 3.sp),
                  decoration: BoxDecoration(
                    color: hasLiveGames
                        ? kRedColor.withValues(alpha: 0.15)
                        : kDarkGreyColor.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4.br),
                  ),
                  child: Text(
                    '$gameCount ${gameCount == 1 ? 'game' : 'games'}',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w500,
                      color: hasLiveGames ? kRedColor : kWhiteColor70,
                    ),
                  ),
                ),
              ],
            ),

            // Tournament details
            if (tournament.dateStart != null || tournament.timeControl != null) ...[
              SizedBox(height: 6.sp),
              Row(
                children: [
                  // Date range
                  if (tournament.dateStart != null) ...[
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 12.sp,
                      color: kWhiteColor70,
                    ),
                    SizedBox(width: 4.sp),
                    Text(
                      _formatDateRange(tournament.dateStart, tournament.dateEnd),
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor70,
                      ),
                    ),
                  ],
                  // Time control
                  if (tournament.timeControl != null) ...[
                    if (tournament.dateStart != null) ...[
                      SizedBox(width: 12.sp),
                      _buildDot(),
                      SizedBox(width: 12.sp),
                    ],
                    _buildTimeControlBadge(tournament.timeControl!),
                  ],
                  // Average ELO
                  if (tournament.maxAvgElo != null && tournament.maxAvgElo! > 0) ...[
                    SizedBox(width: 12.sp),
                    _buildDot(),
                    SizedBox(width: 12.sp),
                    Text(
                      'Elo ${tournament.maxAvgElo}',
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor70,
                      ),
                    ),
                  ],
                ],
              ),
            ],

            // Tap hint
            SizedBox(height: 6.sp),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Tap to view tournament',
                  style: AppTypography.textXsRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.4),
                    fontSize: 10.sp,
                  ),
                ),
                SizedBox(width: 4.sp),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 10.sp,
                  color: kWhiteColor.withValues(alpha: 0.4),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.02, end: 0);
  }

  Widget _buildLoadingCard() {
    return Container(
      margin: EdgeInsets.only(
        top: isFirst ? 0 : 16.sp,
        bottom: 12.sp,
      ),
      height: 60.sp,
      decoration: BoxDecoration(
        color: kBlack2Color.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8.br),
      ),
    ).animate().shimmer(
      duration: 1200.ms,
      color: kWhiteColor.withValues(alpha: 0.05),
    );
  }

  Widget _buildFallbackCard(BuildContext context, WidgetRef ref) {
    // If we can't fetch tournament data, show a simpler card with fallback name
    return GestureDetector(
      onTap: () => _onTournamentTap(context, ref),
      child: Container(
        margin: EdgeInsets.only(
          top: isFirst ? 0 : 16.sp,
          bottom: 12.sp,
        ),
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(8.br),
        ),
        padding: EdgeInsets.all(12.sp),
        child: Row(
          children: [
            if (hasLiveGames) ...[
              _LiveIndicator(),
              SizedBox(width: 8.sp),
            ],
            Expanded(
              child: Text(
                _formatTournamentName(tourName), // Clean up the fallback name
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor,
                  fontSize: 14.sp,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 3.sp),
              decoration: BoxDecoration(
                color: hasLiveGames
                    ? kRedColor.withValues(alpha: 0.15)
                    : kDarkGreyColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4.br),
              ),
              child: Text(
                '$gameCount',
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w500,
                  color: hasLiveGames ? kRedColor : kWhiteColor70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeControlBadge(String timeControl) {
    IconData icon;
    Color color;

    if (timeControl.toLowerCase().contains('rapid')) {
      icon = Icons.timer_outlined;
      color = Colors.orange;
    } else if (timeControl.toLowerCase().contains('blitz')) {
      icon = Icons.bolt;
      color = Colors.yellow;
    } else if (timeControl.toLowerCase().contains('bullet')) {
      icon = Icons.flash_on;
      color = Colors.red;
    } else {
      icon = Icons.schedule;
      color = kWhiteColor70;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12.sp, color: color),
        SizedBox(width: 3.sp),
        Text(
          timeControl,
          style: AppTypography.textXsRegular.copyWith(color: kWhiteColor70),
        ),
      ],
    );
  }

  Widget _buildDot() {
    return Container(
      width: 3.sp,
      height: 3.sp,
      decoration: BoxDecoration(
        color: kWhiteColor.withValues(alpha: 0.3),
        shape: BoxShape.circle,
      ),
    );
  }

  String _formatDateRange(DateTime? start, DateTime? end) {
    if (start == null) return '';

    final startFormat = DateFormat('MMM d');
    final endFormat = end != null && end.year != start.year
        ? DateFormat('MMM d, y')
        : DateFormat('MMM d');

    if (end == null || end.difference(start).inDays < 1) {
      return startFormat.format(start);
    }

    return '${startFormat.format(start)} - ${endFormat.format(end)}';
  }

  String _formatTournamentName(String rawName) {
    // Clean up tournament names that come with dashes or underscores
    return rawName
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '')
        .join(' ')
        .trim();
  }

  Future<void> _onTournamentTap(BuildContext context, WidgetRef ref) async {
    HapticFeedbackService.cardTap();

    try {
      // Always resolve via repository so we correctly map tour IDs -> group_broadcast_ids
      final tournament = await ref.read(_tournamentProvider(tourId).future);

      // Set the selected tournament
      ref.read(selectedBroadcastModelProvider.notifier).state = tournament;

      // Navigate to tournament detail
      if (context.mounted) {
        Navigator.pushNamed(context, '/tournament_detail_screen');
      }
    } catch (e) {
      debugPrint('[ForYouTournamentCard] Error navigating to tournament $tourId: $e');

      // Tournament couldn't be resolved; fall back to a minimal tournament so
      // the detail screen still opens with available games.
      if (context.mounted) {
        try {
          // Create a minimal tournament object with just the ID and name
          final fallbackTournament = GroupBroadcast(
            id: tourId,
            name: _formatTournamentName(tourName),
            createdAt: DateTime.now(),
            search: [tourId, tourName], // Search terms for the tournament
            dateStart: hasLiveGames ? DateTime.now() : null,
            maxAvgElo: null,
            dateEnd: null,
            timeControl: null,
          );

          // Set the fallback tournament
          ref.read(selectedBroadcastModelProvider.notifier).state = fallbackTournament;

          // Navigate to tournament detail screen which will show the games
          if (context.mounted) {
            Navigator.pushNamed(context, '/tournament_detail_screen');
          }
        } catch (fallbackError) {
          debugPrint('[ForYouTournamentCard] Failed to navigate with fallback: $fallbackError');

          // As a last resort, show a snackbar to the user
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Unable to open tournament details'),
                backgroundColor: Colors.orange,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    }
  }
}

/// Live indicator widget with pulsing animation
class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
      decoration: BoxDecoration(
        color: kRedColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4.br),
        border: Border.all(
          color: kRedColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6.sp,
            height: 6.sp,
            decoration: BoxDecoration(
              color: kRedColor,
              shape: BoxShape.circle,
            ),
          )
              .animate(
                onPlay: (controller) => controller.repeat(reverse: true),
              )
              .scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1.2, 1.2),
                duration: 800.ms,
              ),
          SizedBox(width: 4.sp),
          Text(
            'LIVE',
            style: AppTypography.textXsMedium.copyWith(
              color: kRedColor,
              fontSize: 10.sp,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// Provider to fetch tournament data by ID
final _tournamentProvider = FutureProvider.autoDispose.family<GroupBroadcast, String>((ref, tourId) async {
  try {
    return await ref.read(groupBroadcastRepositoryProvider).getGroupBroadcastById(tourId);
  } catch (e) {
    debugPrint('[ForYouTournamentCard] Error fetching tournament $tourId: $e');
    rethrow;
  }
});
