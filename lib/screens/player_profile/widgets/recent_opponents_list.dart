import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

/// List displaying recent opponents with game results.
class RecentOpponentsList extends StatelessWidget {
  const RecentOpponentsList({super.key, required this.opponents});

  final List<RecentOpponent> opponents;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: opponents.length,
        separatorBuilder:
            (context, index) => Divider(
              color: context.colors.divider,
              height: 1,
              indent: 16.sp,
              endIndent: 16.sp,
            ),
        itemBuilder: (context, index) {
          final opponent = opponents[index];
          return _buildOpponentRow(
            context: context,
            index: index + 1,
            opponent: opponent,
            isFirst: index == 0,
            isLast: index == opponents.length - 1,
          );
        },
      ),
    );
  }

  Widget _buildOpponentRow({
    required BuildContext context,
    required int index,
    required RecentOpponent opponent,
    required bool isFirst,
    required bool isLast,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 12.sp),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.vertical(
          top: isFirst ? Radius.circular(12.br) : Radius.zero,
          bottom: isLast ? Radius.circular(12.br) : Radius.zero,
        ),
      ),
      child: Row(
        children: [
          // Row number
          SizedBox(
            width: 24.w,
            child: Text(
              '$index',
              style: AppTypography.textSmMedium.copyWith(color: context.colors.textPrimaryMuted),
            ),
          ),

          // Result indicator (color square showing if played as white/black and result)
          _buildResultIndicator(context, opponent),

          SizedBox(width: 10.w),

          // Country flag
          opponent.countryCode.toUpperCase() == 'FID'
              ? Image.asset(
                PngAsset.fideLogo,
                height: 14.h,
                width: 20.w,
                fit: BoxFit.cover,
                cacheWidth:
                    (20 * MediaQuery.devicePixelRatioOf(context)).toInt(),
                cacheHeight:
                    (14 * MediaQuery.devicePixelRatioOf(context)).toInt(),
              )
              : CountryFlag.fromCountryCode(
                opponent.countryCode,
                theme: ImageTheme(height: 14.h, width: 20.w),
              ),

          SizedBox(width: 8.w),

          // Title and Name
          Expanded(
            child: Text(
              '${opponent.title != null ? '${opponent.title} ' : ''}${opponent.name}',
              style: AppTypography.textSmMedium.copyWith(color: context.colors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          SizedBox(width: 8.w),

          // Rating
          Text(
            opponent.rating.toString(),
            style: AppTypography.textSmMedium.copyWith(color: context.colors.textPrimaryMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildResultIndicator(BuildContext context, RecentOpponent opponent) {
    // The indicator shows:
    // - Top half: player's color (white if playedAsWhite, black otherwise)
    // - Bottom half: result color (green=win, gray=draw, red=loss)
    final resultColor = _getResultColor(context, opponent.result);
    // Literal piece colors — always white square for "played as white" and
    // black square for "played as black", independent of theme.
    final playerColor = opponent.playedAsWhite ? Colors.white : Colors.black;

    return Container(
      width: 20.w,
      height: 20.h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4.br),
        border: Border.all(color: context.colors.divider, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Top half - player's piece color
          Expanded(child: Container(color: playerColor)),
          // Bottom half - result color
          Expanded(child: Container(color: resultColor)),
        ],
      ),
    );
  }

  Color _getResultColor(BuildContext context, double result) {
    if (result == 1.0) {
      return kGreenColor; // Win
    } else if (result == 0.5) {
      return context.colors.textPrimaryMuted; // Draw
    } else {
      return kRedColor; // Loss
    }
  }
}
