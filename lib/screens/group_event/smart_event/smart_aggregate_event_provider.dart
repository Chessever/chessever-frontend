import 'package:chessever2/providers/for_you_games_logic.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum SmartEventSource { forYou, current }

bool isSmartFavoriteEvent(FavoriteEvent favorite) {
  return favorite.metadata['type'] == 'smart_event' ||
      favorite.eventId.startsWith('smart_event:');
}

bool smartEventHasUnfinishedEvents(
  SmartEventRequest request,
  List<String> liveIds,
) {
  return request.events.any((event) {
    return event.withLiveIds(liveIds).tourEventCategory !=
        TourEventCategory.completed;
  });
}

bool smartEventHasCurrentEvents(
  SmartEventRequest request,
  Set<String> currentEventIds,
) {
  if (request.events.isEmpty || currentEventIds.isEmpty) return false;
  return request.events.any((event) => currentEventIds.contains(event.id));
}

@immutable
class SmartEventRequest {
  SmartEventRequest({
    required this.source,
    required this.tierLabel,
    required this.titleSuffix,
    required this.minElo,
    required this.maxElo,
    required this.caption,
    required this.countSingular,
    required this.countPlural,
    required List<GroupEventCardModel> events,
    this.savedAt,
  }) : events = List<GroupEventCardModel>.unmodifiable(events);

  final SmartEventSource source;
  final String tierLabel;
  final String titleSuffix;
  final int minElo;
  final int maxElo;
  final String caption;
  final String countSingular;
  final String countPlural;
  final List<GroupEventCardModel> events;
  final DateTime? savedAt;

  List<String> get eventIds =>
      events.map((event) => event.id).toList(growable: false);

  List<String> get stableEventIds {
    final ids = eventIds.toList(growable: false)..sort();
    return ids;
  }

  bool get hasEloRange => minElo > kFilterMinElo || maxElo < kFilterMaxElo;

  String get scopeId =>
      '${source.name}:$minElo-$maxElo:${stableEventIds.join('|')}';

  String get favoriteEventId => 'smart_event:$scopeId';

  String get displayName => '$tierLabel $titleSuffix'.trim();

  Map<String, dynamic> toFavoriteMetadata() {
    return {
      'type': 'smart_event',
      'source': source.name,
      'tierLabel': tierLabel,
      'titleSuffix': titleSuffix,
      'minElo': minElo,
      'maxElo': maxElo,
      'caption': caption,
      'notificationsEnabled': false,
      'countSingular': countSingular,
      'countPlural': countPlural,
      'savedAt': (savedAt ?? DateTime.now()).toIso8601String(),
      'events': events
          .map(
            (event) => {
              'id': event.id,
              'title': event.title,
              'dates': event.dates,
              'maxAvgElo': event.maxAvgElo,
              'timeUntilStart': event.timeUntilStart,
              'tourEventCategory': event.tourEventCategory.name,
              'timeControl': event.timeControl,
              'startDate': event.startDate?.toIso8601String(),
              'endDate': event.endDate?.toIso8601String(),
              'location': event.location,
              'searchTerms': event.searchTerms,
              'eventSource': event.eventSource.name,
            },
          )
          .toList(growable: false),
    };
  }

