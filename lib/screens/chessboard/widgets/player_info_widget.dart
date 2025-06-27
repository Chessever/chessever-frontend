import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

class PlayerInfoWidget extends StatelessWidget {
  const PlayerInfoWidget({
    required this.name,
    required this.rating,
    required this.time,
    required this.isTop,
    super.key,
  });

  final String name;
  final String rating;
  final String time;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (isTop) ...[
            // For top player (black)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor,
                  ),
                ),
                SizedBox(width: 2),
                Text(
                  rating,
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor,
                  ),
                ),
              ],
            ),
            Text(
              time,
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
          ] else ...[
            // For bottom player (white)
            Text(
              time,
              style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  name,
                  style: AppTypography.textSmMedium.copyWith(
                    color: kWhiteColor,
                  ),
                ),
                SizedBox(width: 2),
                Text(
                  rating,
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
