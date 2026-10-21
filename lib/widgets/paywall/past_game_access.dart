import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/paywall/past_event_access.dart';
import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A free board opened from a mixed history list stays within the admitted
/// event. Past rows remain in the source Games tab, where tapping them asks
/// for access. Personal analyses and entitled navigation keep their full list.
({List<GamesTourModel> games, int index}) gameNavigationForAccess({
  required List<GamesTourModel> games,
  required int index,
  required bool premium,
  Iterable<String> eventTourIds = const [],
  bool publishedEventGame = false,
}) {
  if (games.isEmpty) return (games: games, index: 0);
  final safeIndex = index.clamp(0, games.length - 1);
  final selected = games[safeIndex];
  if (premium ||
      (selected.source != GameSource.supabase &&
          selected.source != GameSource.gamebase &&
          selected.source != GameSource.twic &&
          !publishedEventGame)) {
    return (games: games, index: safeIndex);
  }
  // A Gamebase display name may cover several editions of an event. Only
  // virtual ids are unambiguous enough to share a free navigation scope.
  if (selected.source != GameSource.supabase &&
      !isVirtualGamebaseId(selected.tourId)) {
    return (games: [selected], index: 0);
  }
  final allowedTours = {...eventTourIds, selected.tourId};
  final allowed = games
      .where(
        (game) =>
            game.source == selected.source &&
            allowedTours.contains(game.tourId),
      )
      .toList(growable: false);
  return (
    games: allowed,
    index: allowed.indexWhere((game) => game.gameId == selected.gameId),
  );
}

/// Games tabs can mix events without opening a tournament first. Resolve the
/// tapped game's own event so a stale selected event cannot decide its access.
/// Current SQL membership wins over old dates; paid/rewarded viewers skip all
/// lookups. Personal analyses keep their existing access rules.
Future<bool> ensurePastGameAccess(
  BuildContext context, {
  required GamesTourModel game,
  bool publishedEventGame = false,
}) async {
  if (!context.mounted) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(premiumAccessProvider)) return true;
  if (game.source != GameSource.supabase &&
      game.source != GameSource.gamebase &&
      game.source != GameSource.twic &&
      !publishedEventGame) {
    return true;
  }

  final selected = container.read(selectedBroadcastModelProvider);
  final detail = container.exists(tourDetailScreenProvider)
      ? container.read(tourDetailScreenProvider).valueOrNull
      : null;
  if (selected != null &&
      detail != null &&
      detail.tours.any((tour) => tour.tour.id == game.tourId)) {
    if (selected.dateStart == null &&
        selected.dateEnd == null &&
        detail.tours.every((tour) => tour.tour.dates.isEmpty) &&
        isPastEventWindow(
          end: game.gameDay ?? game.dateStart ?? game.lastMoveTime,
        )) {
      return ensurePastEventAccess(context, broadcast: selected, past: true);
    }
    return ensureEventGameAccess(context, tourId: game.tourId);
  }

  final virtualKey = virtualEventKeyFromId(game.tourId);
  if (virtualKey != null) {
    return ensurePastEventAccess(
      context,
      broadcast: virtualGroupBroadcastForEvent(
        virtualKey.eventName,
        site: virtualKey.site,
        slug: virtualKey.slug,
      ),
    );
  }

  GroupBroadcast? broadcast;
  var resolvedByName = false;
  final repository = container.read(groupBroadcastRepositoryProvider);
  try {
    broadcast = await repository.getGroupBroadcastById(game.tourId);
  } catch (_) {
    if (game.source == GameSource.supabase) {
      // A failed metadata lookup cannot prove that a Current game is past.
      return context.mounted;
    }
  }
  if (!context.mounted) return false;
  if (broadcast == null) {
    for (final slug in <String>{
      if (game.tourSlug?.isNotEmpty == true) game.tourSlug!,
      game.tourId,
    }) {
      try {
        broadcast = await repository.getGroupBroadcastBySlug(slug);
        resolvedByName = slug == game.tourId;
      } catch (_) {
        // Database events may have no corresponding broadcast.
      }
      if (!context.mounted) return false;
      if (broadcast != null) break;
    }
  }
  if (broadcast != null) {
    final date = game.gameDay ?? game.dateStart ?? game.lastMoveTime;
    // A display name can be reused every week/year. It does not prove that
    // an old database game belongs to today's same-named Current broadcast.
    final start = broadcast.dateStart;
    final end = broadcast.dateEnd;
    final matchesEdition =
        !resolvedByName ||
        (date != null &&
            (start == null || !date.isBefore(start)) &&
            (end == null || date.isBefore(end.add(const Duration(days: 1)))));
    if (matchesEdition) {
      return ensurePastEventAccess(
        context,
        broadcast: broadcast,
        past:
            broadcast.dateStart == null &&
            broadcast.dateEnd == null &&
            isPastEventWindow(end: date),
      );
    }
  }
  if (publishedEventGame &&
      !isPastEventWindow(end: game.gameDay ?? game.dateStart)) {
    return true;
  }
  // A database archive game with no broadcast retains its existing gate.
  return ensurePremiumGameAccess(
    context,
    featureId: 'past_event_games',
    returnTo: 'events/past/games',
  );
}
