import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Tournament card for For You tab - displays tournament info and handles navigation
class ForYouTournamentCard extends ConsumerWidget {
  const ForYouTournamentCard({
    super.key,
    required this.tourId,
    required this.groupKey,
    required this.tourName,
    required this.hasLiveGames,
    required this.gameCount,
    required this.isFirst,
  });

  final String tourId;
  final String
  groupKey; // The group_broadcast_id (mapped from tourId) - used for favorite detection
  final String tourName; // Fallback name from games
  final bool hasLiveGames;
  final int gameCount;
  final bool isFirst;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fetch the actual tournament data using groupKey (the group_broadcast_id)
    // This ensures we get the correct umbrella event for favorite detection
    final tournamentAsync = ref.watch(_tournamentProvider(groupKey));

    return tournamentAsync.when(
      data: (tournament) => _buildCard(context, ref, tournament),
      loading: () => _buildLoadingCard(context),
      error: (_, _) => _buildFallbackCard(context, ref),
    );
  }

  Widget _buildCard(
    BuildContext context,
    WidgetRef ref,
    GroupBroadcast tournament,
  ) {
    final liveIds =
        ref.watch(liveGroupBroadcastIdsProvider).valueOrNull ?? const [];
    final model = GroupEventCardModel.fromGroupBroadcast(tournament, liveIds);

    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 0 : 16.sp, bottom: 12.sp),
      child: EventCard(
        tourEventCardModel: model,
        showHeartIndicator: true,
        heroTagSuffix: 'for-you-${model.id}',
        onTap: () => _onTournamentTap(context, ref),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.02, end: 0);
  }

  Widget _buildLoadingCard(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: isFirst ? 0 : 16.sp, bottom: 12.sp),
      height: 60.sp,
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(8.br),
      ),
    ).animate().shimmer(
      duration: 1200.ms,
      color: context.colors.divider.withValues(alpha: 0.4),
    );
  }

  Widget _buildFallbackCard(BuildContext context, WidgetRef ref) {
    // Use groupKey as the ID so EventCard can properly look up favorite players
    final fallbackTournament = GroupBroadcast(
      id: groupKey,
      name: _formatTournamentName(tourName),
      createdAt: DateTime.now(),
      search: [groupKey, tourId, tourName],
      maxAvgElo: null,
      dateStart: null,
      dateEnd: null,
      timeControl: null,
    );

    final model = GroupEventCardModel.fromGroupBroadcast(
      fallbackTournament,
      const [],
    );

    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 0 : 16.sp, bottom: 12.sp),
      child: EventCard(
        tourEventCardModel: model,
        showHeartIndicator: true,
        heroTagSuffix: 'for-you-${model.id}',
        onTap: () => _onTournamentTap(context, ref),
      ),
    );
  }

  String _formatTournamentName(String rawName) {
    // Clean up tournament names that come with dashes or underscores
    return rawName
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) =>
              word.isNotEmpty
                  ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
                  : '',
        )
        .join(' ')
        .trim();
  }

  Future<void> _onTournamentTap(BuildContext context, WidgetRef ref) async {
    HapticFeedbackService.cardTap();

    try {
      // Always resolve via repository using groupKey (group_broadcast_id)
      final tournament = await ref.read(_tournamentProvider(groupKey).future);

      // Set the selected tournament
      ref.read(selectedBroadcastModelProvider.notifier).state = tournament;

      // Navigate to tournament detail (games tab)
      if (context.mounted) {
        ref.read(selectedTourModeProvider.notifier).state =
            TournamentDetailScreenMode.games;
        Navigator.pushNamed(context, '/tournament_detail_screen');
      }
    } catch (e) {
      debugPrint(
        '[ForYouTournamentCard] Error navigating to tournament $groupKey: $e',
      );

      // Tournament couldn't be resolved; fall back to a minimal tournament so
      // the detail screen still opens with available games.
      if (context.mounted) {
        try {
          // Create a minimal tournament object with groupKey as ID
          final fallbackTournament = GroupBroadcast(
            id: groupKey,
            name: _formatTournamentName(tourName),
            createdAt: DateTime.now(),
            search: [
              groupKey,
              tourId,
              tourName,
            ], // Search terms for the tournament
            dateStart: hasLiveGames ? DateTime.now() : null,
            maxAvgElo: null,
            dateEnd: null,
            timeControl: null,
          );

          // Set the fallback tournament
          ref.read(selectedBroadcastModelProvider.notifier).state =
              fallbackTournament;

          // Navigate to tournament detail screen (games tab)
          if (context.mounted) {
            ref.read(selectedTourModeProvider.notifier).state =
                TournamentDetailScreenMode.games;
            Navigator.pushNamed(context, '/tournament_detail_screen');
          }
        } catch (fallbackError) {
          debugPrint(
            '[ForYouTournamentCard] Failed to navigate with fallback: $fallbackError',
          );

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

// Provider to fetch tournament data by ID
final _tournamentProvider = FutureProvider.autoDispose
    .family<GroupBroadcast, String>((ref, tourId) async {
      try {
        return await ref
            .read(groupBroadcastRepositoryProvider)
            .getGroupBroadcastById(tourId);
      } catch (e) {
        debugPrint(
          '[ForYouTournamentCard] Error fetching tournament $tourId: $e',
        );
        rethrow;
      }
    });
