import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PlayerProfileResolvedEventCard extends ConsumerWidget {
  const PlayerProfileResolvedEventCard({
    super.key,
    required this.request,
    required this.fallbackCard,
    required this.heroTagSuffix,
    required this.onTap,
    required this.statsRow,
    this.trailingWidget,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final PlayerProfileEventCardRequest request;
  final GroupEventCardModel fallbackCard;
  final String heroTagSuffix;
  final ValueChanged<GroupEventCardModel> onTap;
  final Widget statsRow;
  final Widget? trailingWidget;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvedCard = ref.watch(
      playerEventCardProvider(request).select((value) => value.valueOrNull),
    );
    final displayCard = resolvedCard ?? fallbackCard;

    return GestureDetector(
      onTap: () => onTap(displayCard),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          EventCard(
            key: ValueKey(displayCard.id),
            tourEventCardModel: displayCard,
            heroTagSuffix: heroTagSuffix,
            forceCompactLayout: true,
            trailingWidget: trailingWidget,
          ),
          statsRow,
        ],
      ),
    );
  }
}
