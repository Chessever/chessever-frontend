import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/utils/smart_event_mutation.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/star_notifications.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Stars or unstars [request]: the one path behind every smart event star.
///
/// A star is the smart event's favorites row (`smart_event:v2:<criteria>`),
/// independent of its My Space shortcut. Starring is subscribing: each evening, in their own
/// timezone, its owner hears how many new games it caught
/// (`queue_smart_event_digests`). Unstarring is the only opt-out, so starring
/// asks nothing; it only makes sure the push can arrive.
Future<void> toggleSmartEventFavorite({
  required BuildContext context,
  required SmartEventRequest request,
}) async {
  final allowed = await requireFullAuthGuard(context);
  if (!allowed || !context.mounted) return;

  // Resolved now: the card may be gone by the time the dialog closes.
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (container.read(smartEventMutationBusyProvider)) return;
  try {
    await withSmartEventMutation(container, () async {
      // Initial loading is not evidence that the event is unstarred.
      await container.read(favoriteEventsProvider.future);
      final notifier = container.read(favoriteEventsProvider.notifier);
      final saved = container.read(
        smartEventSavedFavoriteProvider(request.criteriaKey),
      );

      HapticFeedbackService.pin();

      void track(bool isFavorited) {
        AnalyticsService.instance.trackEventDetached(
          'Smart Event Favorite Toggled',
          properties: {
            'criteria_key': request.criteriaKey,
            'event_name': request.displayName,
            'is_favorited': isFavorited,
          },
        );
      }

      if (saved != null) {
        // Explicit unstar removes all legacy aliases of these exact criteria,
        // never another opening/pace with a similar display name.
        final matches = container
            .read(favoriteEventsProvider)
            .requireValue
            .where(
              (row) =>
                  isSmartFavoriteEvent(row) &&
                  SmartEventRequest.fromFavoriteEvent(row).criteriaKey ==
                      request.criteriaKey,
            )
            .toList();
        for (final row in matches) {
          await notifier.removeFavorite(row.eventId);
        }
        track(false);
        return;
      }

      await notifier.addFavorite(
        eventId: request.favoriteEventId,
        eventName: request.displayName,
        maxAvgElo: request.minElo > 0 ? request.minElo : null,
        extraMetadata: request.toFavoriteMetadata(),
      );
      track(true);
      await makeSmartEventStarReachable(
        container: container,
        messenger: messenger,
      );
    });
  } catch (_) {
    if (messenger != null && messenger.mounted) {
      showAppSnackOn(
        messenger,
        'Could not change the Smart Event subscription. Please retry.',
        tone: AppSnackTone.danger,
      );
    }
  }
}

/// A smart event's star, the event card's star in the same place: filled
/// gold while starred, an outline otherwise.
class SmartEventStar extends ConsumerWidget {
  const SmartEventStar({super.key, required this.request});

  final SmartEventRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(smartEventMutationBusyProvider);
    final starred =
        ref.watch(smartEventSavedFavoriteProvider(request.criteriaKey)) != null;
    return Semantics(
      button: true,
      label: starred
          ? 'Unstar ${request.displayName}'
          : 'Star ${request.displayName}',
      // Match the Prep player's centered target so both My Space cards
      // place their star at the same inset from the trailing edge.
      child: SizedBox.square(
        dimension: 44,
        child: InkResponse(
          radius: 22,
          onTap: busy
              ? null
              : () => toggleSmartEventFavorite(
                  context: context,
                  request: request,
                ),
          child: Center(
            child: ExcludeSemantics(
              child: SvgWidget(
                starred ? SvgAsset.starFilledIcon : SvgAsset.starIcon,
                semanticsLabel: 'Favorite Icon',
                height: 20.h,
                width: 20.w,
                preserveOriginalColors: starred,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
