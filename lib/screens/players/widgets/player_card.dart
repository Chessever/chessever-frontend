import 'package:flutter/material.dart';
import '../../../utils/app_typography.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/svg_asset.dart';
import '../../../widgets/svg_widget.dart';

class PlayerCard extends StatefulWidget {
  final int rank;
  final String playerId;
  final String playerName;
  final String countryCode;
  final int elo;
  final int age;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  const PlayerCard({
    Key? key,
    required this.rank,
    required this.playerId,
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

class _PlayerCardState extends State<PlayerCard>
    with SingleTickerProviderStateMixin {
  late bool _isFavorite;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.isFavorite;

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(PlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This ensures the _isFavorite state is always updated when widget.isFavorite changes
    if (oldWidget.isFavorite != widget.isFavorite) {
      setState(() {
        _isFavorite = widget.isFavorite;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleFavorite() {
    if (widget.onFavoriteToggle != null) {
      setState(() {
        _isFavorite = !_isFavorite;
      });

      // Animate heart icon
      if (_isFavorite) {
        _animationController.forward().then((_) {
          _animationController.reverse();
        });
      }

      widget.onFavoriteToggle!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Navigate to standings screen when the card is tapped
        // Navigator.pushNamed(context, '/standings');
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
                textAlign: TextAlign.start,
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

            // ELO rating with right alignment - using Expanded to match header position
            Expanded(
              flex: 1,
              child: Text(
                widget.elo.toString(),
                textAlign: TextAlign.center,
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              ),
            ),

            // Age - using Expanded to match header and center alignment
            Expanded(
              flex: 1,
              child: Text(
                widget.age.toString(),
                textAlign: TextAlign.center,
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              ),
            ),

            // Favorite icon with animated scale effect
            GestureDetector(
              onTap: _toggleFavorite,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 30,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: SvgWidget(
                    _isFavorite
                        ? SvgAsset.favouriteRedIcon
                        : SvgAsset.favouriteIcon2,
                    semanticsLabel: 'Favorite Icon',
                    height: 12,
                    width: 14,
                  ),
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
