import 'package:flutter/material.dart';
import '../utils/app_typography.dart';

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
    Key? key,
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
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF0C0C0E),
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // First row with title and icon
              Row(
                crossAxisAlignment: CrossAxisAlignment.start, // Align to top
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Title and status section
                  Expanded(
                    child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start, // Align to top
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: AppTypography.textXsBold.copyWith(
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isLive) _buildLiveTag() else statusWidget,
                      ],
                    ),
                  ),

                  // Star or three dots icon
                  isLive
                      ? InkWell(
                        onTap: onFavoritePressed,
                        child: Icon(
                          isFavorite ? Icons.star : Icons.star_border,
                          color: isFavorite ? Colors.amber : Colors.grey,
                          size: 24,
                        ),
                      )
                      : onMorePressed != null
                      ? InkWell(
                        onTap: onMorePressed,
                        child: const Icon(
                          Icons.more_vert,
                          color: Colors.grey,
                          size: 24,
                        ),
                      )
                      : Container(), // Empty container if no icon needed
                ],
              ),

              // Small vertical spacing
              const SizedBox(height: 4),

              // Second row with details
              DefaultTextStyle(
                style: AppTypography.textXsMedium.copyWith(color: Colors.grey),
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
      style: AppTypography.textXsBold.copyWith(color: Color(0xff0FB4E5)),
    );
  }
}