  factory SmartEventRequest.fromFavoriteEvent(FavoriteEvent favorite) {
    final metadata = favorite.metadata;
    final sourceName = metadata['source']?.toString();
    final source = SmartEventSource.values.firstWhere(
      (value) => value.name == sourceName,
      orElse: () => SmartEventSource.forYou,
    );
    final eventRows =
        metadata['events'] is List
            ? metadata['events'] as List
            : const <dynamic>[];
    final events = eventRows
        .whereType<Map>()
        .map((row) => _eventFromMetadata(row.cast<String, dynamic>()))
        .whereType<GroupEventCardModel>()
        .toList(growable: false);

    return SmartEventRequest(
      source: source,
      tierLabel: _normalizedTierLabel(
        metadata['tierLabel'],
        favorite.eventName,
      ),
      titleSuffix: _normalizedTitleSuffix(metadata['titleSuffix']),
      minElo: _intFromMetadata(metadata['minElo']) ?? kFilterMinElo.round(),
      maxElo: _intFromMetadata(metadata['maxElo']) ?? kFilterMaxElo.round(),
      caption: _normalizedCaption(
        metadata['caption'],
        _intFromMetadata(metadata['minElo']) ?? kFilterMinElo.round(),
      ),
      countSingular: _normalizedCountLabel(
        metadata['countSingular'],
        singular: true,
      ),
      countPlural: _normalizedCountLabel(
        metadata['countPlural'],
        singular: false,
      ),
      events: events,
      savedAt: _dateFromMetadata(metadata['savedAt']) ?? favorite.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SmartEventRequest) return false;
    if (source != other.source ||
        tierLabel != other.tierLabel ||
        titleSuffix != other.titleSuffix ||
        minElo != other.minElo ||
        maxElo != other.maxElo ||
        caption != other.caption ||
        countSingular != other.countSingular ||
        countPlural != other.countPlural ||
        savedAt != other.savedAt ||
        events.length != other.events.length) {
      return false;
    }
    for (var i = 0; i < events.length; i++) {
      if (events[i] != other.events[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    source,
    tierLabel,
    titleSuffix,
    minElo,
    maxElo,
    caption,
    countSingular,
    countPlural,
    savedAt,
    Object.hashAll(events),
  );
}

@immutable
class SmartEventCardData {
  const SmartEventCardData({
    required this.request,
    required this.eventCount,
    required this.avgElo,
  });

  final SmartEventRequest request;
  final int eventCount;
  final int avgElo;

  static SmartEventCardData? fromState({
    required FilterPopupState filter,
    required List<GroupEventCardModel> events,
    required SmartEventSource source,
  }) {
    if (events.isEmpty) return null;
    if (filter.formatsAndStates.isEmpty && !filter.hasEloFilter) return null;

    final minElo = filter.minElo ?? kFilterMinElo.round();
    final maxElo = filter.maxElo ?? kFilterMaxElo.round();

    // ELO segment: e.g. "GM" / "IM" / "FM" / "CM". Null when no ELO filter.
    final eloFull =
        filter.hasEloFilter ? RatingTierFilter.labelForMinRating(minElo) : null;
    final eloPart = eloFull?.split(' ').first;

    // Format / state segment: single-value labels stay as-is; multi-value
    // combinations fall back to "Filtered". When the user has both an ELO
    // tier AND a multi-value format set, prefer the cleaner tier-only label
    // (the format ambiguity reads worse than its absence).
    final rawFormat = _labelForNonEloFilters(filter);
    final formatPart =
        rawFormat == null || (eloPart != null && rawFormat == 'Filtered')
            ? null
            : rawFormat;

    final combined =
        [eloPart, formatPart].whereType<String>().join(' ').trim();
    final tierLabel = combined.isEmpty ? 'All' : combined;

    final captionSegments = <String>[
      if (filter.hasEloFilter) '$minElo+',
      if (formatPart != null) formatPart,
    ];
    final caption =
        captionSegments.isEmpty
            ? 'From your filters'
            : 'From your ${captionSegments.join(' ')} filter';

    final elos = events.map((e) => e.maxAvgElo).where((e) => e > 0).toList();
    final avgElo =
        elos.isEmpty ? 0 : (elos.reduce((a, b) => a + b) / elos.length).round();

    return SmartEventCardData(
      request: SmartEventRequest(
        source: source,
        tierLabel: tierLabel,
        titleSuffix: 'Games',
        minElo: minElo,
        maxElo: maxElo,
        caption: caption,
        countSingular: 'live event',
        countPlural: 'live events',
        events: events,
      ),
      eventCount: events.length,
      avgElo: avgElo,
    );
  }

  /// Returns a friendly label for the non-ELO portion of the filter, or null
  /// when no format/state filter is applied.
  /// Multi-value combinations collapse to "Filtered".
  static String? _labelForNonEloFilters(FilterPopupState filter) {
    final values =
        filter.formatsAndStates
            .map((value) => value.trim().toLowerCase())
            .where((value) => value.isNotEmpty)
            .toSet();
    if (values.isEmpty) return null;
    if (values.length == 1) {
      final only = values.first;
      if (only == 'live') return 'Live';
      if (only == 'completed') return 'Completed';
      if (only == 'standard') return 'Classical';
      if (only == 'rapid') return 'Rapid';
      if (only == 'blitz') return 'Blitz';
    }
    return 'Filtered';
  }
}

@immutable
class SmartEventGamesQuery {
  const SmartEventGamesQuery({
    required this.request,
    this.filter,
    this.searchQuery = '',
  });

  final SmartEventRequest request;
  final GameFilter? filter;
  final String searchQuery;

  String get normalizedSearchQuery => searchQuery.trim().toLowerCase();

  bool get hasActiveControls =>
      normalizedSearchQuery.isNotEmpty ||
      filter?.hasActiveFilters == true ||
      filter?.hasActiveSorts == true;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SmartEventGamesQuery &&
            other.request == request &&
            other.filter == filter &&
            other.normalizedSearchQuery == normalizedSearchQuery;
  }

  @override
  int get hashCode => Object.hash(request, filter, normalizedSearchQuery);
}

@immutable
class SmartCurrentEventIdsQuery {
  SmartCurrentEventIdsQuery(Iterable<String> eventIds)
    : eventIds = List<String>.unmodifiable(
        eventIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false)..sort(),
      );

  final List<String> eventIds;

  bool get isEmpty => eventIds.isEmpty;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SmartCurrentEventIdsQuery &&
            listEquals(eventIds, other.eventIds);
  }

