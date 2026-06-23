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
          _ResolvedEventCardFade(
            fallbackCard: fallbackCard,
            resolvedCard: resolvedCard,
            heroTagSuffix: heroTagSuffix,
            trailingWidget: trailingWidget,
          ),
          statsRow,
        ],
      ),
    );
  }
}

class _ResolvedEventCardFade extends StatelessWidget {
  const _ResolvedEventCardFade({
    required this.fallbackCard,
    required this.resolvedCard,
    required this.heroTagSuffix,
    required this.trailingWidget,
  });

  final GroupEventCardModel fallbackCard;
  final GroupEventCardModel? resolvedCard;
  final String heroTagSuffix;
  final Widget? trailingWidget;

  @override
  Widget build(BuildContext context) {
    final resolved = resolvedCard;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        EventCard(
          key: ValueKey('fallback_${fallbackCard.id}'),
          tourEventCardModel: fallbackCard,
          heroTagSuffix: heroTagSuffix,
          forceCompactLayout: true,
          trailingWidget: trailingWidget,
        ),
        if (resolved != null)
          Positioned.fill(
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                key: ValueKey('resolved_${resolved.id}'),
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, opacity, child) {
                  return Opacity(opacity: opacity, child: child);
                },
                child: EventCard(
                  tourEventCardModel: resolved,
                  heroTagSuffix: heroTagSuffix,
                  forceCompactLayout: true,
                  trailingWidget: trailingWidget,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
