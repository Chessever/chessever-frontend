import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/utils/twic_event_identity.dart';
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
    this.gamebaseKey,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final PlayerProfileEventCardRequest request;
  final GroupEventCardModel fallbackCard;
  final String heroTagSuffix;
  final ValueChanged<GroupEventCardModel> onTap;
  final Widget statsRow;
  final Widget? trailingWidget;
  final String? gamebaseKey;
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
            // Fallbacks keep the shared long-press menu too, with a save
            // target that can reopen the event before a broadcast resolves.
            onTap: () => onTap(displayCard),
            spaceDraft: resolvedCard == null
                ? playerProfileFallbackEventSpaceDraft(
                    request: request,
                    card: fallbackCard,
                    gamebaseKey: gamebaseKey,
                  )
                : null,
          ),
          statsRow,
        ],
      ),
    );
  }
}

/// A profile fallback is a broadcast id or a database event, never a
/// calendar entry. Preserve the same archive identity as its tap handler.
SpaceShortcut playerProfileFallbackEventSpaceDraft({
  required PlayerProfileEventCardRequest request,
  required GroupEventCardModel card,
  String? gamebaseKey,
}) {
  String? nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  final isDatabaseEvent = request.dataSource == PlayerProfileDataSource.twic;
  final targetId = isDatabaseEvent
      ? virtualBroadcastId(
          request.tourName,
          site: request.site,
          slug:
              nonEmpty(gamebaseKey) ??
              nonEmpty(request.broadcastSlug) ??
              broadcastSlugFromSite(request.site),
        )
      : request.tourId;
  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.event,
    targetId: targetId,
    title: card.title,
    subtitle: card.dates.isEmpty ? null : card.dates,
    params: {
      'category': card.tourEventCategory.name,
      'eventSource': EventSource.lichessBroadcast.name,
      'timeControl': card.timeControl,
      'dates': card.dates,
      if (nonEmpty(card.location) case final location?) 'location': location,
      if (isDatabaseEvent) 'source': 'gamebase',
    },
  );
}
