import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
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

/// Whether a starred [request] can send notifications. The dispatcher
/// matches a round to a smart event by its level and time controls; which
/// opening a game becomes is not known when its round starts, so an opening
/// smart event is starred without the question.
bool smartEventCanNotify(SmartEventRequest request) => request.eco.isAll;

/// The starred row of [request] when it can notify, for the focus menu's
/// notifications row (see [starNotificationsMenuAction]); null otherwise.
FavoriteEvent? smartEventNotifiableFavorite(
  WidgetRef ref,
  SmartEventRequest request,
) => smartEventCanNotify(request)
    ? ref.read(smartEventSavedFavoriteProvider(request.criteriaKey))
    : null;

/// Stars or unstars [request]: the one path behind every smart event star.
///
/// A star is the smart event's favorites row (`smart_event:v2:<criteria>`),
/// the row For You lists it from. Starring fills the star at once and then
/// asks whether it should also notify; the answer is written onto the row
/// once the row itself has landed.
Future<void> toggleSmartEventFavorite({
  required BuildContext context,
  required SmartEventRequest request,
}) async {
  final allowed = await requireFullAuthGuard(context);
  if (!allowed || !context.mounted) return;

  // Resolved now: the card may be gone by the time the dialog closes.
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
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
    try {
      // By the matched row's own id: a legacy row's differs from today's.
      await notifier.removeFavorite(saved.eventId);
      track(false);
    } catch (e) {
      debugPrint('[SmartEventStar] Error removing favorite: $e');
    }
    return;
  }

  final added = notifier
      .addFavorite(
        eventId: request.favoriteEventId,
        eventName: request.displayName,
        maxAvgElo: request.minElo > 0 ? request.minElo : null,
        extraMetadata: request.toFavoriteMetadata(),
      )
      .then(
        (_) => true,
        onError: (Object e) {
          debugPrint('[SmartEventStar] Error adding favorite: $e');
          return false;
        },
      );

  final wantsAlerts =
      smartEventCanNotify(request) &&
      await askStarNotifications(
        context,
        message:
            'Get round start and result alerts for every event in '
            '${request.displayName}.',
      );
  if (!await added) return;
  track(true);
  if (!wantsAlerts) return;
  await setStarNotifications(
    container: container,
    messenger: messenger,
    eventId: request.favoriteEventId,
    enabled: true,
    surface: 'smart_event',
  );
}

/// A smart event's star, the event card's star in the same place: filled
/// gold while starred, an outline otherwise.
class SmartEventStar extends ConsumerWidget {
  const SmartEventStar({super.key, required this.request});

  final SmartEventRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starred =
        ref.watch(smartEventSavedFavoriteProvider(request.criteriaKey)) != null;
    return Semantics(
      button: true,
      label: starred
          ? 'Unstar ${request.displayName}'
          : 'Star ${request.displayName}',
      child: InkWell(
        onTap: () =>
            toggleSmartEventFavorite(context: context, request: request),
        child: Padding(
          padding: EdgeInsets.fromLTRB(6.w, 6.h, 2.w, 6.h),
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
    );
  }
}
