import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/utils/favorite_event_ids.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/pgn_link_rebrand.dart';
import 'package:chessever2/utils/pgn_export_utils.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Actions available from the event card long-press context menu.
enum EventContextAction { noSpoilers, share, copyPgn, mySpace }

String eventNoSpoilersMenuLabel(bool enabled) =>
    enabled ? 'Turn off No Spoilers' : 'Turn on No Spoilers';

/// A mixed grouped event is treated as not fully protected: one action turns
/// No Spoilers on for every child tour. Only an all-on event toggles off.
bool eventNoSpoilersNextEnabled(Iterable<EventNoSpoilersState> states) {
  final values = states.toList(growable: false);
  return values.isEmpty || !values.every((state) => state.enabled);
}

/// URL query parameter that selects a sub-tab of the broadcast/event page.
/// The web frontend and the in-app deep link handler both read `?tab=<value>`
/// (the traditional "tab in URL" convention) so an event link and a standings
/// link are the SAME URL plus a tab marker. Keep these in sync with
/// `DeepLinkService` and the web broadcast route.
const String kEventTabQueryParam = 'tab';
const String kEventStandingsTab = 'standings';
const String kEventBracketTab = 'bracket';

/// Builds the canonical shareable URL for an event, mirroring
/// `lichess.org/broadcast/<tour.slug>/<tour.id>` on chessever.com.
///
/// Pass [tourSlug] and [tourId] when known (Lichess short id like `QXavbhIZ`
/// + kebab slug) to produce a link that swaps `lichess.org` ↔ `chessever.com`
/// without any other change. The fallback path uses the group_broadcast id
/// and a slugified title — always works, but the path tail isn't a Lichess
/// short id.
///
/// Pass [tab] (e.g. [kEventStandingsTab] or [kEventBracketTab]) to deep-link a
/// specific tab of the
/// event page; it is appended as `?tab=<tab>` so the same link opens the
/// requested tab in-app and on the web.
///
/// Pass [playerFideId] to link a specific player's scorecard within the event
/// (`/broadcast/<slug>/<id>/player/<fideId>`): the same link opens the event and
/// then that player's scorecard in-app, and renders the player card on the web.
///
/// Pass [teamName] to link a team scorecard within the event
/// (`/broadcast/<slug>/<id>/team/<encodedTeamName>`). Precedence:
/// player → team → tab → plain event.
String buildEventShareUrl({
  required String id,
  required String title,
  String? tourId,
  String? tourSlug,
  String? tab,
  int? playerFideId,
  String? teamName,
}) {
  final String base;
  if (tourId != null &&
      tourId.isNotEmpty &&
      tourSlug != null &&
      tourSlug.isNotEmpty) {
    base = 'https://chessever.com/broadcast/$tourSlug/$tourId';
  } else {
    final slug = _slugify(title);
    base = 'https://chessever.com/broadcast/$slug/$id';
  }
  if (playerFideId != null) {
    return '$base/player/$playerFideId';
  }
  final trimmedTeam = teamName?.trim();
  if (trimmedTeam != null && trimmedTeam.isNotEmpty) {
    return '$base/team/${Uri.encodeComponent(trimmedTeam)}';
  }
  if (tab != null && tab.isNotEmpty) {
    return '$base?$kEventTabQueryParam=$tab';
  }
  return base;
}

String _slugify(String input) {
  final lower = input.toLowerCase();
  final dashed = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final trimmed = dashed.replaceAll(RegExp(r'^-+|-+$'), '');
  return trimmed.isEmpty ? 'event' : trimmed;
}

/// The My Space shortcut for an event card. Community (calendar / FIDE major)
/// events carry `source: calendar` plus their calendar identity so the opener
/// can route them to the calendar event detail instead of the broadcast
/// screen. The target id never changes, so pins saved before these params
/// existed keep deduping with new ones.
SpaceShortcut eventSpaceDraft(GroupEventCardModel model) {
  final location = model.location?.trim() ?? '';
  final dates = model.dates.trim();
  final isCalendarEvent = model.eventSource == EventSource.communityEvent;
  return SpaceShortcut.draft(
    kind: SpaceShortcutKind.event,
    targetId: model.id,
    title: model.title,
    subtitle: dates.isEmpty ? null : dates,
    params: {
      'category': model.tourEventCategory.name,
      'eventSource': model.eventSource.name,
      'timeControl': model.timeControl,
      'dates': model.dates,
      if (location.isNotEmpty) 'location': location,
      if (isCalendarEvent) ...{
        'source': 'calendar',
        'calendarEventId': model.id,
        // calendar_events is keyed by name; the sanitized id cannot be turned
        // back into it, so the opener looks the row up by this.
        'calendarEventName': model.title,
      },
    },
  );
}

