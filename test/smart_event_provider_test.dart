import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart'
    show filterBroadcastsByPopupState;
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart'
    show smartGameMatchesTierForTest;
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart'
    show GameFilter;
import 'package:flutter/material.dart' show RangeValues;
import 'package:flutter_test/flutter_test.dart';

PlayerCard _player(String name, int rating, {int? fideId}) {
  return PlayerCard(
    name: name,
    federation: 'USA',
    title: '',
    rating: rating,
    countryCode: 'USA',
    team: null,
    fideId: fideId,
  );
}

GamesTourModel _game({
  String id = 'game-1',
  required int whiteRating,
  required int blackRating,
  DateTime? lastMoveTime,
  int? boardNr,
}) {
  return GamesTourModel(
    gameId: id,
    whitePlayer: _player('White', whiteRating),
    blackPlayer: _player('Black', blackRating),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.ongoing,
    roundId: 'round-1',
    tourId: 'tour-1',
    lastMoveTime: lastMoveTime,
    boardNr: boardNr,
  );
}

GroupEventCardModel _event({
  required String id,
  required DateTime start,
  required DateTime end,
}) {
  return GroupEventCardModel(
    id: id,
    title: 'Event $id',
    dates: 'Jun 1 - 2, 2026',
    maxAvgElo: 2600,
    timeUntilStart: '',
    tourEventCategory: TourEventCategory.ongoing,
    timeControl: 'Standard',
    endDate: end,
    startDate: start,
  );
}

GroupBroadcast _broadcast({
  required String id,
  int? maxAvgElo,
  String? timeControl = 'Standard',
}) {
  return GroupBroadcast(
    id: id,
    createdAt: DateTime.utc(2026, 6, 1),
    name: 'Broadcast $id',
    search: const [],
    maxAvgElo: maxAvgElo,
    dateStart: DateTime.utc(2026, 6, 1),
    dateEnd: DateTime.utc(2026, 6, 5),
    timeControl: timeControl,
  );
}

SmartEventRequest _request({
  SmartEventSource source = SmartEventSource.forYou,
  int minElo = 2500,
  int maxElo = 3200,
  Set<String> formatsAndStates = const {},
  List<GroupEventCardModel> events = const [],
  DateTime? savedAt,
}) {
  return SmartEventRequest(
    source: source,
    tierLabel: 'GM',
    titleSuffix: 'Games',
    minElo: minElo,
    maxElo: maxElo,
    caption: 'From your $minElo+ filter',
    countSingular: 'event',
    countPlural: 'events',
    events: events,
    formatsAndStates: formatsAndStates,
    savedAt: savedAt,
  );
}

Map<String, dynamic> _favoriteEventMetadataRow(GroupEventCardModel event) {
  return {
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
  };
}

