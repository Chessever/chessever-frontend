import 'dart:async';

import 'package:chessever2/providers/favorite_events_provider.dart';
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
    Set<String> formatsAndStates = const {},
    this.savedAt,
  }) : events = List<GroupEventCardModel>.unmodifiable(events),
       formatsAndStates = Set<String>.unmodifiable(
         formatsAndStates
             .map((value) => value.trim().toLowerCase())
             .where((value) => value.isNotEmpty),
       );

  final SmartEventSource source;
  final String tierLabel;
  final String titleSuffix;
  final int minElo;
  final int maxElo;
  final String caption;
  final String countSingular;
  final String countPlural;
  final List<GroupEventCardModel> events;

  /// The format/state criteria the smart event was generated from (subset of
  /// {live, completed, standard, rapid, blitz}). The in-event filter dialog
  /// seeds from these via [seedGameFilter] so they arrive pre-selected, and
  /// overrides flow back through [withGameFilterOverrides].
  final Set<String> formatsAndStates;
  final DateTime? savedAt;

  static const _timeControlCriteria = {'standard', 'rapid', 'blitz'};
  static const _stateCriteria = {'live', 'completed'};
  static const _tierFloors = {'GM': 2500, 'IM': 2400, 'FM': 2300, 'CM': 2200};

  /// The dialog-representable projection of the criteria this smart event
  /// was generated from. Seeds the in-event Games tab filter so the root
  /// filters arrive pre-selected (and counted by the filter-button badge)
  /// instead of hidden; the dialog and the tier dropdown then act as
  /// override surfaces on top. A live+completed pair cancels out to "all",
  /// and a multi-value time-control set falls back to "all" because the
  /// dialog's single-select can't represent it.
  GameFilter seedGameFilter() {
    final hasLive = formatsAndStates.contains('live');
    final hasCompleted = formatsAndStates.contains('completed');
    final live =
        hasLive == hasCompleted
            ? GameLiveFilter.all
            : (hasLive ? GameLiveFilter.live : GameLiveFilter.completed);

    final timeControls =
        formatsAndStates.where(_timeControlCriteria.contains).toList();
    final timeControl =
        timeControls.length != 1
            ? GameTimeControlFilter.all
            : switch (timeControls.first) {
              'standard' => GameTimeControlFilter.classical,
              'rapid' => GameTimeControlFilter.rapid,
              'blitz' => GameTimeControlFilter.blitz,
              _ => GameTimeControlFilter.all,
            };

    return GameFilter(live: live, timeControl: timeControl);
  }

  /// The request re-keyed to the in-event dialog's overrides of its
  /// generating criteria. A dimension is replaced only when the dialog value
  /// diverges from [seedGameFilter]'s projection (an "all" selection clears
  /// it); untouched dimensions keep their original — possibly multi-value —
  /// criteria. Returns `this` unchanged when nothing diverges.
  SmartEventRequest withGameFilterOverrides(GameFilter filter) {
    final seed = seedGameFilter();
    final updated = <String>{...formatsAndStates};

    if (filter.live != seed.live) {
      updated.removeAll(_stateCriteria);
      switch (filter.live) {
        case GameLiveFilter.live:
          updated.add('live');
        case GameLiveFilter.completed:
          updated.add('completed');
        case GameLiveFilter.all:
          break;
      }
    }
    if (filter.timeControl != seed.timeControl) {
      updated.removeAll(_timeControlCriteria);
      switch (filter.timeControl) {
        case GameTimeControlFilter.classical:
          updated.add('standard');
        case GameTimeControlFilter.rapid:
          updated.add('rapid');
        case GameTimeControlFilter.blitz:
          updated.add('blitz');
        case GameTimeControlFilter.all:
          break;
      }
    }

    if (setEquals(updated, formatsAndStates)) return this;
    return _withFormatsAndStates(updated);
  }

  /// Rebuilds the request around a new criteria set, re-deriving the name
  /// and caption exactly like [SmartEventCardData.fromState] /
  /// [withTierSelection] so all three produce identical labels.
  SmartEventRequest _withFormatsAndStates(Set<String> newFormatsAndStates) {
    final eloFull =
        hasEloRange ? RatingTierFilter.labelForMinRating(minElo) : null;
    final eloPart = eloFull?.split(' ').first;

    final rawFormat = _labelForFormatsAndStates(newFormatsAndStates);
    final formatPart =
        rawFormat == null || (eloPart != null && rawFormat == 'Filtered')
            ? null
            : rawFormat;
    final combined = [eloPart, formatPart].whereType<String>().join(' ').trim();

    final captionSegments = <String>[
      if (hasEloRange) '$minElo+',
      if (formatPart != null) formatPart,
    ];

    return SmartEventRequest(
      source: source,
      tierLabel: combined.isEmpty ? 'All' : combined,
      titleSuffix: titleSuffix,
      minElo: minElo,
      maxElo: maxElo,
      caption:
          captionSegments.isEmpty
              ? 'From your filters'
              : 'From your ${captionSegments.join(' ')} filter',
      countSingular: countSingular,
      countPlural: countPlural,
      events: events,
      formatsAndStates: newFormatsAndStates,
      savedAt: savedAt,
    );
  }

  /// The same smart event re-keyed to a different level tier — what the
  /// in-event tier dropdown produces. Naming, caption and the Elo floor
  /// follow the new tier immediately; the included events, format criteria
  /// and labels otherwise stay.
  SmartEventRequest withTierSelection(String tier) {
    final floor = _tierFloors[tier];
    final newMinElo = floor ?? kFilterMinElo.round();
    final eloPart = floor == null ? null : tier;

    // Mirrors SmartEventCardData.fromState: single-value format labels stay,
    // multi-value "Filtered" is dropped next to a tier part.
    final rawFormat = _labelForFormatsAndStates(formatsAndStates);
    final formatPart =
        rawFormat == null || (eloPart != null && rawFormat == 'Filtered')
            ? null
            : rawFormat;
    final combined = [eloPart, formatPart].whereType<String>().join(' ').trim();

    final captionSegments = <String>[
      if (floor != null) '$newMinElo+',
      if (formatPart != null) formatPart,
    ];

    return SmartEventRequest(
      source: source,
      tierLabel: combined.isEmpty ? 'All' : combined,
      titleSuffix: titleSuffix,
      minElo: newMinElo,
      maxElo: maxElo,
      caption:
          captionSegments.isEmpty
              ? 'From your filters'
              : 'From your ${captionSegments.join(' ')} filter',
      countSingular: countSingular,
      countPlural: countPlural,
      events: events,
      formatsAndStates: formatsAndStates,
      savedAt: savedAt,
    );
  }

  List<String> get eventIds =>
      events.map((event) => event.id).toList(growable: false);

  List<String> get stableEventIds {
    final ids = eventIds.toList(growable: false)..sort();
    return ids;
  }

  bool get hasEloRange => minElo > kFilterMinElo || maxElo < kFilterMaxElo;

  String get scopeId =>
      '${source.name}:$minElo-$maxElo:${stableEventIds.join('|')}';

  /// Tier-independent scope: hiding a tournament from the About tab applies
  /// across every tier re-keying of the same smart event.
  String get dismissScopeId => '${source.name}:${stableEventIds.join('|')}';

  /// Source- and event-independent key for hiding the generated smart card.
  ///
  /// The For You and Current tabs build separate [SmartEventRequest] instances
  /// from the same applied filters. Dismissing the card should therefore apply
  /// to the filter configuration, not to one tab's source or current event set.
  String get cardDismissKey {
    final criteria = formatsAndStates.toList(growable: false)..sort();
    return 'smart_event_card:$minElo-$maxElo:${criteria.join('|')}';
  }

  /// The same request with the Elo range opened up to the full scale. The
  /// Games / Standings tabs load through this so the tier dropdown can move
  /// BELOW the saved floor — the selected band travels in the query's
  /// [GameFilter] instead.
  SmartEventRequest withNeutralEloRange() {
    if (!hasEloRange) return this;
    return SmartEventRequest(
      source: source,
      tierLabel: tierLabel,
      titleSuffix: titleSuffix,
      minElo: kFilterMinElo.round(),
      maxElo: kFilterMaxElo.round(),
      caption: caption,
      countSingular: countSingular,
      countPlural: countPlural,
      events: events,
      formatsAndStates: formatsAndStates,
      savedAt: savedAt,
    );
  }

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
      'formatsAndStates': (formatsAndStates.toList(growable: false)..sort()),
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
      formatsAndStates: _formatsAndStatesFromMetadata(
        metadata['formatsAndStates'],
        fallbackLabel: _normalizedTierLabel(
          metadata['tierLabel'],
          favorite.eventName,
        ),
      ),
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
        !setEquals(formatsAndStates, other.formatsAndStates) ||
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
    Object.hashAllUnordered(formatsAndStates),
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

    final combined = [eloPart, formatPart].whereType<String>().join(' ').trim();
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
        countSingular: 'event',
        countPlural: 'events',
        events: events,
        formatsAndStates: filter.formatsAndStates,
      ),
      eventCount: events.length,
      avgElo: avgElo,
    );
  }

  /// Returns a friendly label for the non-ELO portion of the filter, or null
  /// when no format/state filter is applied.
  /// Multi-value combinations collapse to "Filtered".
  static String? _labelForNonEloFilters(FilterPopupState filter) =>
      _labelForFormatsAndStates(filter.formatsAndStates);
}