  @override
  int get hashCode => Object.hashAll(eventIds);
}

final smartCurrentEventIdsProvider = FutureProvider.autoDispose
    .family<Set<String>, SmartCurrentEventIdsQuery>((ref, query) async {
      if (query.isEmpty) return const <String>{};

      final broadcasts = await ref
          .read(groupBroadcastRepositoryProvider)
          .getCurrentGroupBroadcastsByIds(query.eventIds);
      return broadcasts.map((broadcast) => broadcast.id).toSet();
    });

/// Generated level games gathered from every currently-live broadcast
/// (optionally narrowed by the applied ELO tier) into one place, plus the
/// aggregate metadata the event view needs for its About header.
class SmartAggregateEvent {
  const SmartAggregateEvent({
    required this.games,
    required this.tournamentCount,
    required this.avgElo,
    required this.minElo,
    required this.tournamentNames,
    required this.dateStart,
    required this.dateEnd,
    required this.timeControls,
    required this.pinnedGameIds,
    required this.events,
    required this.gameEventNames,
  });

  /// Ordered by day, then pinned games, then average rating.
  final List<GamesTourModel> games;
  final int tournamentCount;
  final int avgElo;
  final int? minElo;
  final List<String> tournamentNames;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final List<String> timeControls;
  final List<String> pinnedGameIds;
  final List<GroupEventCardModel> events;
  final Map<String, String> gameEventNames;

  int get liveGameCount =>
      games.where((g) => g.effectiveGameStatus.isOngoing).length;

  static const empty = SmartAggregateEvent(
    games: <GamesTourModel>[],
    tournamentCount: 0,
    avgElo: 0,
    minElo: null,
    tournamentNames: <String>[],
    dateStart: null,
    dateEnd: null,
    timeControls: <String>[],
    pinnedGameIds: <String>[],
    events: <GroupEventCardModel>[],
    gameEventNames: <String, String>{},
  );
}

/// Composes the filtered event set from the launching tab. Each child event is
/// resolved through [forYouEventSnapshotProvider], the same snapshot path used
/// by real event cards in For You, so smart-event Games rows stay aligned with
/// the regular event detail selection, ordering, pinning, and live updates.
final smartEventDismissedEventIdsProvider = StateProvider.autoDispose
    .family<Set<String>, String>((ref, scopeId) => const <String>{});

