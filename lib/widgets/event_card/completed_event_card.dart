import 'package:chessever2/theme/app_theme.dart';
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
    super.key,
    required this.title,
    required this.dates,
    required this.location,
    required this.playerCount,
    required this.elo,
    this.onTap,
    this.onDownloadTournament,
    this.onAddToLibrary,
  });

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
            decoration: BoxDecoration(
              color: kBackgroundColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.download, color: kWhiteColor),
                  title: const Text(
                    'Download Tournament PGN',
                    style: TextStyle(color: kWhiteColor),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onDownloadTournament?.call();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.library_add, color: kWhiteColor),
                  title: const Text(
                    'Add to Library',
                    style: TextStyle(color: kWhiteColor),
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
