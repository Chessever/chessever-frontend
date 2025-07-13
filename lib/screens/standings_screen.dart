import 'package:chessever2/screens/tournaments/games_tour_screen.dart';
import 'package:chessever2/screens/tournaments/widget/empty_widget.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/standings_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/standing_score_card.dart';
import '../utils/app_typography.dart';

class StandingsScreen extends ConsumerWidget {
  const StandingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerStandings = ref.watch(standingsProvider);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.0.sp),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: 19.h),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 8.0.sp,
            ), // Match ScoreCard padding
            child: Row(
              children: [
                // Player column (matches Expanded in ScoreCard)
                Expanded(
                  child: Text(
                    'Player',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                    ),
                  ),
                ),
                // Elo column (matches ScoreCard width of 100)
                SizedBox(
                  width: 100.w,
                  child: Text(
                    'Elo',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                // Score column (matches ScoreCard width of 60)
                SizedBox(
                  width: 60.w,
                  child: Text(
                    'Score',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                    ),
                    textAlign: TextAlign.end, // Match ScoreCard's textAlign
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          playerStandings.isEmpty
              ? EmptyWidget(title: "No data available")
              : ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: playerStandings.length,
                itemBuilder: (context, index) {
                  final player = playerStandings[index];
                  return Padding(
                    padding: EdgeInsets.only(bottom: 16.0.sp),
                    child: StandingScoreCard(
                      countryCode: player.countryCode,
                      title: player.title,
                      name: player.name,
                      score: player.score,
                      scoreChange: player.scoreChange,
                      matchScore: player.matchScore,
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}