/// Whether [model] is one of the user's favorite (starred) events. Same
/// matching the card's star uses: stored id (incl. remapped `cal_event_*`
/// ids) or, failing that, the event name.
bool eventIsFavorited(
  Iterable<FavoriteEvent> favorites,
  GroupEventCardModel model,
) {
  final title = model.title.trim().toLowerCase();
  return favorites.any(
    (e) =>
        favoriteEventMatchesId(
          storedEventId: e.eventId,
          candidateId: model.id,
          eventName: e.eventName,
          metadata: e.metadata,
        ) ||
        e.eventName.trim().toLowerCase() == title,
  );
}

/// Stars or unstars [model]: the one path behind every event star, so each
/// writes the same row and the same analytics event.
Future<void> toggleEventFavorite({
  required BuildContext context,
  required WidgetRef ref,
  required GroupEventCardModel model,
}) async {
  final allowed = await requireFullAuthGuard(context);
  if (!allowed) return;

  HapticFeedbackService.pin();

  final favoritesCount =
      ref.read(favoriteEventsProvider).valueOrNull?.length ?? 0;
  try {
    final isFavorited = await ref
        .read(favoriteEventsProvider.notifier)
        .toggleFavorite(
          eventId: model.id,
          eventName: model.title,
          timeControl: model.timeControl,
          maxAvgElo: model.maxAvgElo > 0 ? model.maxAvgElo : null,
          dates: model.dates.isNotEmpty ? model.dates : null,
        );
    // Same path for Current / For You / Calendar cards — remaps synthetic
    // cal_event_* ids to group_broadcasts.id when possible.
    final nextCount =
        isFavorited
            ? favoritesCount + 1
            : (favoritesCount - 1).clamp(0, favoritesCount);
    AnalyticsService.instance.trackEventDetached(
      'Event Favorite Toggled',
      properties: {
        'event_id': model.id,
        'event_name': model.title,
        'time_control': model.timeControl,
        'event_source': model.eventSource.name,
        'tour_category': model.tourEventCategory.name,
        'is_favorited': isFavorited,
        'new_favorites_total': nextCount,
        if (model.location != null && model.location!.isNotEmpty)
          'location': model.location,
        if (model.maxAvgElo > 0) 'max_avg_elo': model.maxAvgElo,
      },
    );
  } catch (e) {
    debugPrint('[EventCard] Error toggling favorite: $e');
    // Silently handle error - state will be corrected on next refresh.
  }
}

/// Resolves the tours behind [model] and loads each one's No Spoilers state,
/// so the menu can label that row before it opens. Community events have no
/// tours. Never throws: a failed lookup, or a host disposed while it was in
/// flight (its `ref` is dead by then), answers an empty list.
Future<List<String>> loadEventMenuTourIds(
  WidgetRef ref,
  GroupEventCardModel model,
) async {
  if (!hasBroadcastActions(model)) return const <String>[];
  try {
    final tourIds = await _eventTourIds(ref, model);
    await _eventNoSpoilersStates(ref, tourIds);
    return tourIds;
  } catch (_) {
    return const <String>[];
  }
}

/// How long a chosen No Spoilers row waits for tours that were still loading
/// when the menu opened. The lookup was already under way behind the menu.
const Duration _kNoSpoilersResolveCap = Duration(seconds: 5);

