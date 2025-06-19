import 'package:flutter/material.dart';
import 'event_card.dart';

class LiveEventCard extends StatefulWidget {
  final String title;
  final String dates;
  final String location;
  final int playerCount;
  final int elo;
  final VoidCallback? onTap;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  const LiveEventCard({
    super.key,
    required this.title,
    required this.dates,
    required this.location,
    required this.playerCount,
    required this.elo,
    this.onTap,
    this.isFavorite = false,
    this.onFavoriteToggle,
  });

  @override
  State<LiveEventCard> createState() => _LiveEventCardState();
}

class _LiveEventCardState extends State<LiveEventCard> {
  var isFav = false;

  @override
  void initState() {
    isFav = widget.isFavorite;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return EventCard(
      title: widget.title,
      dates: widget.dates,
      location: widget.location,
      playerCount: widget.playerCount,
      elo: widget.elo,
      onTap: widget.onTap,
      isLive: true,
      isFavorite: isFav,
      onFavoritePressed: () {
        if (widget.onFavoriteToggle != null) {
          widget.onFavoriteToggle!();
        }
        setState(() {
          isFav = !isFav;
        });
      },
      statusWidget: Container(), // Not used when isLive is true
    );
  }
}