final smartAggregateEventRepositoryProvider = FutureProvider.autoDispose
    .family<SmartAggregateEvent, SmartEventGamesQuery>((ref, query) async {
      final dismissedIds = ref.watch(
        smartEventDismissedEventIdsProvider(query.request.scopeId),
      );
      return _loadAggregateEventFromRepository(
        ref: ref,
        query: query,
        dismissedIds: dismissedIds,
      );
    });

final smartFilteredAggregateEventProvider = Provider.autoDispose.family<
  AsyncValue<SmartAggregateEvent>,
  SmartEventGamesQuery
>((ref, query) {
  final directAsync = ref.watch(smartAggregateEventRepositoryProvider(query));
  final baseAsync = ref.watch(smartAggregateEventProvider(query.request));

  return directAsync.when(
    data: (direct) {
      if (direct.events.isEmpty) {
        return AsyncValue.data(direct);
      }
      if (direct.games.isNotEmpty) {
        return AsyncValue.data(direct);
      }
      final fallback = baseAsync.valueOrNull;
      if (fallback != null && fallback.games.isNotEmpty) {
        return AsyncValue.data(fallback);
      }
      return AsyncValue.data(direct);
    },
    loading: () {
      final fallback = baseAsync.valueOrNull;
      if (fallback != null && fallback.games.isNotEmpty) {
        return AsyncValue.data(fallback);
      }
      return const AsyncValue.loading();
    },
    error: (error, stackTrace) {
      final fallback = baseAsync.valueOrNull;
      if (fallback != null) {
        return AsyncValue.data(fallback);
      }
      return AsyncValue.error(error, stackTrace);
    },
  );
});

final smartAggregateEventProvider = Provider.autoDispose
    .family<AsyncValue<SmartAggregateEvent>, SmartEventRequest>((ref, request) {
      if (request.events.isEmpty) {
        return const AsyncValue.data(SmartAggregateEvent.empty);
      }

      final directAsync = ref.watch(
        smartAggregateEventRepositoryProvider(
          SmartEventGamesQuery(request: request),
        ),
      );
      final directAggregate = directAsync.valueOrNull;
      if (directAggregate != null && directAggregate.games.isNotEmpty) {
        return AsyncValue.data(directAggregate);
      }
      if (directAggregate != null && directAggregate.events.isEmpty) {
        return AsyncValue.data(directAggregate);
      }

      var isLoading = false;
      Object? firstError;
      StackTrace? firstStackTrace;
      final snapshots = <ForYouEventGamesSnapshot>[];
      final dismissedIds = ref.watch(
        smartEventDismissedEventIdsProvider(request.scopeId),
      );
      final activeEvents = request.events
          .where((event) => !dismissedIds.contains(event.id))
          .toList(growable: false);
      if (activeEvents.isEmpty) {
        return const AsyncValue.data(SmartAggregateEvent.empty);
      }

      // The whole smart event view is scoped to *current* broadcasts. The
      // repository path filters server-side; mirror it here so the snapshot
      // fallback can't resurrect games from events that are no longer current.
      final currentEventIdsAsync = ref.watch(
        smartCurrentEventIdsProvider(
          SmartCurrentEventIdsQuery(activeEvents.map((event) => event.id)),
        ),
      );
      if (currentEventIdsAsync.hasError) {
        if (directAggregate != null) {
          return AsyncValue.data(directAggregate);
        }
        return AsyncValue.error(
          currentEventIdsAsync.error!,
          currentEventIdsAsync.stackTrace ?? StackTrace.current,
        );
      }
      final currentEventIds = currentEventIdsAsync.valueOrNull;
      if (currentEventIds == null) {
        if (directAggregate != null) {
          return AsyncValue.data(directAggregate);
        }
        return const AsyncValue.loading();
      }
      final currentEvents = activeEvents
          .where((event) => currentEventIds.contains(event.id))
          .toList(growable: false);
      if (currentEvents.isEmpty) {
        return const AsyncValue.data(SmartAggregateEvent.empty);
      }

      for (final event in currentEvents) {
        final snapshotAsync = ref.watch(forYouEventSnapshotProvider(event.id));
        snapshotAsync.when(
          data: (snapshot) {
            if (snapshot.hasGames) snapshots.add(snapshot);
          },
          loading: () => isLoading = true,
          error: (error, stackTrace) {
            firstError ??= error;
            firstStackTrace ??= stackTrace;
          },
        );
      }

      final aggregate = _buildAggregateEvent(
        request,
        snapshots,
        events: currentEvents,
      );
      if (aggregate.games.isNotEmpty) {
        return AsyncValue.data(aggregate);
      }

      if (directAggregate != null) {
        return AsyncValue.data(directAggregate);
      }

      if (isLoading || directAsync.isLoading) {
        return const AsyncValue.loading();
      }

      if (firstError != null) {
        return AsyncValue.error(firstError!, firstStackTrace!);
      }

      if (directAsync.hasError) {
        return AsyncValue.error(directAsync.error!, directAsync.stackTrace!);
      }

      return AsyncValue.data(aggregate);
    });