/// The rows of an event's focus menu, in one order everywhere an event card
/// can be long-pressed: Open, No Spoilers, Share, Copy PGN, My Space. The
/// card's own star is where an event is favorited.
///
/// [tourIds] comes from [loadEventMenuTourIds]. Once they are known the No
/// Spoilers row reads the live per-tour state, so it is never stale after a
/// toggle. While they are still loading, pass the lookup as
/// [pendingTourIds]: the menu opens at once with the row in its default
/// "Turn on" form, and the row settles the tours when chosen (see
/// [_turnOnNoSpoilersOnceResolved]). With neither, the row is left out.
/// Community (calendar) events only get Open and My Space: they have no
/// broadcast to act on.
List<LibraryMenuAction> eventMenuActions({
  required BuildContext context,
  required WidgetRef ref,
  required GroupEventCardModel model,
  List<String> tourIds = const <String>[],
  Future<List<String>>? pendingTourIds,
  VoidCallback? onOpen,
}) {
  final broadcastActions = hasBroadcastActions(model);
  final spoilerStates = [
    for (final tourId in tourIds) ref.read(eventNoSpoilersProvider(tourId)),
  ];
  final noSpoilersEnabled =
      spoilerStates.isNotEmpty && spoilerStates.every((state) => state.enabled);

  return [
    if (onOpen != null)
      LibraryMenuAction(
        icon: Icons.open_in_new_rounded,
        label: 'Open event',
        onSelected: onOpen,
      ),
    if (broadcastActions && tourIds.isNotEmpty)
      LibraryMenuAction(
        icon:
            noSpoilersEnabled
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
        label: eventNoSpoilersMenuLabel(noSpoilersEnabled),
        onSelected: () async {
          final enabled = eventNoSpoilersNextEnabled(spoilerStates);
          await Future.wait(
            tourIds.map(
              (tourId) => ref
                  .read(eventNoSpoilersProvider(tourId).notifier)
                  .setEnabled(enabled),
            ),
          );
          HapticFeedbackService.success();
        },
      )
    else if (broadcastActions && pendingTourIds != null)
      _pendingNoSpoilersAction(context, pendingTourIds),
    if (broadcastActions) ...[
      LibraryMenuAction(
        icon: Icons.ios_share_rounded,
        label: 'Share',
        onSelected: () => _shareEvent(context: context, ref: ref, model: model),
      ),
      LibraryMenuAction(
        icon: Icons.copy_rounded,
        label: 'Copy PGN',
        onSelected:
            () => _copyEventPgn(context: context, ref: ref, model: model),
      ),
    ],
    spaceMenuAction(context: context, ref: ref, draft: eventSpaceDraft(model)),
  ];
}

/// Show the event long-press context menu and run the selected action.
///
/// The shared focus menu ([showLibraryContextMenu]) anchored to [context]'s
/// card; [globalPosition] only decides which edge of a wide card the menu
/// hangs from. Community (calendar) events only get their non-broadcast rows
/// (see [hasBroadcastActions]).
Future<void> showEventContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required GroupEventCardModel model,
  required Offset globalPosition,
  VoidCallback? onOpen,
}) async {
  // The menu (and its haptic) answers the press at once; the tours load
  // behind it and the No Spoilers row settles them if it is chosen.
  final pendingTourIds =
      hasBroadcastActions(model) ? loadEventMenuTourIds(ref, model) : null;
  await showLibraryContextMenu(
    context: context,
    actions: eventMenuActions(
      context: context,
      ref: ref,
      model: model,
      pendingTourIds: pendingTourIds,
      onOpen: onOpen,
    ),
    // A screen reader's long-press action reports no position.
    origin: globalPosition == Offset.zero ? null : globalPosition,
  );
}

/// Community events are calendar-only and not backed by a GroupBroadcast, so
/// No Spoilers / Share / Copy PGN have nothing to act on. They still get the
/// My Space row.
bool hasBroadcastActions(GroupEventCardModel model) {
  return model.eventSource != EventSource.communityEvent;
}

Future<List<String>> _eventTourIds(
  WidgetRef ref,
  GroupEventCardModel model,
) async {
  try {
    final ids = await ref
        .read(groupBroadcastRepositoryProvider)
        .getTourIdsForGroupBroadcast(model.id);
    return ids.where((id) => id.isNotEmpty).toSet().toList(growable: false);
  } catch (_) {
    return const <String>[];
  }
}

Future<List<EventNoSpoilersState>> _eventNoSpoilersStates(
  WidgetRef ref,
  List<String> tourIds,
) async {
  await Future.wait(
    tourIds.map(
      (tourId) => ref.read(eventNoSpoilersProvider(tourId).notifier).load(),
    ),
  );
  return [
    for (final tourId in tourIds) ref.read(eventNoSpoilersProvider(tourId)),
  ];
}

/// The No Spoilers row of a menu that opened before the event's tours were
/// known. It reads "Turn on", the state of any event never touched, and the
/// provider scope and messenger are captured now, while the card is mounted,
/// because the row only runs after the menu has closed.
LibraryMenuAction _pendingNoSpoilersAction(
  BuildContext context,
  Future<List<String>> pendingTourIds,
) {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  return LibraryMenuAction(
    icon: Icons.visibility_outlined,
    label: eventNoSpoilersMenuLabel(false),
    onSelected:
        () => _turnOnNoSpoilersOnceResolved(
          container: container,
          messenger: messenger,
          pendingTourIds: pendingTourIds,
        ),
  );
}

