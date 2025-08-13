import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/standings/standing_screen_provider.dart';
import 'package:chessever2/screens/tournaments/widget/empty_widget.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../widgets/standing_score_card.dart';
import '../../utils/app_typography.dart';

class StandingsScreen extends ConsumerWidget {
  const StandingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerStandings = ref.watch(standingScreenProvider);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.0.sp),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: 16.h),
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
          SizedBox(height: 4.h),
          playerStandings.when(
            data: (data) {
              return data.isEmpty
                  ? Center(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(height: 64.h),
                        EmptyWidget(title: "No data available"),
                      ],
                    ),
                  )
                  : Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.only(
                        bottom:
                            MediaQuery.of(context).viewInsets.bottom + 16.sp,
                      ),
                      itemCount: data.length,
                      itemBuilder: (context, index) {
                        final player = data[index];
                        final validCountryCode = ref
                            .read(locationServiceProvider)
                            .getValidCountryCode(player.countryCode);
                        return Padding(
                          padding: EdgeInsets.only(
                            // bottom: 16.sp,
                            // top: index == 0 ? 16.sp : 0,
                          ),
                          child: StandingScoreCard(
                            countryCode: validCountryCode,
                            title: player.title,
                            name: player.name,
                            score: player.score,
                            scoreChange: player.scoreChange,
                            matchScore: player.matchScore,
                            index: index,
                            isFirst: index == 0,
                            isLast: index == data.length - 1,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ScoreCardScreen(
                                    score:player.matchScore??"" ,
                                    performance: player.score,
                                    scoreChangeData: player.scoreChange,
                                    

                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  );
            },
            error: (e, _) {
              return _StandingScreenLoading();
            },
            loading: () {
              return _StandingScreenLoading();
            },
          ),
        ],
      ),
    );
  }
}

class _StandingScreenLoading extends StatelessWidget {
  const _StandingScreenLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final List<PlayerStandingModel> data = [
      PlayerStandingModel(
        countryCode: 'ARM',
        title: 'GM',
        name: 'Aronian, Levon',
        score: 2712,
        scoreChange: -12,
        matchScore: '5.0 / 9',
      ),
      PlayerStandingModel(
        countryCode: 'AZE',
        title: 'GM',
        name: 'Mamedyarov, Shakhriyar',
        score: 2704,
        scoreChange: 6,
        matchScore: '5.0 / 9',
      ),
      PlayerStandingModel(
        countryCode: 'USA',
        title: 'GM',
        name: 'Nakamura, Hikaru',
        score: 2698,
        scoreChange: -5,
        matchScore: '4.5 / 9',
      ),
    ];

    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16.sp,
      ),
      itemCount: data.length,
      itemBuilder: (context, index) {
        final player = data[index];
        return SkeletonWidget(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: 16.sp,
              top: index == 0 ? 16.sp : 0,
            ),
            child: StandingScoreCard(
              countryCode: player.countryCode,
              title: player.title,
              name: player.name,
              score: player.score,
              scoreChange: player.scoreChange,
              matchScore: player.matchScore,
              index: index,
              isFirst: index == 0,
              isLast: index == data.length - 1,
              onTap: () {},
            ),
          ),
        );
      },
    );
  }
}
