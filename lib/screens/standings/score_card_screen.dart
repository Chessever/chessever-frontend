import 'package:chessever2/screens/standings/widget/scoreboard_appbar.dart';
import 'package:chessever2/screens/standings/widget/scoreboard_card_widget.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class ScoreCardScreen extends StatelessWidget {
  final int performance;
  final String score;
  final int scoreChangeData;

  const ScoreCardScreen({
    super.key,
    required this.performance,
    required this.score,
    required this.scoreChangeData,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),

          ScoreboardAppbar(),
          SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0.sp),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 65.h,
                  width: 64.w,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.red,
                  ),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "PERFORMANCE",
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            performance.toString(),
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "SCORE",
                            style: AppTypography.textSmMedium.copyWith( 
                              color: kWhiteColor,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            score,
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "RATING",
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            "+ ${scoreChangeData.toString()}",
                            style: AppTypography.textSmMedium.copyWith(
                              color: kGreenColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: 4,
              itemBuilder: (context, index) {
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.0.sp),
                  child: ScoreboardCardWidget(
                    countryCode: "NP",
                    title: "Ding, Liren",
                    name: "Gukesh, D",
                    score: 235,
                    scoreChange: 5,
                    matchScore: "35",
                    index: index,
                    isFirst: index == 0,
                    isLast: index == 4 - 1,
                    onTap: () {},
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
