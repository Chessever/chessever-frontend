import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import '../../utils/app_typography.dart';

class EventCard extends StatelessWidget {
  final String title;
  final String dates;
  final String location;
  final int playerCount;
  final int elo;
  final Widget statusWidget;
  final VoidCallback? onTap;
  final bool isLive;
  final bool isFavorite;
  final VoidCallback? onFavoritePressed;
  final VoidCallback? onMorePressed;

  const EventCard({
    super.key,
    required this.title,
    required this.dates,
    required this.location,
    required this.playerCount,
    required this.elo,
    required this.statusWidget,
    this.onTap,
    this.isLive = false,
    this.isFavorite = false,
    this.onFavoritePressed,
    this.onMorePressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // height: 56, // Fixed height for the card
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(8),
            topLeft: Radius.circular(8),
          ),
        ),
        padding: const EdgeInsets.only(top: 6, bottom: 6, left: 8, right: 8),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment
                  .center, // Center vertically in the entire container
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: AppTypography.textXsBold.copyWith(
                            color: kWhiteColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (isLive) _buildLiveTag() else statusWidget,
                    ],
                  ),

                  // Small vertical spacing
                  const SizedBox(height: 2),

                  // Second row with details
                  DefaultTextStyle(
                    style: AppTypography.textXsMedium.copyWith(
                      color: Colors.grey,
                    ),
                    child: Row(
                      children: [
                        Flexible(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(dates),
                              _buildDot(),
                              Text(location),
                              _buildDot(),
                              Text("$playerCount players"),
                              _buildDot(),
                              Text("ELO $elo"),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Star or three dots icon - now aligned to the center of the entire card
            const SizedBox(width: 16),
            // Show three dots for completed events, star for live/upcoming events
            if (statusWidget is Text &&
                (statusWidget as Text).data == "Completed")
              InkWell(
                onTap: onMorePressed,
                child: SvgWidget(
                  SvgAsset.threeDots,
                  semanticsLabel: 'More Options',
                  height: 24,
                  width: 24,
                ),
              )
            else
              InkWell(
                onTap: onFavoritePressed,
                child: SvgWidget(
                  SvgAsset.starIcon,
                  semanticsLabel: 'Favorite Icon',
                  height: 20,
                  width: 20,
                  colorFilter: ColorFilter.mode(
                    isFavorite ? kPrimaryColor : kDarkGreyColor,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            // Empty container if no icon needed
          ],
        ),
      ),
    );
  }

  Widget _buildDot() {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildLiveTag() {
    return Text(
      'LIVE',
      style: AppTypography.textXsBold.copyWith(
        color: kPrimaryColor,
        fontFamily: 'InterDisplay',
      ),
    );
  }
}
