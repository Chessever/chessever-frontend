import 'package:flutter/material.dart';
import '../../../utils/app_typography.dart';
import '../../../theme/app_theme.dart'; // Import app theme

class PlayerCard extends StatelessWidget {
  final int rank;
  final String playerName;
  final String countryCode;
  final int elo;
  final int age;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  const PlayerCard({
    Key? key,
    required this.rank,
    required this.playerName,
    required this.countryCode,
    required this.elo,
    required this.age,
    this.isFavorite = false,
    this.onFavoriteToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Navigate to standings screen when the card is tapped
        Navigator.pushNamed(context, '/standings');
      },
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color:
              kBlack2Color, // Using theme color instead of hardcoded Color(0xFF1A1A1C)
          borderRadius: BorderRadius.zero,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Rank number
            SizedBox(
              width: 24,
              child: Text(
                '$rank.',
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              ),
            ),

            // Country flag
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: getCountryFlag(countryCode),
            ),

            // GM prefix and player name
            Expanded(
              flex: 3,
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'GM ',
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                    TextSpan(
                      text: playerName,
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ELO rating - using Expanded to match header
            Expanded(
              flex: 1,
              child: Text(
                elo.toString(),
                textAlign: TextAlign.center,
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              ),
            ),

            // Age - using Expanded to match header
            Expanded(
              flex: 1,
              child: Text(
                age.toString(),
                textAlign: TextAlign.center,
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              ),
            ),

            // Favorite icon
            GestureDetector(
              onTap: onFavoriteToggle,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 30,
                child: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color:
                      isFavorite
                          ? Colors.red
                          : kWhiteColor, // Using theme color for unfilled state
                  size: 20,
                ),
              ),
            ),
          ],
        ),
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
          width: 20,
          height: 14,
          errorBuilder:
              (context, error, stackTrace) =>
                  Text('🇳🇴', style: TextStyle(fontSize: 16)),
        );
      case 'US':
        return Image.network(
          'https://flagcdn.com/w20/us.png',
          width: 20,
          height: 14,
          errorBuilder:
              (context, error, stackTrace) =>
                  Text('🇺🇸', style: TextStyle(fontSize: 16)),
        );
      case 'IN':
        return Image.network(
          'https://flagcdn.com/w20/in.png',
          width: 20,
          height: 14,
          errorBuilder:
              (context, error, stackTrace) =>
                  Text('🇮🇳', style: TextStyle(fontSize: 16)),
        );
      case 'UZ':
        return Image.network(
          'https://flagcdn.com/w20/uz.png',
          width: 20,
          height: 14,
          errorBuilder:
              (context, error, stackTrace) =>
                  Text('🇺🇿', style: TextStyle(fontSize: 16)),
        );
      default:
        return Text(
          countryCode,
          style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
        );
    }
  }
}
