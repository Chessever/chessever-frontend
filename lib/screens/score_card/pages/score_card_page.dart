import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class ScoreCard extends StatelessWidget {
  const ScoreCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () {},
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'GM Magnus Carlsen',
              style: AppTypography.textXxsRegular.copyWith(color: kWhiteColor),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_down,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 10.br),
            child: SvgPicture.asset(SvgAsset.favouriteIcon2, height: 18),
          ),
        ],
        centerTitle: false,
      ),
      body: Column(
        children: [
          // Player profile section
          Container(
            padding: EdgeInsets.all(20.sp),
            child: Row(
              children: [
                // Profile image
                // Container(
                //   width: 80,
                //   height: 80,
                //   decoration: BoxDecoration(
                //     borderRadius: BorderRadius.circular(8),
                //     image: SvgPicture.asset(assetName)
                //   ),
                // ),
                SvgPicture.asset(SvgAsset.images),
                const SizedBox(width: 20),
                // Stats
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PERFORMANCE',
                            style: AppTypography.textXsMedium.copyWith(
                              color: kWhiteColor70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '2873',
                            style: AppTypography.textXsBold.copyWith(
                              color: kWhiteColor,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SCORE',
                            style: AppTypography.textXsMedium.copyWith(
                              color: kWhiteColor70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '2.5/3',
                            style: AppTypography.textXsBold.copyWith(
                              color: kWhiteColor,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'RATING',
                            style: AppTypography.textXsMedium.copyWith(
                              color: kWhiteColor70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '+4',
                            style: AppTypography.textXsBold.copyWith(
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

          // Rankings list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _buildRankingItem(
                  rank: 1,
                  flag: '🇨🇳',
                  name: 'GM Hikaru, Nakamura',
                  rating: '2791',
                  icon: Icons.person,
                  iconColor: Colors.white,
                ),
                // _buildRankingItem(
                //   rank: 2,
                //   flag: '🇮🇳',
                //   name: 'GM Gukesh, D',
                //   rating: '2753',
                //   icon: Icons.person_outline,
                //   iconColor: Colors.white,
                // ),
                // _buildRankingItem(
                //   rank: 3,
                //   flag: '🇨🇳',
                //   name: 'GM Wei Yi',
                //   rating: '2728',
                //   icon: Icons.person_outline,
                //   iconColor: Colors.white,
                //   hasHalfPoint: true,
                // ),
                // _buildRankingItem(
                //   rank: 4,
                //   flag: '🇺🇸',
                //   name: 'GM Hikaru, Nakamura',
                //   rating: '2748',
                //   icon: Icons.person,
                //   iconColor: Colors.white,
                // ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankingItem({
    required int rank,
    required String flag,
    required String name,
    required String rating,
    required IconData icon,
    required Color iconColor,
    bool hasHalfPoint = false,
  }) {
    return Container(
      // margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.symmetric(vertical: 12.sp, horizontal: 10.sp),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8.br),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Rank + Flag
          SizedBox(
            width: 40.w, // Adjusted for flag emoji + rank
            child: Text(
              '$rank. $flag',
              style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
            ),
          ),

          // Name (Expanded)
          Expanded(
            child: Text(
              name,
              style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Rating
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              rating,
              style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
            ),
          ),

          // Icon + Score
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 4),
              Text(
                hasHalfPoint ? '½' : '1',
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
