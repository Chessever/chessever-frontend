import 'package:chessever2/screens/tournaments/games_tour_screen.dart';
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
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 19),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 8.0,
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
                  width: 100,
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
                  width: 60,
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
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: ScoreCard(
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
