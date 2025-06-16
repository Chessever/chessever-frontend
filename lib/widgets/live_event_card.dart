import 'package:flutter/material.dart';
import 'event_card.dart';

class LiveEventCard extends StatelessWidget {
  final String title;
  final String dates;
  final String location;
  final int playerCount;
  final int elo;
  final VoidCallback? onTap;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  const LiveEventCard({
    Key? key,
    required this.title,
    required this.dates,
    required this.location,
    required this.playerCount,
    required this.elo,
    this.onTap,
    this.isFavorite = false,
    this.onFavoriteToggle,
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
      isLive: true,
      isFavorite: isFavorite,
      onFavoritePressed: onFavoriteToggle,
      statusWidget: Container(), // Not used when isLive is true
    );
  }
}