Future<SmartAggregateEvent> _loadAggregateEventFromRepository({
  required Ref ref,
  required SmartEventGamesQuery query,
  required Set<String> dismissedIds,
}) async {
  final request = query.request;
  final activeEvents = request.events
      .where((event) => !dismissedIds.contains(event.id))
      .toList(growable: false);
  if (activeEvents.isEmpty) return SmartAggregateEvent.empty;

  final currentEvents = await _currentSmartEvents(
    ref: ref,
    events: activeEvents,
  );
  if (currentEvents.isEmpty) return SmartAggregateEvent.empty;

  final eventIds = currentEvents
      .map((event) => event.id)
      .toList(growable: false);
  final tourRepository = ref.read(tourRepositoryProvider);
  final toursByEvent = await tourRepository.getToursByGroupBroadcastIds(
    eventIds,
  );

  final missingEventIds =
      eventIds.where((id) => (toursByEvent[id] ?? const []).isEmpty).toList();
  if (missingEventIds.isNotEmpty) {
    final fallbackTours = await tourRepository.getToursByIds(missingEventIds);
    for (final tour in fallbackTours) {
      final eventId =
          missingEventIds.contains(tour.id)
              ? tour.id
              : tour.groupBroadcastId != null &&
                  missingEventIds.contains(tour.groupBroadcastId)
              ? tour.groupBroadcastId!
              : null;
      if (eventId == null) continue;
      toursByEvent.putIfAbsent(eventId, () => []).add(tour);
    }
  }

  final tourIds = <String>[];
  final seenTourIds = <String>{};
  final tourIdToEventId = <String, String>{};
  for (final event in currentEvents) {
    for (final tour in toursByEvent[event.id] ?? const []) {
      if (seenTourIds.add(tour.id)) {
        tourIds.add(tour.id);
      }
      tourIdToEventId[tour.id] = event.id;
    }
  }

  if (tourIds.isEmpty) {
    return _buildAggregateEventFromGameRows(
      request: request,
      events: currentEvents,
      games: const <Games>[],
      tourIdToEventId: tourIdToEventId,
      minAverageElo: _effectiveMinAverageElo(request, query.filter),
      maxAverageElo: _effectiveMaxAverageElo(request, query.filter),
    );
  }

  final minAverageElo = _effectiveMinAverageElo(request, query.filter);
  final maxAverageElo = _effectiveMaxAverageElo(request, query.filter);
  final games = await ref
      .read(gameRepositoryProvider)
      .getSmartEventGamesFromTourIds(
        tourIds: tourIds,
        filter: query.filter,
        query: query.normalizedSearchQuery,
        minAverageEloForPrefilter:
            minAverageElo > GameFilter.defaultMinRating ? minAverageElo : null,
        limit: 1000,
      );

  return _buildAggregateEventFromGameRows(
    request: request,
    events: currentEvents,
    games: games,
    tourIdToEventId: tourIdToEventId,
    minAverageElo: minAverageElo,
    maxAverageElo: maxAverageElo,
  );
}

