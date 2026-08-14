import 'dart:async';

import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart'
    show filterBroadcastsByPopupState, liveBroadcastIdsProvider;
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/event_time_control.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show RangeValues;
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum SmartEventSource { forYou, current }

bool isSmartFavoriteEvent(FavoriteEvent favorite) {
  return favorite.metadata['type'] == 'smart_event' ||
      favorite.eventId.startsWith('smart_event:');
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

  /// The criteria this smart event is generated from, as a value object —
  /// the key everything self-refreshing hangs off (server resolution,
  /// saved-favorite identity, accent color). Deliberately excludes the
  /// resolved event set and the source tab: a smart event IS its criteria;
  /// the events matching them are recomputed from the server at view time.
  SmartEventCriteria get criteria =>
      SmartEventCriteria(
        minElo: minElo,
        maxElo: maxElo,
        formatsAndStates: formatsAndStates,
      );

  /// Stable string form of [criteria].
  String get criteriaKey => criteria.key;

  String get scopeId => criteriaKey;

  /// Source- and event-independent key for hiding the generated smart card.
  ///
  /// The For You and Current tabs build separate [SmartEventRequest] instances
  /// from the same applied filters. Dismissing the card should therefore apply
  /// to the filter configuration, not to one tab's source or current event set.
  String get cardDismissKey => 'smart_event_card:$criteriaKey';

  /// The same request carrying a different (freshly resolved) event set.
  SmartEventRequest withEvents(List<GroupEventCardModel> newEvents) {
    return SmartEventRequest(
      source: source,
      tierLabel: tierLabel,
      titleSuffix: titleSuffix,
      minElo: minElo,
      maxElo: maxElo,
      caption: caption,
      countSingular: countSingular,
      countPlural: countPlural,
      events: newEvents,
      formatsAndStates: formatsAndStates,
      savedAt: savedAt,
    );
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

  /// Criteria-keyed saved identity (v2). v1 embedded the event-id snapshot,
  /// which froze a saved smart event to whatever was live at save time —
  /// v2 keys the row on the criteria alone so the same saved event resolves
  /// fresh members forever. Legacy v1 rows are matched by parsed criteria
  /// (see [smartEventSavedFavoriteProvider]) and migrated on refresh.
  String get favoriteEventId => 'smart_event:v2:$criteriaKey';

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
      'events': encodeSmartEventsForMetadata(events),
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

/// The generating criteria of a smart event as a value object — the family
/// key for server-fresh member resolution.
@immutable
class SmartEventCriteria {
  SmartEventCriteria({
    required this.minElo,
    required this.maxElo,
    required Set<String> formatsAndStates,
  }) : formatsAndStates = Set<String>.unmodifiable(
         formatsAndStates
             .map((value) => value.trim().toLowerCase())
             .where((value) => value.isNotEmpty),
       );

  final int minElo;
  final int maxElo;
  final Set<String> formatsAndStates;

  String get key {
    final criteria = formatsAndStates.toList(growable: false)..sort();
    return '$minElo-$maxElo:${criteria.join('|')}';
  }

  /// Projects only event-level criteria onto the home tabs' filter state.
  /// Rating is deliberately left unfiltered here: smart-event rating tiers
  /// apply to each game's two-player average after candidate tournaments are
  /// resolved, not to a broadcast's `max_avg_elo`.
  FilterPopupState toPopupState() {
    return FilterPopupState(
      formatsAndStates: formatsAndStates,
      eloRange: const RangeValues(kFilterMinElo, kFilterMaxElo),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SmartEventCriteria &&
            other.minElo == minElo &&
            other.maxElo == maxElo &&
            setEquals(other.formatsAndStates, formatsAndStates);
  }

  @override
  int get hashCode =>
      Object.hash(minElo, maxElo, Object.hashAllUnordered(formatsAndStates));
}

/// What a smart-event games fetch counts as one of its games.
///
/// Shared by the day probe and the day fetch so they never disagree.
/// GM is "average player rating 2500 or higher" with **no** event-level
/// scoping — a floor on the event's own average (or a restriction to
/// currently-running broadcasts) silently drops qualifying games played
/// inside opens, which is what left older days showing a handful of boards.
@immutable
class SmartEventFetchScope {
  const SmartEventFetchScope({
    required this.liveOnly,
    required this.completedOnly,
    this.minGameAverageElo,
    this.maxGameAverageElo,
    this.eventTimeControls,
  });

  final bool liveOnly;
  final bool completedOnly;
  final int? minGameAverageElo;
  final int? maxGameAverageElo;
  final List<String>? eventTimeControls;
}

/// Scope of the smart collection [query] serves — same contract as desktop.
SmartEventFetchScope smartEventFetchScopeFor(SmartEventGamesQuery query) {
  final minElo = _effectiveMinAverageElo(query.request, query.filter);
  final maxElo = _effectiveMaxAverageElo(query.request, query.filter);
  final hasLowerBound = minElo > GameFilter.defaultMinRating;
  final hasUpperBound = maxElo < GameFilter.absoluteMaxRating;

  final formats = query.request.formatsAndStates;
  final filterLive = query.filter?.live ?? GameLiveFilter.all;
  final hasLive = formats.contains('live') || filterLive == GameLiveFilter.live;
  final hasCompleted =
      formats.contains('completed') ||
      filterLive == GameLiveFilter.completed;
  final liveOnly = hasLive && !hasCompleted;
  final completedOnly = hasCompleted && !hasLive;

  final timeControlTokens = <String>{
    ...formats.where((token) => timeControlBucketFor(token) != null),
  };
  switch (query.filter?.timeControl) {
    case GameTimeControlFilter.classical:
      timeControlTokens
        ..removeWhere((token) => timeControlBucketFor(token) != null)
        ..add('standard');
    case GameTimeControlFilter.rapid:
      timeControlTokens
        ..removeWhere((token) => timeControlBucketFor(token) != null)
        ..add('rapid');
    case GameTimeControlFilter.blitz:
      timeControlTokens
        ..removeWhere((token) => timeControlBucketFor(token) != null)
        ..add('blitz');
    case GameTimeControlFilter.all:
    case null:
      break;
  }

  final eventTimeControls = postgrestTimeControlValues(timeControlTokens);

  return SmartEventFetchScope(
    liveOnly: liveOnly,
    completedOnly: completedOnly,
    minGameAverageElo: hasLowerBound ? minElo : null,
    maxGameAverageElo: hasUpperBound ? maxElo : null,
    eventTimeControls:
        eventTimeControls.isEmpty
            ? null
            : eventTimeControls.toSet().toList(growable: false),
  );
}

/// SERVER-FRESH membership of a smart event: every broadcast in the server's
/// `group_broadcasts_current` view that matches the event-level criteria now.
/// Live/completed and format reuse [filterBroadcastsByPopupState]; rating is
/// intentionally deferred to each game's two-player average in the aggregate
/// pipeline so an event average can neither admit weak boards nor hide a
/// qualifying board.
///
/// Watches the strict live-id stream, so live/completed criteria (and the
/// live badges on resolved cards) re-evaluate whenever liveness changes —
/// this is what keeps a saved smart event refreshing itself while open.
final smartEventResolvedEventsProvider = FutureProvider.autoDispose
    .family<List<GroupEventCardModel>, SmartEventCriteria>((
      ref,
      criteria,
    ) async {
      List<String> liveIds;
      try {
        liveIds = await ref.watch(liveGroupBroadcastIdsProvider.future);
      } catch (_) {
        liveIds = ref.read(liveBroadcastIdsProvider);
      }

      final broadcasts =
          await ref.read(groupBroadcastRepositoryProvider)
              .getCurrentGroupBroadcasts();
      final matching = filterBroadcastsByPopupState(
        broadcasts,
        criteria.toPopupState(),
        liveIds: liveIds,
      );
      return matching
          .map((broadcast) =>
              GroupEventCardModel.fromGroupBroadcast(broadcast, liveIds))
          .toList(growable: false);
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
    this.hasMore = false,
    this.isLoadingMore = false,
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
  final bool hasMore;
  final bool isLoadingMore;

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

  SmartAggregateEvent copyWith({
    List<GamesTourModel>? games,
    int? tournamentCount,
    int? avgElo,
    int? minElo,
    List<String>? tournamentNames,
    DateTime? dateStart,
    DateTime? dateEnd,
    List<String>? timeControls,
    List<String>? pinnedGameIds,
    List<GroupEventCardModel>? events,
    Map<String, String>? gameEventNames,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return SmartAggregateEvent(
      games: games ?? this.games,
      tournamentCount: tournamentCount ?? this.tournamentCount,
      avgElo: avgElo ?? this.avgElo,
      minElo: minElo ?? this.minElo,
      tournamentNames: tournamentNames ?? this.tournamentNames,
      dateStart: dateStart ?? this.dateStart,
      dateEnd: dateEnd ?? this.dateEnd,
      timeControls: timeControls ?? this.timeControls,
      pinnedGameIds: pinnedGameIds ?? this.pinnedGameIds,
      events: events ?? this.events,
      gameEventNames: gameEventNames ?? this.gameEventNames,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// The saved favorite (if any) whose smart event matches [criteriaKey]
/// ([SmartEventRequest.criteriaKey]). Matching parses each smart favorite and
/// compares criteria — never row eventIds — so legacy v1 rows (whose ids
/// embed a frozen event-id snapshot) resolve exactly like v2 rows.
final smartEventSavedFavoriteProvider = Provider.family<FavoriteEvent?, String>(
  (ref, criteriaKey) {
    final favorites = ref.watch(favoriteEventsProvider).valueOrNull ?? const [];
    for (final favorite in favorites) {
      if (!isSmartFavoriteEvent(favorite)) continue;
      if (SmartEventRequest.fromFavoriteEvent(favorite).criteriaKey ==
          criteriaKey) {
        return favorite;
      }
    }
    return null;
  },
);

/// The `metadata.events` encoding shared by saving and snapshot refreshing.
List<Map<String, dynamic>> encodeSmartEventsForMetadata(
  List<GroupEventCardModel> events,
) {
  return events
      .map(
        (event) => <String, dynamic>{
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
      .toList(growable: false);
}

/// Rows currently being rewritten, keyed by row eventId — prevents duplicate
/// concurrent writes while a refresh is in flight (rebuilds re-enter here).
final _smartSnapshotRefreshInFlight = <String>{};

/// Sync a saved smart event's server row to its freshly resolved membership.
///
/// The favorites row (`user_favorite_events`) is the server-side home of a
/// saved smart event; its `metadata.events` snapshot exists only as an
/// offline / first-paint fallback. Whenever the resolver produces a
/// different member set, write it back so the row — and every other device
/// reading it — stays current. Legacy v1 rows (event-set-keyed ids) are
/// migrated to the criteria-keyed v2 id in the same pass.
Future<void> refreshSavedSmartEventSnapshot({
  required WidgetRef ref,
  required FavoriteEvent favorite,
  required List<GroupEventCardModel> resolvedEvents,
}) async {
  final parsed = SmartEventRequest.fromFavoriteEvent(favorite);
  final fresh = parsed.withEvents(resolvedEvents);
  final needsMigration = favorite.eventId != fresh.favoriteEventId;
  final sameEvents = listEquals(parsed.stableEventIds, fresh.stableEventIds);
  if (!needsMigration && sameEvents) return;

  if (!_smartSnapshotRefreshInFlight.add(favorite.eventId)) return;
  try {
    final notifier = ref.read(favoriteEventsProvider.notifier);
    if (needsMigration) {
      final favorites =
          ref.read(favoriteEventsProvider).valueOrNull ?? const [];
      final v2AlreadyExists = favorites.any(
        (row) => row.eventId == fresh.favoriteEventId,
      );
      await notifier.removeFavorite(favorite.eventId);
      // Duplicate legacy saves of the same criteria collapse into one v2 row.
      if (!v2AlreadyExists) {
        await notifier.addFavorite(
          eventId: fresh.favoriteEventId,
          eventName: fresh.displayName,
          maxAvgElo: fresh.minElo > 0 ? fresh.minElo : null,
          extraMetadata: {
            ...fresh.toFavoriteMetadata(),
            // Carry user-owned flags the rebuild would otherwise reset.
            'notificationsEnabled':
                favorite.metadata['notificationsEnabled'] ?? false,
          },
        );
      }
      return;
    }

    await notifier.updateMetadata(favorite.eventId, {
      'events': encodeSmartEventsForMetadata(resolvedEvents),
    });
  } catch (_) {
    // Best-effort background sync — the next resolution retries it.
  } finally {
    _smartSnapshotRefreshInFlight.remove(favorite.eventId);
  }
}

/// THE single data path for the smart event view.
///
/// Games are fetched the same way desktop GM / Live / Classical collections
/// are: globally by `game_day`, one whole day at a time, with no restriction
/// to currently-running broadcasts. First paint is the newest day; older days
/// append in the background and on scroll. Event cards for About / Standings
/// are derived from the loaded games' broadcast metadata.
final smartAggregateEventRepositoryProvider = StateNotifierProvider.autoDispose
    .family<
      SmartAggregateEventNotifier,
      AsyncValue<SmartAggregateEvent>,
      SmartEventGamesQuery
    >((ref, query) {
      return SmartAggregateEventNotifier(ref, query);
    });

class SmartAggregateEventNotifier
    extends StateNotifier<AsyncValue<SmartAggregateEvent>> {
  SmartAggregateEventNotifier(this._ref, this._query)
    : super(const AsyncValue.loading()) {
    unawaited(_initialize());
  }

  final Ref _ref;
  final SmartEventGamesQuery _query;

  DateTime? _nextDay;
  bool _cursorReady = false;
  bool _isFetching = false;
  bool _didPrefetch = false;

  /// Upper bound on days skipped in one fetch when a day survives the backend
  /// predicates but is emptied by client-side narrowing.
  static const int _maxSkippedSmartEventDays = 12;

  /// Days to pull in after first paint so Yesterday / older headers appear
  /// without waiting on a scroll. First paint itself is still one day.
  static const int _prefetchOlderDays = 6;

  Future<void> _initialize() async {
    await _fetchNextNonEmptyDay(append: false);
    if (!mounted || _didPrefetch) return;
    _didPrefetch = true;
    unawaited(_prefetch());
  }

  Future<void> _prefetch() async {
    for (var i = 0; i < _prefetchOlderDays; i++) {
      if (!mounted) return;
      final current = state.valueOrNull;
      if (current == null || !current.hasMore) return;
      await _fetchNextNonEmptyDay(append: true);
    }
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.isLoadingMore || !current.hasMore) return;
    await _fetchNextNonEmptyDay(append: true);
  }

  Future<void> _fetchNextNonEmptyDay({required bool append}) async {
    if (_isFetching) return;
    _isFetching = true;
    if (append) {
      final current = state.valueOrNull;
      if (current != null) {
        state = AsyncValue.data(current.copyWith(isLoadingMore: true));
      }
    }

    try {
      final repository = _ref.read(gameRepositoryProvider);
      final scope = smartEventFetchScopeFor(_query);
      final extraFilter = _residualSmartEventFilter(_query.filter);
      final search =
          _query.normalizedSearchQuery.isEmpty
              ? null
              : _query.normalizedSearchQuery;

      var targetDay =
          _cursorReady
              ? _nextDay
              : await repository.getCurrentSmartEventDay(
                liveOnly: scope.liveOnly,
                completedOnly: scope.completedOnly,
                minGameAverageElo: scope.minGameAverageElo,
                searchQuery: search,
                extraFilter: extraFilter,
              );
      _cursorReady = true;

      if (targetDay == null) {
        _nextDay = null;
        if (!append) {
          state = const AsyncValue.data(SmartAggregateEvent.empty);
        } else {
          final current = state.valueOrNull;
          if (current != null) {
            state = AsyncValue.data(
              current.copyWith(hasMore: false, isLoadingMore: false),
            );
          }
        }
        return;
      }

      for (var skipped = 0; skipped <= _maxSkippedSmartEventDays; skipped++) {
        final page = await repository.getCurrentSmartEventGamesOnDay(
          day: targetDay!,
          liveOnly: scope.liveOnly,
          completedOnly: scope.completedOnly,
          minGameAverageElo: scope.minGameAverageElo,
          maxGameAverageElo: scope.maxGameAverageElo,
          eventTimeControls: scope.eventTimeControls,
          searchQuery: search,
          extraFilter: extraFilter,
        );
        _nextDay = page.nextDay;

        if (page.games.isNotEmpty) {
          final liveIds = _ref.read(liveBroadcastIdsProvider);
          final dayEvent = _buildAggregateEventFromGameRows(
            request: _query.request,
            games: page.games,
            liveIds: liveIds,
            minAverageElo:
                scope.minGameAverageElo ?? GameFilter.defaultMinRating,
            maxAverageElo:
                scope.maxGameAverageElo ?? GameFilter.absoluteMaxRating,
          );
          final merged =
              append
                  ? _mergeOlderDay(
                    state.valueOrNull ?? SmartAggregateEvent.empty,
                    dayEvent,
                  )
                  : dayEvent;
          if (!mounted) return;
          state = AsyncValue.data(
            merged.copyWith(
              hasMore: page.hasMore,
              isLoadingMore: false,
            ),
          );
          return;
        }

        if (page.nextDay == null) {
          if (!append) {
            state = const AsyncValue.data(SmartAggregateEvent.empty);
          } else {
            final current = state.valueOrNull;
            if (current != null) {
              state = AsyncValue.data(
                current.copyWith(hasMore: false, isLoadingMore: false),
              );
            }
          }
          return;
        }
        targetDay = page.nextDay;
      }

      final current = state.valueOrNull;
      if (!append) {
        state = const AsyncValue.data(SmartAggregateEvent.empty);
      } else if (current != null) {
        state = AsyncValue.data(
          current.copyWith(
            hasMore: _nextDay != null,
            isLoadingMore: false,
          ),
        );
      }
    } catch (error, stackTrace) {
      if (!append) {
        state = AsyncValue.error(error, stackTrace);
      } else {
        final current = state.valueOrNull;
        if (current != null) {
          state = AsyncValue.data(current.copyWith(isLoadingMore: false));
        }
      }
    } finally {
      _isFetching = false;
    }
  }
}

/// Filters that are not already expressed as day-query scope (live / time
/// control / rating floor). Passing those through again would either double
/// apply or take the slow inner-join-on-broadcasts path.
GameFilter? _residualSmartEventFilter(GameFilter? filter) {
  if (filter == null) return null;
  final residual = filter.copyWith(
    live: GameLiveFilter.all,
    timeControl: GameTimeControlFilter.all,
    minRating: GameFilter.defaultMinRating,
    maxRating: GameFilter.absoluteMaxRating,
  );
  return residual.hasActiveFilters ? residual : null;
}

SmartAggregateEvent _mergeOlderDay(
  SmartAggregateEvent newer,
  SmartAggregateEvent older,
) {
  final seenGameIds = <String>{};
  final games = <GamesTourModel>[];
  for (final game in [...newer.games, ...older.games]) {
    if (seenGameIds.add(game.gameId)) games.add(game);
  }
  final eventsById = <String, GroupEventCardModel>{
    for (final event in newer.events) event.id: event,
    for (final event in older.events) event.id: event,
  };
  final gameEventNames = {...newer.gameEventNames, ...older.gameEventNames};
  final gameEventIds = <String, String>{};
  for (final game in games) {
    final name = gameEventNames[game.gameId];
    if (name == null) continue;
    for (final event in eventsById.values) {
      if (event.title == name) {
        gameEventIds[game.gameId] = event.id;
        break;
      }
    }
  }
  return _createSmartAggregateEvent(
    minElo: newer.minElo,
    participatingEvents: _sortEventsByAvgElo(
      eventsById.values.toList(growable: false),
      games: games,
      gameEventIds: gameEventIds,
    ),
    orderedGames: games,
    gameEventNames: gameEventNames,
    pinnedIds: const <String>[],
    hasMore: older.hasMore,
  );
}

SmartAggregateEvent _buildAggregateEventFromGameRows({
  required SmartEventRequest request,
  required List<Games> games,
  required List<String> liveIds,
  required int minAverageElo,
  required int maxAverageElo,
}) {
  final eventsById = <String, GroupEventCardModel>{};
  final gamesById = <String, GamesTourModel>{};
  final gameEventIds = <String, String>{};

  for (final game in games) {
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

    final eventId = game.groupBroadcastId ?? game.tourId;
    gameEventIds[gameModel.gameId] = eventId;
    eventsById.putIfAbsent(
      eventId,
      () => _eventCardFromGame(game, liveIds),
    );
  }

  final orderedGames = _sortSmartGames(
    gamesById.values.toList(growable: false),
    pinnedIds: const <String>[],
  );

  final gameEventNames = <String, String>{};
  for (final game in orderedGames) {
    final eventId = gameEventIds[game.gameId];
    if (eventId == null) continue;
    gameEventNames[game.gameId] = eventsById[eventId]?.title ?? eventId;
  }

  final participatingEvents = _sortEventsByAvgElo(
    eventsById.values.toList(growable: false),
    games: orderedGames,
    gameEventIds: gameEventIds,
  );

  return _createSmartAggregateEvent(
    minElo: request.minElo > kFilterMinElo ? request.minElo : null,
    participatingEvents: participatingEvents,
    orderedGames: orderedGames,
    gameEventNames: gameEventNames,
    pinnedIds: const <String>[],
  );
}

GroupEventCardModel _eventCardFromGame(Games game, List<String> liveIds) {
  final id = game.groupBroadcastId ?? game.tourId;
  return GroupEventCardModel.fromGroupBroadcast(
    GroupBroadcast(
      id: id,
      createdAt: game.eventDateStart ?? DateTime.fromMillisecondsSinceEpoch(0),
      name: game.eventName ?? game.tourName ?? id,
      search: const <String>[],
      maxAvgElo: game.eventMaxAvgElo ?? game.avgElo,
      dateStart: game.eventDateStart,
      dateEnd: game.eventDateEnd,
      timeControl: game.timeControl,
    ),
    liveIds,
  );
}

SmartAggregateEvent _createSmartAggregateEvent({
  required int? minElo,
  required List<GroupEventCardModel> participatingEvents,
  required List<GamesTourModel> orderedGames,
  required Map<String, String> gameEventNames,
  required List<String> pinnedIds,
  bool hasMore = false,
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
    minElo: minElo,
    tournamentNames: participatingEvents
        .map((event) => event.title)
        .toList(growable: false),
    dateStart: dates.isEmpty ? null : dates.first,
    dateEnd: dates.isEmpty ? null : dates.last,
    timeControls: timeControls,
    pinnedGameIds: pinnedIds,
    events: participatingEvents,
    gameEventNames: gameEventNames,
    hasMore: hasMore,
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

/// Exposes the aggregate pipeline's rating gate so the two-player-average
/// contract is pinned by a test — it has flipped between average and
/// strongest-player twice, and each flip shipped as a user-visible bug.
@visibleForTesting
bool matchesSmartEventAverageEloForTest(
  GamesTourModel game, {
  required int minAverageElo,
  required int maxAverageElo,
}) {
  return _matchesAverageEloRange(
    game,
    minAverageElo: minAverageElo,
    maxAverageElo: maxAverageElo,
  );
}

int _effectiveMinAverageElo(SmartEventRequest request, GameFilter? filter) {
  var value =
      request.hasEloRange ? request.minElo : GameFilter.defaultMinRating;
  final filterMin = filter?.minRating ?? GameFilter.defaultMinRating;
  if (filterMin > value) value = filterMin;
  return value;
}

int _effectiveMaxAverageElo(SmartEventRequest request, GameFilter? filter) {
  // The home Level chips are open-ended floors (GM 2500+). Their range end is
  // always [kFilterMaxElo], which is a UI ceiling, not a real cap — treating
  // it as one dropped 3200+ boards from every GM/IM/FM/CM collection.
  var value = GameFilter.absoluteMaxRating;
  if (request.hasEloRange && request.maxElo < kFilterMaxElo.round()) {
    value = request.maxElo;
  }
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

/// Drops the oldest day from a day-desc sorted games list. Kept for tests
/// of the old capped-fetch path; day pagination no longer produces a
/// half-fetched trailing day. A single-day list stays untouched — an empty
/// list would be worse than a partial one.
List<GamesTourModel> _trimTrailingPartialDay(List<GamesTourModel> sortedGames) {
  if (sortedGames.isEmpty) return sortedGames;
  final oldestDay = _smartGameDay(sortedGames.last);
  if (_smartGameDay(sortedGames.first) == oldestDay) return sortedGames;
  final cut =
      sortedGames.lastIndexWhere((game) => _smartGameDay(game) != oldestDay) +
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
  // `game_day` is the pagination cursor and the desktop section key. Prefer
  // it over lastMoveTime so a game that finished the next morning still
  // sits on the round it was played.
  final raw = game.gameDay ?? game.bucketDate ?? game.lastMoveTime ?? DateTime(0);
  return DateTime(raw.year, raw.month, raw.day);
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
