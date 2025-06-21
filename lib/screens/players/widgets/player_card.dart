import 'package:flutter/material.dart';
import '../../../utils/app_typography.dart';
import '../../../theme/app_theme.dart';

class PlayerCard extends StatefulWidget {
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
  State<PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<PlayerCard> {
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.isFavorite;
  }

  @override
  void didUpdateWidget(PlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFavorite != widget.isFavorite) {
      _isFavorite = widget.isFavorite;
    }
  }

  void _toggleFavorite() {
    if (widget.onFavoriteToggle != null) {
      setState(() {
        _isFavorite = !_isFavorite;
      });
      widget.onFavoriteToggle!();
    }
  }

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
          color: kBlack2Color,
          borderRadius: BorderRadius.zero,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Rank number
            SizedBox(
              width: 24,
              child: Text(
                '${widget.rank}.',
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              ),
            ),

            // Country flag
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: getCountryFlag(widget.countryCode),
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
                      text: widget.playerName,
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
                widget.elo.toString(),
                textAlign: TextAlign.center,
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              ),
            ),

            // Age - using Expanded to match header
            Expanded(
              flex: 1,
              child: Text(
                widget.age.toString(),
                textAlign: TextAlign.center,
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              ),
            ),

            // Favorite icon
            GestureDetector(
              onTap: _toggleFavorite,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 30,
                child: Icon(
                  _isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: _isFavorite ? kRedColor : kWhiteColor,
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