Future<List<GroupEventCardModel>> _currentSmartEvents({
  required Ref ref,
  required List<GroupEventCardModel> events,
}) async {
  if (events.isEmpty) return const <GroupEventCardModel>[];

  final currentEventIds = await ref.read(
    smartCurrentEventIdsProvider(
      SmartCurrentEventIdsQuery(events.map((event) => event.id)),
    ).future,
  );
  if (currentEventIds.isEmpty) return const <GroupEventCardModel>[];

  return events
      .where((event) => currentEventIds.contains(event.id))
      .toList(growable: false);
}

SmartAggregateEvent _buildAggregateEventFromGameRows({
  required SmartEventRequest request,
  required List<GroupEventCardModel> events,
  required List<Games> games,
  required Map<String, String> tourIdToEventId,
  required int minAverageElo,
  required int maxAverageElo,
}) {
  final eventById = {for (final event in events) event.id: event};
  final gamesById = <String, GamesTourModel>{};
  final gameEventNames = <String, String>{};
  final eventIdsWithGames = <String>{};

  for (final game in games) {
    final eventId = tourIdToEventId[game.tourId];
    if (eventId == null) continue;

    late final GamesTourModel gameModel;
    try {
      gameModel = GamesTourModel.fromGame(game);
    } catch (_) {
      continue;
    }

    if (!_matchesAverageEloRange(
      gameModel,
      minAverageElo: minAverageElo,
      maxAverageElo: maxAverageElo,
    )) {
      continue;
    }

    gamesById.putIfAbsent(gameModel.gameId, () => gameModel);
    gameEventNames[gameModel.gameId] = eventById[eventId]?.title ?? eventId;
    eventIdsWithGames.add(eventId);
  }

  final orderedGames = _sortSmartGames(
    gamesById.values.toList(growable: false),
    pinnedIds: const <String>[],
  );
  final participatingEvents =
      eventIdsWithGames.isEmpty
          ? events
          : events
              .where((event) => eventIdsWithGames.contains(event.id))
              .toList(growable: false);

  return _createSmartAggregateEvent(
    request: request,
    participatingEvents: participatingEvents,
    orderedGames: orderedGames,
    gameEventNames: gameEventNames,
    pinnedIds: const <String>[],
  );
}

SmartAggregateEvent _buildAggregateEvent(
  SmartEventRequest request,
  List<ForYouEventGamesSnapshot> snapshots, {
  List<GroupEventCardModel>? events,
}) {
  final activeEvents = events ?? request.events;
  final eventById = {for (final event in activeEvents) event.id: event};

  final gamesById = <String, GamesTourModel>{};
  final gameEventNames = <String, String>{};
  final pinnedIds = <String>[];
  final seenPinnedIds = <String>{};
  final eventIdsWithGames = <String>{};

  for (final snapshot in snapshots) {
    if (snapshot.hasGames) eventIdsWithGames.add(snapshot.eventId);
    for (final pinId in snapshot.pinnedIds) {
      if (seenPinnedIds.add(pinId)) pinnedIds.add(pinId);
    }
    for (final game in snapshot.visibleGames) {
      if (!_matchesRequestEloRange(game, request)) continue;
      gamesById.putIfAbsent(game.gameId, () => game);
      gameEventNames[game.gameId] =
          eventById[snapshot.eventId]?.title ?? snapshot.eventId;
    }
  }

  final orderedGames = _sortSmartGames(
    gamesById.values.toList(growable: false),
    pinnedIds: pinnedIds,
  );

  final participatingEvents =
      eventIdsWithGames.isEmpty
          ? activeEvents
          : activeEvents
              .where((event) => eventIdsWithGames.contains(event.id))
              .toList(growable: false);

  return _createSmartAggregateEvent(
    request: request,
    participatingEvents: participatingEvents,
    orderedGames: orderedGames,
    gameEventNames: gameEventNames,
    pinnedIds: pinnedIds,
  );
}

