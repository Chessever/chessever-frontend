import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class RoundHeader extends ConsumerWidget {
  final dynamic round;
  final List<GamesTourModel> roundGames;

  const RoundHeader({super.key, required this.round, required this.roundGames});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Removed all the individual visibility checking logic
    // Now handled centrally in GamesTourScreen for better performance

    return Container(
      margin: EdgeInsets.only(top: 16.h, bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: kDarkGreyColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kWhiteColor.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4.w,
            height: 20.h,
            decoration: BoxDecoration(
              color: kPrimaryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              '${round.name} ⚫ ${roundGames.length} games',
              style: TextStyle(
                color: kWhiteColor,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
