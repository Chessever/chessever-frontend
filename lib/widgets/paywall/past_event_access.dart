import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart'
    show liveBroadcastIdsProvider;
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The SQL view used by Events > Current is authoritative, even when local
/// dates look old. A failed lookup is unknown rather than proof of being past.
final currentEventMembershipProvider = FutureProvider.autoDispose
    .family<bool?, String>((ref, id) async {
      try {
        final current = await ref
            .read(groupBroadcastRepositoryProvider)
            .getCurrentGroupBroadcastsByIds([id]);
        return current.any((event) => event.id == id);
      } catch (_) {
        return null;
      }
    });

Future<bool?> _isCurrentEvent(ProviderContainer container, String id) async {
  if (isVirtualGamebaseId(id)) return false;
  final subscription = container.listen(
    currentEventMembershipProvider(id).future,
    (_, _) {},
  );
  try {
    return await subscription.read();
  } finally {
    subscription.close();
  }
}

/// Whether an event running from [start] to [end] has finished: its end has
/// passed by a day or, with no end, it started over a week ago. Current keeps
/// the final day playable, including rounds whose stored end is midnight.
/// An event with no dates at all is not called past.
bool isPastEventWindow({DateTime? start, DateTime? end, DateTime? now}) {
  final at = now ?? DateTime.now();
  if (end != null) {
    return !at.isBefore(end.add(const Duration(days: 1)));
  }
  return start != null && at.isAfter(start.add(const Duration(days: 7)));
}

/// [isPastEventWindow] for [broadcast], which is never past while one of
/// its rounds is live ([liveIds]).
bool isPastEvent(
  GroupBroadcast broadcast, {
  Iterable<String> liveIds = const <String>[],
  DateTime? now,
}) {
  if (liveIds.contains(broadcast.id)) return false;
  return isPastEventWindow(
    start: broadcast.dateStart,
    end: broadcast.dateEnd,
    now: now,
  );
}

Iterable<String> _liveEventIds(ProviderContainer container) {
  // Calendar, Countrymen and For You watch this stream directly, without
  // first visiting Events and filling its compatibility cache.
  if (container.exists(liveGroupBroadcastIdsProvider)) {
    final ids = container.read(liveGroupBroadcastIdsProvider).valueOrNull;
    // A resolved empty list also supersedes an old cache after a live event
    // ends. Only fall back while the authoritative snapshot is unavailable.
    if (ids != null) return ids;
  }
  return container.read(liveBroadcastIdsProvider);
}

/// Opening a past event is Premium: the Watch ad / Upgrade chooser every
/// Premium surface shows. [past] is the caller's own verdict, so a card from
/// the Past list asks even where its dates alone would not say so.
Future<bool> ensurePastEventAccess(
  BuildContext context, {
  required GroupBroadcast broadcast,
  bool past = false,
}) async {
  if (!context.mounted) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(premiumAccessProvider)) return true;
  if (_liveEventIds(container).contains(broadcast.id)) return true;
  if (!past) {
    var start = broadcast.dateStart;
    var end = broadcast.dateEnd;
    final virtualKey = virtualEventKeyFromId(broadcast.id);
    if ((start == null || end == null) && virtualKey != null) {
      final subscription = container.listen(
        gamebaseEventViewProvider(
          GamebaseEventViewRequest(
            eventName: virtualKey.eventName,
            site: virtualKey.site,
            slug: virtualKey.slug,
          ),
        ).future,
        (_, _) {},
      );
      try {
        final view = await subscription.read();
        start ??= view?.about.startDate;
        end ??= view?.about.endDate;
      } catch (_) {
        // Keep an undated event usable when its metadata is unavailable.
      } finally {
        subscription.close();
      }
      if (!context.mounted) return false;
    }
    if (!isPastEventWindow(start: start, end: end)) return true;
  }
  if (await _isCurrentEvent(container, broadcast.id) != false) return true;
  if (!context.mounted) return false;
  return ensurePremiumGameAccess(
    context,
    featureId: 'past_events',
    returnTo: 'events/past',
  );
}

/// Opening a game of the event on screen asks for Premium when that event
/// is past, however the viewer reached it (search, a favourite, a link).
/// A game from another event ([tourId] outside the open event's tours)
/// opens as it always did.
Future<bool> ensureEventGameAccess(
  BuildContext context, {
  String? tourId,
}) async {
  if (!context.mounted) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(premiumAccessProvider)) return true;
  final selected = container.read(selectedBroadcastModelProvider);
  if (selected == null) return true;
  if (_liveEventIds(container).contains(selected.id)) {
    return true;
  }
  final detail = container.exists(tourDetailScreenProvider)
      ? container.read(tourDetailScreenProvider).valueOrNull
      : null;
  final tours = detail?.tours ?? const [];
  if (tourId != null &&
      tours.isNotEmpty &&
      !tours.any((tour) => tour.tour.id == tourId)) {
    return true;
  }
  // Some routes (a favourite, a shortcut) open the event from a row with no
  // dates; the base-table row, when already fetched, then the event's own
  // tours still carry them.
  var start = selected.dateStart;
  var end = selected.dateEnd;
  if ((start == null || end == null) &&
      container.exists(canonicalSelectedBroadcastProvider)) {
    final canonical = container
        .read(canonicalSelectedBroadcastProvider)
        .valueOrNull;
    if (canonical?.id == selected.id) {
      start ??= canonical?.dateStart;
      end ??= canonical?.dateEnd;
    }
  }
  var past = isPastEventWindow(start: start, end: end);
  if (end == null) {
    final datedTours = tours.where((tour) => tour.tour.dates.isNotEmpty);
    if (datedTours.isNotEmpty) {
      // Every dated category must be finished. A later category with only a
      // start date still gets its own grace period; an explicit equal start
      // and end describes a single-day event rather than an unknown end.
      past = datedTours.every((tour) {
        final dates = tour.tour.dates;
        return isPastEventWindow(
          start: dates.first,
          end: dates.length > 1 ? dates.last : null,
        );
      });
    }
  }
  if (!past) return true;
  if (await _isCurrentEvent(container, selected.id) != false) return true;
  if (!context.mounted) return false;
  return ensurePremiumGameAccess(
    context,
    featureId: 'past_event_games',
    returnTo: 'events/past/games',
  );
}
