import 'package:chessever2/utils/responsive_helper.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import '../../../utils/app_typography.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/svg_asset.dart';
import '../../../widgets/svg_widget.dart';

class PlayerCard extends StatefulWidget {
  const PlayerCard({
    super.key,
    required this.rank,
    required this.playerId,
    required this.playerName,
    required this.countryCode,
    required this.elo,
    required this.age,
    this.isFavorite = false,
    this.onFavoriteToggle,
  });

  final int rank;
  final String playerId;
  final String playerName;
  final String countryCode;
  final int elo;
  final int age;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

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
        height: 48.h,
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.zero,
        ),
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 14.sp),
        child: Row(
          children: [
            // Rank number
            SizedBox(
              width: 24.w,
              child: Text(
                '${widget.rank}.',
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              ),
            ),

            // Country flag
            Container(
              margin: EdgeInsets.only(right: 8.sp),
              child: CountryFlag.fromCountryCode(
                widget.countryCode,
                height: 14.h,
                width: 20.w,
              ),
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
                width: 30.w,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: SvgWidget(
                    _isFavorite
                        ? SvgAsset.favouriteRedIcon
                        : SvgAsset.favouriteIcon2,
                    semanticsLabel: 'Favorite Icon',
                    height: 12.h,
                    width: 14.w,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
   
    );
  }
}
