import 'package:flutter/material.dart';
import 'event_card.dart';
import '../../utils/app_typography.dart';

class CompletedEventCard extends StatelessWidget {
  final String title;
  final String dates;
  final String location;
  final int playerCount;
  final int elo;
  final VoidCallback? onTap;
  final VoidCallback? onDownloadTournament;
  final VoidCallback? onAddToLibrary;

  const CompletedEventCard({
    Key? key,
    required this.title,
    required this.dates,
    required this.location,
    required this.playerCount,
    required this.elo,
    this.onTap,
    this.onDownloadTournament,
    this.onAddToLibrary,
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
      statusWidget: Text(
        "Completed",
        style: AppTypography.textXsMedium.copyWith(color: Colors.grey),
      ),
      onMorePressed: () => _showMenu(context),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0C0C0E),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.download, color: Colors.white),
                  title: const Text(
                    'Download Tournament PGN',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onDownloadTournament?.call();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.library_add, color: Colors.white),
                  title: const Text(
                    'Add to Library',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onAddToLibrary?.call();
                  },
                ),
              ],
            ),
          ),
    );
  }
}