SmartAggregateEvent _createSmartAggregateEvent({
  required SmartEventRequest request,
  required List<GroupEventCardModel> participatingEvents,
  required List<GamesTourModel> orderedGames,
  required Map<String, String> gameEventNames,
  required List<String> pinnedIds,
}) {
  final elos =
      participatingEvents
          .map((event) => event.maxAvgElo)
          .where((elo) => elo > 0)
          .toList();
  final avgElo =
      elos.isEmpty ? 0 : (elos.reduce((a, b) => a + b) / elos.length).round();

  final dates =
      participatingEvents
          .expand((event) => <DateTime?>[event.startDate, event.endDate])
          .whereType<DateTime>()
          .toList()
        ..sort();

  final timeControls =
      participatingEvents
          .map((event) => event.timeControl.trim())
          .where((timeControl) => timeControl.isNotEmpty)
          .toSet()
          .toList();

  return SmartAggregateEvent(
    games: orderedGames,
    tournamentCount: participatingEvents.length,
    avgElo: avgElo,
    minElo: request.minElo > kFilterMinElo ? request.minElo : null,
    tournamentNames: participatingEvents
        .map((event) => event.title)
        .toList(growable: false),
    dateStart: dates.isEmpty ? null : dates.first,
    dateEnd: dates.isEmpty ? null : dates.last,
    timeControls: timeControls,
    pinnedGameIds: pinnedIds,
    events: participatingEvents,
    gameEventNames: gameEventNames,
  );
}

bool _matchesRequestEloRange(GamesTourModel game, SmartEventRequest request) {
  if (!request.hasEloRange) return true;
  return _matchesAverageEloRange(
    game,
    minAverageElo: request.minElo,
    maxAverageElo: request.maxElo,
  );
}

bool _matchesAverageEloRange(
  GamesTourModel game, {
  required int minAverageElo,
  required int maxAverageElo,
}) {
  final hasLowerBound = minAverageElo > GameFilter.defaultMinRating;
  final hasUpperBound = maxAverageElo < GameFilter.absoluteMaxRating;
  if (!hasLowerBound && !hasUpperBound) return true;
  final gameAvgElo = smartGameAverageElo(game);
  if (gameAvgElo <= 0) return false;
  return gameAvgElo >= minAverageElo && gameAvgElo <= maxAverageElo;
}

int _effectiveMinAverageElo(SmartEventRequest request, GameFilter? filter) {
  var value =
      request.hasEloRange ? request.minElo : GameFilter.defaultMinRating;
  final filterMin = filter?.minRating ?? GameFilter.defaultMinRating;
  if (filterMin > value) value = filterMin;
  return value;
}

int _effectiveMaxAverageElo(SmartEventRequest request, GameFilter? filter) {
  var value =
      request.hasEloRange ? request.maxElo : GameFilter.absoluteMaxRating;
  final filterMax = filter?.maxRating ?? GameFilter.absoluteMaxRating;
  if (filterMax < value) value = filterMax;
  return value;
}

int smartGameAverageElo(GamesTourModel game) {
  final ratings = <int>[
    game.whitePlayer.rating,
    game.blackPlayer.rating,
  ].where((rating) => rating > 0).toList(growable: false);
  if (ratings.isEmpty) return 0;
  return (ratings.reduce((a, b) => a + b) / ratings.length).round();
}

@visibleForTesting
List<GamesTourModel> sortSmartGamesForTest(
  List<GamesTourModel> games, {
  required List<String> pinnedIds,
}) {
  return _sortSmartGames(games, pinnedIds: pinnedIds);
}

