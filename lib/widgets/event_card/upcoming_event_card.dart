import 'package:flutter/material.dart';
import '../../utils/app_typography.dart';
import 'event_card.dart';

class UpcomingEventCard extends StatelessWidget {
  final String title;
  final String dates;
  final String location;
  final int playerCount;
  final int elo;
  final String timeUntilStart;
  final VoidCallback? onTap;
  final bool isFavorite;
  final VoidCallback? onAddToFavorites;

  const UpcomingEventCard({
    Key? key,
    required this.title,
    required this.dates,
    required this.location,
    required this.playerCount,
    required this.elo,
    required this.timeUntilStart,
    this.onTap,
    this.isFavorite = false,
    this.onAddToFavorites,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return EventCard(
      title: title,
      dates: dates,
      location: location,
      playerCount: playerCount,
      elo: elo,
      onTap: onTap,
      isLive: false,
      isFavorite: isFavorite,
      onFavoritePressed: onAddToFavorites,
      statusWidget: Text(
        timeUntilStart,
        style: AppTypography.textXsMedium.copyWith(
          color: Colors.white.withOpacity(0.7),
        ),
      ),
    );
  }
}