void main() {
  group('criteria-keyed identity', () {
    test('favoriteEventId is independent of the resolved event set', () {
      final eventA = _event(
        id: 'event-a',
        start: DateTime.utc(2026, 6, 1),
        end: DateTime.utc(2026, 6, 2),
      );
      final eventB = _event(
        id: 'event-b',
        start: DateTime.utc(2026, 6, 1),
        end: DateTime.utc(2026, 6, 2),
      );

      final snapshotOne = _request(events: [eventA]);
      final snapshotTwo = _request(events: [eventA, eventB]);

      // The whole point of v2: refreshing membership must not change the
      // saved identity, or a saved event could never update itself.
      expect(snapshotOne.favoriteEventId, snapshotTwo.favoriteEventId);
      expect(snapshotOne.favoriteEventId, startsWith('smart_event:v2:'));
    });

    test('favoriteEventId is independent of the generating tab', () {
      final forYou = _request(source: SmartEventSource.forYou);
      final current = _request(source: SmartEventSource.current);

      expect(forYou.favoriteEventId, current.favoriteEventId);
    });

    test('criteria changes produce distinct identities', () {
      expect(
        _request(minElo: 2500).favoriteEventId,
        isNot(_request(minElo: 2400).favoriteEventId),
      );
      expect(
        _request(formatsAndStates: {'blitz'}).favoriteEventId,
        isNot(_request(formatsAndStates: {'rapid'}).favoriteEventId),
      );
    });

    test('legacy v1 rows parse to the same criteriaKey as fresh requests', () {
      final event = _event(
        id: 'event-a',
        start: DateTime.utc(2026, 6, 1),
        end: DateTime.utc(2026, 6, 2),
      );
      final legacy = FavoriteEvent(
        id: 'favorite-1',
        userId: 'user-1',
        // v1 identity embedded the event-id snapshot.
        eventId: 'smart_event:forYou:2500-3200:event-a',
        eventName: 'GM Games',
        metadata: {
          'type': 'smart_event',
          'source': 'forYou',
          'tierLabel': 'GM',
          'titleSuffix': 'Games',
          'minElo': 2500,
          'maxElo': 3200,
          'caption': 'From your 2500+ filter',
          'countSingular': 'event',
          'countPlural': 'events',
          'events': [_favoriteEventMetadataRow(event)],
        },
        createdAt: DateTime.utc(2026, 6, 3),
        updatedAt: DateTime.utc(2026, 6, 3),
      );

      final parsed = SmartEventRequest.fromFavoriteEvent(legacy);

      expect(parsed.criteriaKey, _request(minElo: 2500).criteriaKey);
      // And the row is recognized as needing migration to v2.
      expect(parsed.favoriteEventId, isNot(legacy.eventId));
    });

    test('withEvents swaps membership without touching identity', () {
      final saved = _request(
        events: [
          _event(
            id: 'stale',
            start: DateTime.utc(2026, 6, 1),
            end: DateTime.utc(2026, 6, 2),
          ),
        ],
        savedAt: DateTime.utc(2026, 6, 3),
      );
      final refreshed = saved.withEvents([
        _event(
          id: 'fresh',
          start: DateTime.utc(2026, 7, 1),
          end: DateTime.utc(2026, 7, 2),
        ),
      ]);

      expect(refreshed.favoriteEventId, saved.favoriteEventId);
      expect(refreshed.savedAt, saved.savedAt);
      expect(refreshed.events.single.id, 'fresh');
    });
  });

  group('filterBroadcastsByPopupState (smart event resolver semantics)', () {
    test('elo floor keeps qualifying and null-rated broadcasts', () {
      final filtered = filterBroadcastsByPopupState(
        [
          _broadcast(id: 'strong', maxAvgElo: 2600),
          _broadcast(id: 'weak', maxAvgElo: 2100),
          _broadcast(id: 'unrated', maxAvgElo: null),
        ],
        const FilterPopupState(
          formatsAndStates: {},
          eloRange: RangeValues(2500, kFilterMaxElo),
        ),
        liveIds: const [],
      );

      expect(filtered.map((b) => b.id), ['strong', 'unrated']);
    });

    test('live/completed statuses test against the live-id list', () {
      final broadcasts = [
        _broadcast(id: 'live-one', maxAvgElo: 2600),
        _broadcast(id: 'finished', maxAvgElo: 2600),
      ];

      final liveOnly = filterBroadcastsByPopupState(
        broadcasts,
        const FilterPopupState(
          formatsAndStates: {'live'},
          eloRange: RangeValues(kFilterMinElo, kFilterMaxElo),
        ),
        liveIds: const ['live-one'],
      );
      final completedOnly = filterBroadcastsByPopupState(
        broadcasts,
        const FilterPopupState(
          formatsAndStates: {'completed'},
          eloRange: RangeValues(kFilterMinElo, kFilterMaxElo),
        ),
        liveIds: const ['live-one'],
      );

      expect(liveOnly.map((b) => b.id), ['live-one']);
      expect(completedOnly.map((b) => b.id), ['finished']);
    });

    test('format criteria test the broadcast time control', () {
      final filtered = filterBroadcastsByPopupState(
        [
          _broadcast(id: 'blitz-one', timeControl: 'Blitz'),
          _broadcast(id: 'classical', timeControl: 'Standard'),
          _broadcast(id: 'unknown', timeControl: null),
        ],
        const FilterPopupState(
          formatsAndStates: {'blitz'},
          eloRange: RangeValues(kFilterMinElo, kFilterMaxElo),
        ),
        liveIds: const [],
      );

      expect(filtered.map((b) => b.id), ['blitz-one']);
    });

    test('event membership ignores Elo because rating belongs to games', () {
      final criteria = SmartEventCriteria(
        minElo: 2500,
        maxElo: 3200,
        formatsAndStates: const {'blitz'},
      );
      final state = criteria.toPopupState();

      expect(state.formatsAndStates, {'blitz'});
      expect(state.minElo, isNull);
      expect(state.hasEloFilter, isFalse);
    });
  });

  group('smartGameAverageElo', () {
    test('uses individual game average instead of event average', () {
      expect(
        smartGameAverageElo(_game(whiteRating: 2600, blackRating: 2400)),
        2500,
      );
    });

    test('keeps reported sub-2500 GM boards below the threshold', () {
      expect(
        smartGameAverageElo(_game(whiteRating: 2591, blackRating: 2371)),
        2481,
      );
      expect(
        smartGameAverageElo(_game(whiteRating: 2521, blackRating: 2440)),
        2481,
      );
    });

    test('falls back to available player rating when one side is missing', () {
      expect(
        smartGameAverageElo(_game(whiteRating: 2600, blackRating: 0)),
        2600,
      );
    });
  });

  group('rating tiers gate on the game average', () {
    // The exact boards from the report: a 2500+ player on the board is NOT
    // enough — the two-player average decides.
    final reportedGmBoards = [
      _game(id: 'gm-1', whiteRating: 2591, blackRating: 2371),
      _game(id: 'gm-2', whiteRating: 2521, blackRating: 2440),
    ];

    test('GM+ excludes strong-player boards whose average is below 2500', () {
      for (final game in reportedGmBoards) {
        expect(smartGameMatchesTierForTest(game, 'GM'), isFalse);
        expect(
          matchesSmartEventAverageEloForTest(
            game,
            minAverageElo: 2500,
            maxAverageElo: GameFilter.absoluteMaxRating,
          ),
          isFalse,
        );
      }
    });

    test('GM+ keeps a board whose average lands exactly on the floor', () {
      final onFloor = _game(whiteRating: 2560, blackRating: 2440);
      expect(smartGameMatchesTierForTest(onFloor, 'GM'), isTrue);
      expect(
        matchesSmartEventAverageEloForTest(
          onFloor,
          minAverageElo: 2500,
          maxAverageElo: GameFilter.absoluteMaxRating,
        ),
        isTrue,
      );
    });

    test('every tier is an open-ended floor on the same scalar', () {
      // Average 2350: clears CM (2200) and FM (2300), misses IM (2400) and GM.
      final game = _game(whiteRating: 2400, blackRating: 2300);
      expect(smartGameMatchesTierForTest(game, 'CM'), isTrue);
      expect(smartGameMatchesTierForTest(game, 'FM'), isTrue);
      expect(smartGameMatchesTierForTest(game, 'IM'), isFalse);
      expect(smartGameMatchesTierForTest(game, 'GM'), isFalse);
      expect(smartGameMatchesTierForTest(game, 'All'), isTrue);
    });

    test('an unrated board never satisfies an active floor', () {
      final unrated = _game(whiteRating: 0, blackRating: 0);
      expect(smartGameMatchesTierForTest(unrated, 'CM'), isFalse);
      expect(
        matchesSmartEventAverageEloForTest(
          unrated,
          minAverageElo: 2200,
          maxAverageElo: GameFilter.absoluteMaxRating,
        ),
        isFalse,
      );
    });

    test('a neutral band admits everything, including unrated boards', () {
      expect(
        matchesSmartEventAverageEloForTest(
          _game(whiteRating: 0, blackRating: 0),
          minAverageElo: GameFilter.defaultMinRating,
          maxAverageElo: GameFilter.absoluteMaxRating,
        ),
        isTrue,
      );
    });
  });

  group('sortSmartGamesForTest', () {
    test('groups by day, then pinned first, then average rating', () {
      final today = DateTime(2026, 6, 9, 12);
      final yesterday = DateTime(2026, 6, 8, 12);
      final games = [
        _game(
          id: 'older-high',
          whiteRating: 2800,
          blackRating: 2800,
          lastMoveTime: yesterday,
        ),
        _game(
          id: 'today-low',
          whiteRating: 2300,
          blackRating: 2300,
          lastMoveTime: today,
        ),
        _game(
          id: 'older-pinned-low',
          whiteRating: 2200,
          blackRating: 2200,
          lastMoveTime: yesterday,
        ),
        _game(
          id: 'today-pinned-low',
          whiteRating: 2200,
          blackRating: 2200,
          lastMoveTime: today,
        ),
        _game(
          id: 'today-high',
          whiteRating: 2600,
          blackRating: 2600,
          lastMoveTime: today,
        ),
      ];

      final sorted = sortSmartGamesForTest(
        games,
        pinnedIds: ['today-pinned-low', 'older-pinned-low'],
      );

      expect(sorted.map((game) => game.gameId), [
        'today-pinned-low',
        'today-high',
        'today-low',
        'older-pinned-low',
        'older-high',
      ]);
    });
  });

  group('trimTrailingPartialDayForTest', () {
    test('drops the oldest day when the fetch was truncated', () {
      final games = [
        _game(
          id: 'today-a',
          whiteRating: 2600,
          blackRating: 2600,
          lastMoveTime: DateTime(2026, 6, 10, 14),
        ),
        _game(
          id: 'today-b',
          whiteRating: 2500,
          blackRating: 2500,
          lastMoveTime: DateTime(2026, 6, 10, 9),
        ),
        _game(
          id: 'oldest-partial',
          whiteRating: 2700,
          blackRating: 2700,
          lastMoveTime: DateTime(2026, 6, 9, 18),
        ),
      ];

      final trimmed = trimTrailingPartialDayForTest(games);

      expect(trimmed.map((game) => game.gameId), ['today-a', 'today-b']);
    });

    test('keeps everything when only one day was fetched', () {
      final games = [
        _game(
          id: 'a',
          whiteRating: 2600,
          blackRating: 2600,
          lastMoveTime: DateTime(2026, 6, 10, 14),
        ),
        _game(
          id: 'b',
          whiteRating: 2500,
          blackRating: 2500,
          lastMoveTime: DateTime(2026, 6, 10, 9),
        ),
      ];

      expect(trimTrailingPartialDayForTest(games).map((game) => game.gameId), [
        'a',
        'b',
      ]);
    });

    test('returns empty list unchanged', () {
      expect(trimTrailingPartialDayForTest(const []), isEmpty);
    });
  });

  group('SmartEventRequest favorite metadata', () {
    test('round-trips saved level games through favorite metadata', () {
      final event = _event(
        id: 'event-a',
        start: DateTime.utc(2026, 6, 1),
        end: DateTime.utc(2026, 6, 2),
      );
      final request = _request(
        events: [event],
        savedAt: DateTime.utc(2026, 6, 3),
      );
      final favorite = FavoriteEvent(
        id: 'favorite-1',
        userId: 'user-1',
        eventId: request.favoriteEventId,
        eventName: request.displayName,
        metadata: request.toFavoriteMetadata(),
        createdAt: DateTime.utc(2026, 6, 3),
        updatedAt: DateTime.utc(2026, 6, 3),
      );

      final restored = SmartEventRequest.fromFavoriteEvent(favorite);

      expect(restored.favoriteEventId, request.favoriteEventId);
      expect(restored.minElo, 2500);
      expect(restored.maxElo, 3200);
      expect(restored.events.single.id, 'event-a');
      expect(restored.displayName, 'GM Games');
      expect(restored.caption, 'From your 2500+ filter');
      expect(restored.countSingular, 'event');
      expect(restored.countPlural, 'events');
    });

    test('heals legacy live-games count labels on restore', () {
      final event = _event(
        id: 'event-a',
        start: DateTime.utc(2026, 6, 1),
        end: DateTime.utc(2026, 6, 2),
      );
      final favorite = FavoriteEvent(
        id: 'favorite-1',
        userId: 'user-1',
        eventId: 'smart_event:forYou:0-3200:event-a',
        eventName: 'Live Games',
        metadata: {
          'type': 'smart_event',
          'source': 'forYou',
          'tierLabel': 'Live',
          'titleSuffix': 'Games',
          'minElo': 0,
          'maxElo': 3200,
          'caption': 'From your filters',
          'countSingular': 'live event',
          'countPlural': 'live events',
          'events': [_favoriteEventMetadataRow(event)],
        },
        createdAt: DateTime.utc(2026, 6, 3),
        updatedAt: DateTime.utc(2026, 6, 3),
      );

      final restored = SmartEventRequest.fromFavoriteEvent(favorite);

      expect(restored.displayName, 'Live Games');
      expect(restored.caption, 'From your filters');
      // Smart events aggregate every event in Current, live or not — the
      // legacy "live event(s)" labels are rewritten on restore.
      expect(restored.countSingular, 'event');
      expect(restored.countPlural, 'events');
    });
  });
}
