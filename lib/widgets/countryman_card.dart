import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import '../utils/app_typography.dart';

class CountrymanCard extends StatelessWidget {
  final int rank;
  final String playerName;
  final String countryCode;
  final int elo;
  final int age;

  const CountrymanCard({
    Key? key,
    required this.rank,
    required this.playerName,
    required this.countryCode,
    required this.elo,
    required this.age,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1C),
        borderRadius: BorderRadius.zero,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Rank number
          SizedBox(
            width: 24,
            child: Text(
              '$rank.',
              style: AppTypography.textXsMedium.copyWith(color: Colors.white),
            ),
          ),

          // Country flag
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: getCountryFlag(countryCode),
          ),

          // GM prefix and player name
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'GM ',
                    style: AppTypography.textXsMedium.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  TextSpan(
                    text: playerName,
                    style: AppTypography.textXsMedium.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ELO rating - exactly matching the header width
          Container(
            width: 60,
            child: Text(
              elo.toString(),
              textAlign: TextAlign.center,
              style: AppTypography.textXsMedium.copyWith(color: Colors.white),
            ),
          ),

          // Age - exactly matching the header width
          Container(
            width: 50,
            child: Text(
              age.toString(),
              textAlign: TextAlign.center,
              style: AppTypography.textXsMedium.copyWith(color: Colors.white),
            ),
          ),
          // Container(
          //   width: 50,
          //   child: SvgPicture.asset(
          //     SvgAsset.favouriteIcon2
          //   ),
          // ),
        ],
      ),
    );
  }
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
        style: TextStyle(fontSize: 12, color: Colors.white),
      );
  }
}
