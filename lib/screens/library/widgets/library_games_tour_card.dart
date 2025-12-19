import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart'
    as tour;
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter/material.dart';

class LibraryGamesTourCard extends StatelessWidget {
  const LibraryGamesTourCard({
    super.key,
    required this.matchComparison,
    required this.eventName,
    required this.onTap,
    this.onLongPress,
    this.showClock = true,
  });

  final MatchWithComparison matchComparison;
  final String eventName;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showClock;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedbackService.cardTap();
        onTap();
      },
      onLongPress:
          onLongPress != null
              ? () {
                HapticFeedbackService.buttonPress();
                onLongPress!();
              }
              : null,
      child: SizedBox(
        width: double.infinity,
        child: tour.GamesTourGameCardBody(
          matchComparison: matchComparison,
          eventName: eventName,
          showClock: showClock,
        ),
      ),
    );
  }
}