final dismissedSmartEventCardKeysProvider = StateProvider<Set<String>>(
  (ref) => const <String>{},
);

SmartEventCardData? visibleSmartEventCardData(
  SmartEventCardData? data,
  Set<String> dismissedKeys,
) {
  if (data == null) return null;
  if (dismissedKeys.contains(data.request.cardDismissKey)) return null;
  return data;
}

/// Shared by card generation and tier re-keying so both produce identical
/// format/state name parts.
String? _labelForFormatsAndStates(Set<String> formatsAndStates) {
  final values =
      formatsAndStates
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

/// Metadata key under which a saved smart event stores its hidden tournaments.
const smartEventHiddenMetadataKey = 'hiddenEventIds';

/// Parse the hidden-tournament IDs out of a favorite's `metadata` JSONB.
Set<String> readSmartEventHiddenIds(Map<String, dynamic> metadata) {
  final raw = metadata[smartEventHiddenMetadataKey];
  if (raw is List) return raw.map((e) => e.toString()).toSet();
  return const <String>{};
}

/// Live, session-only hidden tournaments for an UNSAVED smart event — there's
/// no favorite row to persist to yet. Keyed by
/// [SmartEventRequest.dismissScopeId]; folded into the saved row's metadata
/// when the user saves the event. Intentionally NOT persisted: an unsaved smart
/// event is a transient preview.
final _smartEventSessionHiddenIdsProvider = StateProvider.family<
    Set<String>,
    String
>((ref, dismissScopeId) => const <String>{});

/// The saved favorite (if any) whose smart event matches [dismissScopeId].
/// `dismissScopeId` is tier/elo-independent, so this resolves the same saved
/// event regardless of the in-screen tier dropdown.
final smartEventSavedFavoriteProvider = Provider.family<FavoriteEvent?, String>((
  ref,
  dismissScopeId,
) {
  final favorites = ref.watch(favoriteEventsProvider).valueOrNull ?? const [];
  for (final favorite in favorites) {
    if (!isSmartFavoriteEvent(favorite)) continue;
    if (SmartEventRequest.fromFavoriteEvent(favorite).dismissScopeId ==
        dismissScopeId) {
      return favorite;
    }
  }
  return null;
});

/// The tournaments hidden from a smart event view, keyed by
/// [SmartEventRequest.dismissScopeId]. Source of truth:
///   • saved event   → its `user_favorite_events.metadata.hiddenEventIds`
///                      (server-side via Supabase, synced across devices)
///   • unsaved event → session-only [_smartEventSessionHiddenIdsProvider]
///
/// Because a saved event's config lives on its own row, DELETING the event
/// drops the config automatically — re-creating an identical filter set later
/// starts fresh instead of resurrecting the deleted event's hides. (The old
/// content-keyed local store had no such lifecycle and leaked configs across
/// re-creations.)
final smartEventDismissedEventIdsProvider = Provider.family<Set<String>, String>(
  (ref, dismissScopeId) {
    final favorite = ref.watch(smartEventSavedFavoriteProvider(dismissScopeId));
    if (favorite != null) return readSmartEventHiddenIds(favorite.metadata);
    return ref.watch(_smartEventSessionHiddenIdsProvider(dismissScopeId));
  },
);

/// Persist the hidden tournaments for a smart event. Routes to the saved
/// favorite's metadata (server-side, isolated to that row) when the event is
/// saved, or to session state when it isn't yet saved.
void setSmartEventHiddenIds(
  WidgetRef ref,
  String dismissScopeId,
  Set<String> ids,
) {
  final favorite = ref.read(smartEventSavedFavoriteProvider(dismissScopeId));
  if (favorite != null) {
    unawaited(
      ref
          .read(favoriteEventsProvider.notifier)
          .updateMetadata(favorite.eventId, {
            smartEventHiddenMetadataKey: ids.toList(growable: false),
          }),
    );
  } else {
    ref
        .read(_smartEventSessionHiddenIdsProvider(dismissScopeId).notifier)
        .state = ids;
  }
}

/// Drop the unsaved/session hidden set for a scope. Call once its config has
/// been folded into a saved row (on save) or when the event is deleted, so a
/// later unsaved view of the same scope can't resurrect stale session hides.
void resetSmartEventSessionHidden(WidgetRef ref, String dismissScopeId) {
  ref
      .read(_smartEventSessionHiddenIdsProvider(dismissScopeId).notifier)
      .state = const <String>{};
}

/// THE single data path for the smart event view. One server fetch per query
/// (events narrowed to the `group_broadcasts_current` view — the same source
/// as the home Current tab — search and filters applied server-side), then a
/// deterministic client-side sort. No snapshot fallback, no second source:
/// what loads is what renders, so the list can't reshuffle after first paint.
final smartAggregateEventRepositoryProvider = FutureProvider.autoDispose
    .family<SmartAggregateEvent, SmartEventGamesQuery>((ref, query) async {
      final dismissedIds = ref.watch(
        smartEventDismissedEventIdsProvider(query.request.dismissScopeId),
      );
      return _loadAggregateEventFromRepository(
        ref: ref,
        query: query,
        dismissedIds: dismissedIds,
      );
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
        limit: _smartEventGamesFetchCap,
      );

  return _buildAggregateEventFromGameRows(
    request: request,
    events: currentEvents,
    games: games,
    tourIdToEventId: tourIdToEventId,
    minAverageElo: minAverageElo,
    maxAverageElo: maxAverageElo,
    truncated: games.length >= _smartEventGamesFetchCap,
  );
}

/// Hard ceiling on how many game rows one smart event aggregation may pull.
/// The repository pages until every matching row is fetched, so a broad
/// filter (e.g. Classical across every current broadcast) sees the same day
/// span as a narrow one (e.g. Classical + GM) — a fixed single-page cap made
/// the broader filter cover FEWER days than the narrower one, which read as
/// "more games with more filters". The cap only guards against pathological
/// aggregations; when it is hit the trailing (incomplete) day is trimmed.
const int _smartEventGamesFetchCap = 6000;

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
  bool truncated = false,
}) {
  final eventById = {for (final event in events) event.id: event};
  final gamesById = <String, GamesTourModel>{};
  final gameEventIds = <String, String>{};

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
    gameEventIds[gameModel.gameId] = eventId;
  }

  var orderedGames = _sortSmartGames(
    gamesById.values.toList(growable: false),
    pinnedIds: const <String>[],
  );
  if (truncated) {
    orderedGames = _trimTrailingPartialDay(orderedGames);
  }

  // Names and participating events derive from the games that actually
  // render, so a trimmed trailing day can't leave a tournament listed in
  // About with zero visible games.
  final gameEventNames = <String, String>{};
  final eventIdsWithGames = <String>{};
  for (final game in orderedGames) {
    final eventId = gameEventIds[game.gameId];
    if (eventId == null) continue;
    gameEventNames[game.gameId] = eventById[eventId]?.title ?? eventId;
    eventIdsWithGames.add(eventId);
  }

  final participatingEvents = _sortEventsByAvgElo(
    eventIdsWithGames.isEmpty
        ? events
        : events
            .where((event) => eventIdsWithGames.contains(event.id))
            .toList(growable: false),
    games: orderedGames,
    gameEventIds: gameEventIds,
  );

  return _createSmartAggregateEvent(
    request: request,
    participatingEvents: participatingEvents,
    orderedGames: orderedGames,
    gameEventNames: gameEventNames,
    pinnedIds: const <String>[],
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

/// Canonical event ordering inside a smart event: average Elo descending.
/// About / Standings render the sorted [SmartAggregateEvent.events] list
/// directly.
///
/// Sort key per event: the stored broadcast average ([GroupEventCardModel
/// .maxAvgElo], the Ø figure shown on the event card) when present, otherwise
/// the mean of the event's own game averages so unrated broadcast rows still
/// land in the right place.
List<GroupEventCardModel> _sortEventsByAvgElo(
  List<GroupEventCardModel> events, {
  required Iterable<GamesTourModel> games,
  required Map<String, String> gameEventIds,
}) {
  if (events.length < 2) return events;

  final sums = <String, int>{};
  final counts = <String, int>{};
  for (final game in games) {
    final eventId = gameEventIds[game.gameId];
    if (eventId == null) continue;
    final avg = smartGameAverageElo(game);
    if (avg <= 0) continue;
    sums[eventId] = (sums[eventId] ?? 0) + avg;
    counts[eventId] = (counts[eventId] ?? 0) + 1;
  }

  int sortElo(GroupEventCardModel event) {
    if (event.maxAvgElo > 0) return event.maxAvgElo;
    final count = counts[event.id];
    if (count == null || count == 0) return 0;
    return (sums[event.id]! / count).round();
  }

  final sorted = List<GroupEventCardModel>.from(events);
  sorted.sort((a, b) {
    final byElo = sortElo(b).compareTo(sortElo(a));
    if (byElo != 0) return byElo;
    return a.title.compareTo(b.title);
  });
  return sorted;
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

@visibleForTesting
List<GamesTourModel> trimTrailingPartialDayForTest(
  List<GamesTourModel> sortedGames,
) {
  return _trimTrailingPartialDay(sortedGames);
}

/// Drops the oldest day from a day-desc sorted games list. Used only when the
/// fetch hit [_smartEventGamesFetchCap]: the trailing day is then almost
/// certainly half-fetched, and rendering it would show a misleadingly small
/// count for that day. A single-day list stays untouched — an empty list
/// would be worse than a partial one.
List<GamesTourModel> _trimTrailingPartialDay(List<GamesTourModel> sortedGames) {
  if (sortedGames.isEmpty) return sortedGames;
  final oldestDay = _smartGameDay(sortedGames.last);
  if (_smartGameDay(sortedGames.first) == oldestDay) return sortedGames;
  final cut =
      sortedGames.lastIndexWhere(
        (game) => _smartGameDay(game) != oldestDay,
      ) +
      1;
  return sortedGames.sublist(0, cut);
}

/// Deterministic games ordering: day (newest first) → pinned → average Elo
/// descending, with fixed tie-breakers down to the game id. Every key is a
/// stable property of the fetched row — deliberately NOT live status — so the
/// list can never reshuffle while the user is looking at it.
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
  final fallback = singular ? 'event' : 'events';
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return fallback;
  // A smart event aggregates every event in the Current view, live or not —
  // heal legacy saves that called the count "live events".
  if (text == 'live event' || text == 'live events') return fallback;
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

Set<String> _formatsAndStatesFromMetadata(
  Object? value, {
  required String fallbackLabel,
}) {
  if (value is List) {
    return value
        .map((entry) => entry.toString().trim().toLowerCase())
        .where((entry) => entry.isNotEmpty)
        .toSet();
  }
  // Legacy saves predate the field — recover what we can from the display
  // label ("GM Blitz", "Live", ...). Multi-value combos collapsed to
  // "Filtered" at save time and stay unrecoverable (empty = nothing pinned).
  final words = fallbackLabel.toLowerCase().split(RegExp(r'\s+'));
  return {
    for (final word in words)
      if (word == 'live' ||
          word == 'completed' ||
          word == 'rapid' ||
          word == 'blitz')
        word
      else if (word == 'classical')
        'standard',
  };
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
