import 'dart:async';

import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Premium outcome the Smart Events entry sells, from the spec.
const String kCreateSmartEventCta = 'Create a Smart Event';

/// Smart Events: the viewer's saved ones, or the GM and IM tier previews until
/// they have one. Previews open freely (the event view is the preview);
/// creating one is Premium, and sits in the header as the section's action.
/// Creating starts from the GM tier in the Smart Event view, where the
/// filters can be changed and the result saved.
class SmartEventsSection extends ConsumerWidget {
  const SmartEventsSection({super.key});

  void _open(BuildContext context, SmartEventRequest request) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SmartEventScreen(request: request),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscribed = ref.watch(
      subscriptionProvider.select((s) => s.isSubscribed),
    );
    // The tier previews need no account, so they hold the section's height
    // while the viewer's saved events load and are replaced in place.
    final shown =
        ref.watch(discoverySmartRequestsProvider).valueOrNull ??
        kDiscoverySmartPresets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DiscoverySectionHeader(
          title: 'Smart Events',
          trailing: DiscoveryAction(
            label: 'Create',
            lead: DiscoveryActionLead.plus,
            trailingPadlock: !subscribed,
            semanticsLabel: subscribed
                ? kCreateSmartEventCta
                : '$kCreateSmartEventCta, Premium',
            onTap: () => unlockThen(
              context,
              ref,
              () => _open(context, kDiscoverySmartPresets.first),
              featureId: 'smart_event_create',
              returnTo: discoveryReturnTo('smart_events'),
            ),
          ),
        ),
        SizedBox(height: 8.w),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) SizedBox(height: 10.w),
                _SmartEventTile(
                  key: ValueKey('smart_${shown[i].criteriaKey}'),
                  request: shown[i],
                  onTap: (resolved) => _open(context, resolved),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One Smart Event through the app's own card, with its membership resolved
/// from the current broadcasts so the counts are today's, not the save's.
class _SmartEventTile extends ConsumerWidget {
  const _SmartEventTile({
    super.key,
    required this.request,
    required this.onTap,
  });

  final SmartEventRequest request;
  final ValueChanged<SmartEventRequest> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = ref
        .watch(discoverySmartEventMembersProvider(request.criteria))
        .valueOrNull;
    final current = resolved == null ? request : request.withEvents(resolved);
    final events = current.events;
    final elos = [
      for (final e in events)
        if (e.maxAvgElo > 0) e.maxAvgElo,
    ];
    final avgElo = elos.isEmpty
        ? 0
        : (elos.reduce((a, b) => a + b) / elos.length).round();

    // The card's one-shot entrance starts it transparent; on a page that is
    // already on screen the card must simply be there.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: SmartEventCard(
        tierLabel: current.tierLabel,
        minElo: current.minElo,
        liveCount: events.length,
        avgElo: avgElo,
        titleSuffix: current.titleSuffix,
        caption: current.caption,
        countSingular: current.countSingular,
        countPlural: current.countPlural,
        accentColor: smartEventAccentColor(current.scopeId),
        spaceDraft: smartEventSpaceDraft(current),
        onTap: () => onTap(current),
      ),
    );
  }
}