/// Does what the pending row promised once the tours land: turns No Spoilers
/// on for every tour. When they turn out to be on already it says so rather
/// than flipping them off behind a "Turn on" label; the next open reads the
/// real state.
Future<void> _turnOnNoSpoilersOnceResolved({
  required ProviderContainer container,
  required ScaffoldMessengerState? messenger,
  required Future<List<String>> pendingTourIds,
}) async {
  void tell(String message, {AppSnackTone tone = AppSnackTone.neutral}) {
    if (messenger != null && messenger.mounted) {
      showAppSnackOn(messenger, message, tone: tone);
    }
  }

  try {
    final tourIds = await pendingTourIds.timeout(
      _kNoSpoilersResolveCap,
      onTimeout: () => const <String>[],
    );
    if (tourIds.isEmpty) {
      tell("Couldn't turn on No Spoilers", tone: AppSnackTone.danger);
      return;
    }
    final notifiers = [
      for (final tourId in tourIds)
        container.read(eventNoSpoilersProvider(tourId).notifier),
    ];
    await Future.wait(notifiers.map((notifier) => notifier.load()));
    final states = [
      for (final tourId in tourIds)
        container.read(eventNoSpoilersProvider(tourId)),
    ];
    if (!eventNoSpoilersNextEnabled(states)) {
      tell('No Spoilers is already on');
      return;
    }
    await Future.wait(notifiers.map((notifier) => notifier.setEnabled(true)));
    HapticFeedbackService.success();
  } catch (_) {
    tell("Couldn't turn on No Spoilers", tone: AppSnackTone.danger);
  }
}

Future<void> _shareEvent({
  required BuildContext context,
  required WidgetRef ref,
  required GroupEventCardModel model,
}) async {
  // Resolve the primary tour so the share link mirrors the Lichess shape
  // `<tour.slug>/<tour.id>`. This keeps the path tail an 8-char Lichess
  // short id (e.g. `QXavbhIZ`) instead of repeating the slug. Fall back to
  // the group_broadcast id if the lookup fails, so sharing never blocks.
  ({String id, String slug})? tour;
  try {
    tour = await ref
        .read(groupBroadcastRepositoryProvider)
        .getPrimaryTourSlugAndId(model.id);
  } catch (_) {
    tour = null;
  }

  final url = buildEventShareUrl(
    id: model.id,
    title: model.title,
    tourId: tour?.id,
    tourSlug: tour?.slug,
  );
  if (!context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  final origin =
      box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 1, 1);

  AnalyticsService.instance.trackEventDetached(
    'Event Shared',
    properties: {'event_id': model.id, 'event_name': model.title},
  );

  await Share.share(url, sharePositionOrigin: origin);
}

Future<void> _copyEventPgn({
  required BuildContext context,
  required WidgetRef ref,
  required GroupEventCardModel model,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  try {
    final tourIds = await ref
        .read(groupBroadcastRepositoryProvider)
        .getTourIdsForGroupBroadcast(model.id);

    if (tourIds.isEmpty) {
      showAppSnackOn(messenger, 'No games to copy');
      return;
    }

    final gameRepo = ref.read(gameRepositoryProvider);
    final pgnBuffer = StringBuffer();
    const pageSize = 500;
    var offset = 0;
    var copied = 0;

    while (true) {
      final games = await gameRepo.getGamesFromTourIds(
        tourIds: tourIds,
        limit: pageSize,
        offset: offset,
      );
      if (games.isEmpty) break;

      for (final g in games) {
        final pgn = g.pgn;
        if (pgn == null || pgn.trim().isEmpty) continue;
        if (copied > 0) pgnBuffer.write('\n\n');
        pgnBuffer.write(
          canonicalizePgnForExport(rebrandPgnLinks(pgn.trim())),
        );
        copied++;
      }

      if (games.length < pageSize) break;
      offset += pageSize;
    }

    if (copied == 0) {
      showAppSnackOn(messenger, 'No games to copy');
      return;
    }

    await Clipboard.setData(ClipboardData(text: pgnBuffer.toString()));
    HapticFeedbackService.success();

    AnalyticsService.instance.trackEventDetached(
      'Event PGN Copied',
      properties: {
        'event_id': model.id,
        'event_name': model.title,
        'game_count': copied,
      },
    );

    showAppSnackOn(
      messenger,
      copied == 1 ? 'PGN copied' : '$copied PGNs copied',
    );
  } catch (_) {
    showAppSnackOn(
      messenger,
      'Failed to copy PGN',
      tone: AppSnackTone.danger,
    );
  }
}

/// Helper used by long-press handlers that want the standard menu flow. The
/// shared menu raises the context-menu haptic itself when it opens.
Future<void> onEventCardLongPress({
  required BuildContext context,
  required WidgetRef ref,
  required GroupEventCardModel model,
  required Offset globalPosition,
}) async {
  await showEventContextMenu(
    context: context,
    ref: ref,
    model: model,
    globalPosition: globalPosition,
  );
}
