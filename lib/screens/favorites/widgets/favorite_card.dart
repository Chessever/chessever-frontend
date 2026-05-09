// filepath: /Users/p1/Desktop/chessever/lib/screens/favorites/widgets/favorite_card.dart
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import '../../../utils/app_typography.dart';
import '../../../theme/app_theme.dart';

class FavoriteCard extends StatefulWidget {
  final int rank;
  final String playerName;
  final String countryCode;
  final int elo;
  final String age;
  final VoidCallback? onRemoveFavorite;

  const FavoriteCard({
    Key? key,
    required this.rank,
    required this.playerName,
    required this.countryCode,
    required this.elo,
    required this.age,
    this.onRemoveFavorite,
  }) : super(key: key);

  @override
  State<FavoriteCard> createState() => _FavoriteCardState();
}

class _FavoriteCardState extends State<FavoriteCard> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48.h,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.zero,
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      child: Row(
        children: [
          // Rank number
          SizedBox(
            width: 24.w,
            child: Text(
              '${widget.rank}.',
              style: AppTypography.textXsMedium.copyWith(color: context.colors.textPrimary),
            ),
          ),

          // Country flag
          Container(
            margin: EdgeInsets.only(right: 6.w),
            child: getCountryFlag(widget.countryCode),
          ),

          // GM prefix and player name
          Expanded(
            flex: 3,
            child: RichText(
              textAlign: TextAlign.left,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: widget.playerName,
                    style: AppTypography.textXsMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ELO rating - center aligned to match header
          Expanded(
            flex: 1,
            child: Text(
              widget.elo.toString(),
              textAlign: TextAlign.center,
              style: AppTypography.textXsMedium.copyWith(color: context.colors.textPrimary),
            ),
          ),

          // Age - using Expanded to match header
          Expanded(
            flex: 1,
            child: Text(
              widget.age.toString(),
              textAlign: TextAlign.center,
              style: AppTypography.textXsMedium.copyWith(color: context.colors.textPrimary),
            ),
          ),

          // Remove favorite icon
          GestureDetector(
            onTap: () {
              if (widget.onRemoveFavorite != null) {
                // No need for setState here as the card will be removed from the list
                widget.onRemoveFavorite!();
              }
            },
            child: SizedBox(
              width: 30.w,
              child: Icon(Icons.favorite, color: kRedColor, size: 20.ic),
            ),
          ),
        ],
      ),
    );
  }

  Widget getCountryFlag(String countryCode) {
    // Simple country flag implementation
    // In a real app, you would use a proper flag package like country_icons
    switch (countryCode) {
      case 'NO':
        return Image.network(
          'https://flagcdn.com/w20/no.png',
          width: 20.w,
          height: 14.h,
          errorBuilder:
              (context, error, stackTrace) =>
                  Text('🇳🇴', style: TextStyle(fontSize: 16.sp)),
        );
      case 'US':
        return Image.network(
          'https://flagcdn.com/w20/us.png',
          width: 20.w,
          height: 14.h,
          errorBuilder:
              (context, error, stackTrace) =>
                  Text('🇺🇸', style: TextStyle(fontSize: 16.sp)),
        );
      case 'IN':
        return Image.network(
          'https://flagcdn.com/w20/in.png',
          width: 20.w,
          height: 14.h,
          errorBuilder:
              (context, error, stackTrace) =>
                  Text('🇮🇳', style: TextStyle(fontSize: 16.sp)),
        );
      case 'UZ':
        return Image.network(
          'https://flagcdn.com/w20/uz.png',
          width: 20.w,
          height: 14.h,
          errorBuilder:
              (context, error, stackTrace) =>
                  Text('🇺🇿', style: TextStyle(fontSize: 16.sp)),
        );
      default:
        return Text(
          countryCode,
          style: AppTypography.textXsMedium.copyWith(color: context.colors.textPrimary),
        );
    }
  }
}