List<GamesTourModel> _sortSmartGames(
  List<GamesTourModel> games, {
  required List<String> pinnedIds,
}) {
  final pinned = pinnedIds.toSet();
  final sorted = List<GamesTourModel>.from(games);
  sorted.sort((a, b) {
    final ad = _smartGameDay(a);
    final bd = _smartGameDay(b);
    final byDay = bd.compareTo(ad);
    if (byDay != 0) return byDay;

    // Within a day, live games surface above finished ones — the live tab
    // should feel live first, strongest second.
    final aLive = a.effectiveGameStatus.isOngoing ? 1 : 0;
    final bLive = b.effectiveGameStatus.isOngoing ? 1 : 0;
    if (aLive != bLive) return bLive.compareTo(aLive);

    final aPinned = pinned.contains(a.gameId) ? 1 : 0;
    final bPinned = pinned.contains(b.gameId) ? 1 : 0;
    if (aPinned != bPinned) return bPinned.compareTo(aPinned);

    final byAvgElo = smartGameAverageElo(b).compareTo(smartGameAverageElo(a));
    if (byAvgElo != 0) return byAvgElo;

    final byTopElo = b.cardElo.compareTo(a.cardElo);
    if (byTopElo != 0) return byTopElo;

    final aBoard = a.boardNr;
    final bBoard = b.boardNr;
    if (aBoard != null && bBoard != null) return aBoard.compareTo(bBoard);
    if (aBoard != null) return -1;
    if (bBoard != null) return 1;
    return a.gameId.compareTo(b.gameId);
  });
  return sorted;
}

DateTime _smartGameDay(GamesTourModel game) {
  final raw = game.lastMoveTime ?? game.bucketDate ?? DateTime(0);
  final local = raw.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String _normalizedTierLabel(Object? value, String fallbackName) {
  final text = value?.toString().trim();
  final label =
      text == null || text.isEmpty
          ? _tierLabelFromDisplayName(fallbackName)
          : text;
  return label.isEmpty ? 'All' : label;
}

String _tierLabelFromDisplayName(String value) {
  final text = value.trim();
  const suffix = ' Games';
  if (text.endsWith(suffix)) {
    return text.substring(0, text.length - suffix.length).trim();
  }
  return text;
}

String _normalizedTitleSuffix(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'Live Games') return 'Games';
  return text;
}

String _normalizedCountLabel(Object? value, {required bool singular}) {
  final fallback = singular ? 'live event' : 'live events';
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return fallback;
  return text;
}

String _normalizedCaption(Object? value, int minElo) {
  final text = value?.toString().trim();
  if (text == null ||
      text.isEmpty ||
      text == 'Saved smart event' ||
      text.startsWith('Gathered from your')) {
    if (minElo > kFilterMinElo) return 'From your $minElo+ filter';
    return 'From your filters';
  }
  return text;
}

GroupEventCardModel? _eventFromMetadata(Map<String, dynamic> json) {
  final id = json['id']?.toString();
  final title = json['title']?.toString();
  if (id == null || id.isEmpty || title == null || title.isEmpty) return null;

  final categoryName = json['tourEventCategory']?.toString();
  final category = TourEventCategory.values.firstWhere(
    (value) => value.name == categoryName,
    orElse: () => TourEventCategory.ongoing,
  );
  final sourceName = json['eventSource']?.toString();
  final eventSource = EventSource.values.firstWhere(
    (value) => value.name == sourceName,
    orElse: () => EventSource.lichessBroadcast,
  );

  return GroupEventCardModel(
    id: id,
    title: title,
    dates: json['dates']?.toString() ?? '',
    maxAvgElo: _intFromMetadata(json['maxAvgElo']) ?? 0,
    timeUntilStart: json['timeUntilStart']?.toString() ?? '',
    tourEventCategory: category,
    timeControl: json['timeControl']?.toString() ?? 'Standard',
    endDate: _dateFromMetadata(json['endDate']),
    startDate: _dateFromMetadata(json['startDate']),
    location: json['location']?.toString(),
    searchTerms:
        json['searchTerms'] is List
            ? (json['searchTerms'] as List)
                .map((value) => value.toString())
                .toList(growable: false)
            : const <String>[],
    eventSource: eventSource,
  );
}

int? _intFromMetadata(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _dateFromMetadata(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text);
}
