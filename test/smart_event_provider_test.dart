import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart'
    show filterBroadcastsByPopupState;
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart'
    show smartEventTabLabels, smartGameMatchesTierForTest;
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart'
    show GameEcoFilter, GameFilter, GameLiveFilter, GameTimeControlFilter;
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
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
  DateTime? gameDay,
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
    gameDay: gameDay,
    boardNr: boardNr,
  );
}

GroupEventCardModel _event({
  required String id,
  required DateTime start,
  required DateTime end,
  String? title,
  int maxAvgElo = 2600,
}) {
  return GroupEventCardModel(
    id: id,
    title: title ?? 'Event $id',
    dates: 'Jun 1 - 2, 2026',
    maxAvgElo: maxAvgElo,
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
  GameEcoFilter? eco,
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
    eco: eco,
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
  test('smart event tabs expose Events instead of Standings', () {
    expect(smartEventTabLabels, ['About', 'Games', 'Events']);
  });

  test('smart event groups use exact IDs and newest event datetime first', () {
    final olderStart = DateTime.utc(2026, 8, 20, 10);
    final newerStart = DateTime.utc(2026, 8, 21, 10);
    final eventA = _event(
      id: 'event-a',
      title: 'Shared title',
      start: newerStart,
      end: newerStart.add(const Duration(hours: 8)),
    );
    final eventB = _event(
      id: 'event-b',
      title: 'Shared title',
      start: olderStart,
      end: olderStart.add(const Duration(hours: 8)),
    );
    final gameA1 = _game(id: 'a-1', whiteRating: 2500, blackRating: 2500);
    final gameA2 = _game(id: 'a-2', whiteRating: 2600, blackRating: 2600);
    final gameB = _game(id: 'b-1', whiteRating: 2700, blackRating: 2700);
    final aggregate = SmartAggregateEvent.empty.copyWith(
      events: [eventB, eventA],
      games: [gameA2, gameB, gameA1],
      gameEventNames: const {
        'a-1': 'Shared title',
        'a-2': 'Shared title',
        'b-1': 'Shared title',
      },
      gameEventIds: const {
        'a-1': 'event-a',
        'a-2': 'event-a',
        'b-1': 'event-b',
      },
    );

    final groups = groupSmartEventGames(
      event: aggregate,
      visibleGames: [gameA2, gameB, gameA1],
    );

    expect(groups.map((group) => group.event.id), ['event-a', 'event-b']);
    expect(groups[0].games.map((game) => game.gameId), ['a-2', 'a-1']);
    expect(groups[1].games.map((game) => game.gameId), ['b-1']);
  });

  test('event average Elo breaks equal-datetime grouping ties', () {
    final start = DateTime.utc(2026, 8, 21, 10);
    final lower = _event(
      id: 'lower',
      start: start,
      end: start.add(const Duration(hours: 8)),
      maxAvgElo: 2450,
    );
    final higher = _event(
      id: 'higher',
      start: start,
      end: start.add(const Duration(hours: 8)),
      maxAvgElo: 2750,
    );
    final lowerGame = _game(
      id: 'lower-game',
      whiteRating: 2450,
      blackRating: 2450,
    );
    final higherGame = _game(
      id: 'higher-game',
      whiteRating: 2750,
      blackRating: 2750,
    );
    final aggregate = SmartAggregateEvent.empty.copyWith(
      events: [lower, higher],
      games: [lowerGame, higherGame],
      gameEventIds: const {'lower-game': 'lower', 'higher-game': 'higher'},
    );

    final groups = groupSmartEventGames(
      event: aggregate,
      visibleGames: aggregate.games,
    );

    expect(groups.map((group) => group.event.id), ['higher', 'lower']);
  });

  test('opening search creates a global family smart-event request', () {
    final request = SmartEventRequest.forOpening(GameEcoFilter.forFamily('B9'));

    expect(request.displayName, 'Sicilian: Najdorf');
    expect(request.eco.code, 'B9');
    expect(request.events, isEmpty);
    expect(request.minElo, 0);
    expect(request.maxElo, 3200);
    expect(request.seedGameFilter().eco.code, 'B9');
    expect(request.openingExplanation?.codeLabel, 'B90-B99');
    expect(request.openingExplanation?.scope, contains('all 10 ECO codes'));
    expect(request.openingExplanation?.scope, contains('main line'));
  });

  test('named-line smart events explain and persist their ECO scope', () {
    final suggestion = searchOpeningSuggestions(
      'Gurgen',
    ).firstWhere((result) => result.subtitle == 'Gurgenidze variation');
    final request = SmartEventRequest.forOpeningSelection(suggestion.selection);
    final explanation = request.openingExplanation!;

    expect(request.eco.code, 'B06');
    expect(explanation.title, contains('Gurgenidze variation'));
    expect(explanation.scope, contains('classified as ECO B06'));
    expect(
      explanation.classificationNote,
      contains('sibling named variations'),
    );
    expect(explanation.classificationNote, contains('ECO classification'));
    expect(explanation.moves, isNotEmpty);

    final metadata = request.toFavoriteMetadata();
    final restored = SmartEventRequest.fromFavoriteEvent(
      FavoriteEvent(
        id: 'favorite-gurgenidze',
        userId: 'user-1',
        eventId: request.favoriteEventId,
        eventName: request.displayName,
        metadata: metadata,
        createdAt: DateTime.utc(2026, 8, 22),
        updatedAt: DateTime.utc(2026, 8, 22),
      ),
    );

    expect(restored.openingContext, request.openingContext);
    expect(restored.openingExplanation?.title, explanation.title);
    expect(restored.openingExplanation?.moves, explanation.moves);
  });

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
      expect(
        _request(eco: GameEcoFilter.forFamily('B9')).favoriteEventId,
        isNot(_request().favoriteEventId),
      );
      expect(
        _request(eco: GameEcoFilter.forFamily('B9')).favoriteEventId,
        isNot(_request(eco: GameEcoFilter.forCode('B90')).favoriteEventId),
      );
    });

    test('non-opening criteria keep their exact legacy v2 key', () {
      expect(_request().criteriaKey, '2500-3200:');
      expect(
        _request(formatsAndStates: {'blitz'}).criteriaKey,
        '2500-3200:blitz',
      );
    });

    test('opening criteria seed, serialize, and restore the ECO prefix', () {
      final request = _request(
        minElo: 0,
        maxElo: 3200,
        eco: GameEcoFilter.forFamily('B9'),
      );
      final metadata = request.toFavoriteMetadata();
      final favorite = FavoriteEvent(
        id: 'favorite-eco',
        userId: 'user-1',
        eventId: request.favoriteEventId,
        eventName: request.displayName,
        metadata: metadata,
        createdAt: DateTime.utc(2026, 8, 21),
        updatedAt: DateTime.utc(2026, 8, 21),
      );

      expect(request.seedGameFilter().eco.code, 'B9');
      expect(request.criteriaKey, endsWith(':eco=B9'));
      expect(metadata['ecoCode'], 'B9');
      expect(SmartEventRequest.fromFavoriteEvent(favorite).eco.code, 'B9');
    });

    test("complete King's Indian family survives saved-event restoration", () {
      final request = SmartEventRequest.forOpening(
        GameEcoFilter.forFamily('E6+E7+E8+E9'),
      );
      final metadata = request.toFavoriteMetadata();
      final favorite = FavoriteEvent(
        id: 'favorite-kings-indian',
        userId: 'user-1',
        eventId: request.favoriteEventId,
        eventName: request.displayName,
        metadata: metadata,
        createdAt: DateTime.utc(2026, 8, 21),
        updatedAt: DateTime.utc(2026, 8, 21),
      );

      final restored = SmartEventRequest.fromFavoriteEvent(favorite);

      expect(request.displayName, "King's Indian");
      expect(request.caption, "From your King's Indian opening filter");
      expect(metadata['ecoCode'], 'E6+E7+E8+E9');
      expect(restored.eco.code, 'E6+E7+E8+E9');
      expect(restored.eco.ecoPrefixes, ['E6', 'E7', 'E8', 'E9']);
      expect(restored.seedGameFilter().eco, restored.eco);
    });

    test('opening criteria reach queries that do not pass a tab filter', () {
      final residual = smartEventResidualFilterForTest(
        null,
        requestEco: GameEcoFilter.forFamily('B9'),
      );

      expect(residual, isNotNull);
      expect(residual!.eco.code, 'B9');
      expect(residual.live, GameLiveFilter.all);
      expect(residual.timeControl, GameTimeControlFilter.all);
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
    test('an opening-only home filter creates an opening smart event', () {
      final data = SmartEventCardData.fromState(
        filter: FilterPopupState(
          formatsAndStates: const {},
          eloRange: const RangeValues(kFilterMinElo, kFilterMaxElo),
          eco: GameEcoFilter.forFamily('B9'),
        ),
        events: [
          _event(
            id: 'event-a',
            start: DateTime.utc(2026, 8, 21),
            end: DateTime.utc(2026, 8, 22),
          ),
        ],
        source: SmartEventSource.forYou,
      );

      expect(data, isNotNull);
      expect(data!.request.eco.code, 'B9');
      expect(data.request.displayName, 'Sicilian: Najdorf');
      expect(data.request.seedGameFilter().eco.code, 'B9');
    });

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

    test('Classical chip matches events tagged classical', () {
      final filtered = filterBroadcastsByPopupState(
        [
          _broadcast(id: 'classical-db', timeControl: 'classical'),
          _broadcast(id: 'standard-db', timeControl: 'Standard'),
          _broadcast(id: 'blitz-db', timeControl: 'Blitz'),
        ],
        const FilterPopupState(
          formatsAndStates: {'standard'},
          eloRange: RangeValues(kFilterMinElo, kFilterMaxElo),
        ),
        liveIds: const [],
      );

      expect(filtered.map((b) => b.id), ['classical-db', 'standard-db']);
    });

    test('Blitz chip matches bullet events', () {
      final filtered = filterBroadcastsByPopupState(
        [
          _broadcast(id: 'bullet', timeControl: 'bullet'),
          _broadcast(id: 'blitz', timeControl: 'Blitz'),
          _broadcast(id: 'rapid', timeControl: 'Rapid'),
          _broadcast(id: 'unknown', timeControl: null),
        ],
        const FilterPopupState(
          formatsAndStates: {'blitz'},
          eloRange: RangeValues(kFilterMinElo, kFilterMaxElo),
        ),
        liveIds: const [],
      );

      expect(filtered.map((b) => b.id), ['bullet', 'blitz']);
    });

    test('every Time Control chip keeps unknown-control broadcasts', () {
      final filtered = filterBroadcastsByPopupState(
        [
          _broadcast(id: 'unknown', timeControl: null),
          _broadcast(id: 'blitz', timeControl: 'Blitz'),
        ],
        const FilterPopupState(
          formatsAndStates: {'standard', 'rapid', 'blitz'},
          eloRange: RangeValues(kFilterMinElo, kFilterMaxElo),
        ),
        liveIds: const [],
      );

      expect(filtered.map((b) => b.id), ['unknown', 'blitz']);
    });

    test(
      'Live+Completed together is every event, not an empty intersection',
      () {
        final filtered = filterBroadcastsByPopupState(
          [
            _broadcast(id: 'live-one', maxAvgElo: 2600),
            _broadcast(id: 'finished', maxAvgElo: 2600),
          ],
          const FilterPopupState(
            formatsAndStates: {'live', 'completed'},
            eloRange: RangeValues(kFilterMinElo, kFilterMaxElo),
          ),
          liveIds: const ['live-one'],
        );

        expect(filtered.map((b) => b.id), ['live-one', 'finished']);
      },
    );

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

  group('smart event fetch scope matches desktop', () {
    test('GM is decided per game, with no event-level tour list', () {
      // Scoping GM to currently-running broadcasts (or to events whose own
      // average clears 2500) drops qualifying games played inside opens —
      // desktop showed 160 boards on 11 Aug 2026 while mobile showed 59.
      final scope = smartEventFetchScopeFor(
        SmartEventGamesQuery(
          request: _request().withNeutralEloRange(),
          filter: GameFilter(minRating: 2500),
        ),
      );

      expect(scope.minGameAverageElo, 2500);
      expect(scope.eventTimeControls, isNull);
      expect(scope.liveOnly, isFalse);
      expect(scope.completedOnly, isFalse);
    });

    test('Classical carries both spellings of the event time control', () {
      final scope = smartEventFetchScopeFor(
        SmartEventGamesQuery(
          request: _request(
            minElo: 0,
            maxElo: 3500,
            formatsAndStates: const {'standard'},
          ),
        ),
      );

      expect(scope.minGameAverageElo, isNull);
      expect(
        scope.eventTimeControls,
        containsAll(<String>['standard', 'classical', 'Standard', 'Classical']),
      );
    });

    test('Blitz carries bullet so a Blitz chip does not drop bullet tours', () {
      final scope = smartEventFetchScopeFor(
        SmartEventGamesQuery(
          request: _request(
            minElo: 0,
            maxElo: 3500,
            formatsAndStates: const {'blitz'},
          ),
        ),
      );

      expect(
        scope.eventTimeControls,
        containsAll(<String>['blitz', 'Blitz', 'bullet', 'Bullet']),
      );
    });

    test('all three Time Control chips skip event-level tour scoping', () {
      final scope = smartEventFetchScopeFor(
        SmartEventGamesQuery(
          request: _request(
            minElo: 0,
            maxElo: 3500,
            formatsAndStates: const {'standard', 'rapid', 'blitz'},
          ),
        ),
      );

      expect(scope.eventTimeControls, isNull);
    });

    test('Live+Completed is every game, not live-only or completed-only', () {
      final scope = smartEventFetchScopeFor(
        SmartEventGamesQuery(
          request: _request(
            minElo: 0,
            maxElo: 3500,
            formatsAndStates: const {'live', 'completed'},
          ),
        ),
      );

      expect(scope.liveOnly, isFalse);
      expect(scope.completedOnly, isFalse);
    });

    test('Completed is the only collection restricted to finished games', () {
      final completed = smartEventFetchScopeFor(
        SmartEventGamesQuery(
          request: _request(
            minElo: 0,
            maxElo: 3500,
            formatsAndStates: const {'completed'},
          ),
        ),
      );

      expect(completed.completedOnly, isTrue);
      expect(completed.liveOnly, isFalse);
    });

    test('home GM 2500–3200 is an open floor, not a 3200 ceiling', () {
      final scope = smartEventFetchScopeFor(
        SmartEventGamesQuery(request: _request(minElo: 2500, maxElo: 3200)),
      );

      expect(scope.minGameAverageElo, 2500);
      expect(scope.maxGameAverageElo, isNull);
    });

    test('every Level chip is the matching open floor', () {
      expect(
        smartEventFetchScopeFor(
          SmartEventGamesQuery(request: _request(minElo: 2400, maxElo: 3200)),
        ).minGameAverageElo,
        2400,
      );
      expect(
        smartEventFetchScopeFor(
          SmartEventGamesQuery(request: _request(minElo: 2300, maxElo: 3200)),
        ).minGameAverageElo,
        2300,
      );
      expect(
        smartEventFetchScopeFor(
          SmartEventGamesQuery(request: _request(minElo: 2200, maxElo: 3200)),
        ).minGameAverageElo,
        2200,
      );
    });

    test('Live + Blitz + GM compose without dropping any dimension', () {
      final scope = smartEventFetchScopeFor(
        SmartEventGamesQuery(
          request: _request(
            minElo: 2500,
            maxElo: 3200,
            formatsAndStates: const {'live', 'blitz'},
          ),
        ),
      );

      expect(scope.liveOnly, isTrue);
      expect(scope.completedOnly, isFalse);
      expect(scope.minGameAverageElo, 2500);
      expect(scope.maxGameAverageElo, isNull);
      expect(scope.eventTimeControls, contains('blitz'));
      expect(scope.eventTimeControls, contains('bullet'));
    });

    test(
      'Completed + Classical + IM compose without dropping any dimension',
      () {
        final scope = smartEventFetchScopeFor(
          SmartEventGamesQuery(
            request: _request(
              minElo: 2400,
              maxElo: 3200,
              formatsAndStates: const {'completed', 'standard'},
            ),
          ),
        );

        expect(scope.liveOnly, isFalse);
        expect(scope.completedOnly, isTrue);
        expect(scope.minGameAverageElo, 2400);
        expect(
          scope.eventTimeControls,
          containsAll(<String>['standard', 'classical']),
        );
      },
    );

    test('every status × time-control × level combination composes', () {
      const statuses = <Set<String>>[
        {},
        {'live'},
        {'completed'},
        {'live', 'completed'},
      ];
      const timeControls = <Set<String>>[
        {},
        {'standard'},
        {'rapid'},
        {'blitz'},
        {'blitz', 'rapid'},
        {'standard', 'rapid', 'blitz'},
      ];
      const levels = <int>[0, 2200, 2300, 2400, 2500];

      for (final status in statuses) {
        for (final tc in timeControls) {
          for (final floor in levels) {
            final label = 'status=$status tc=$tc floor=$floor';
            final scope = smartEventFetchScopeFor(
              SmartEventGamesQuery(
                request: _request(
                  minElo: floor,
                  maxElo: 3200,
                  formatsAndStates: {...status, ...tc},
                ),
              ),
            );
            final hasLive = status.contains('live');
            final hasCompleted = status.contains('completed');
            expect(scope.liveOnly, hasLive && !hasCompleted, reason: label);
            expect(
              scope.completedOnly,
              hasCompleted && !hasLive,
              reason: label,
            );
            expect(
              scope.minGameAverageElo,
              floor == 0 ? isNull : floor,
              reason: label,
            );
            expect(scope.maxGameAverageElo, isNull, reason: label);
            if (tc.isEmpty || tc.length == 3) {
              expect(scope.eventTimeControls, isNull, reason: label);
            } else {
              expect(scope.eventTimeControls, isNotNull, reason: label);
            }
          }
        }
      }
    });

    test('Live is the only collection restricted to running games', () {
      final live = smartEventFetchScopeFor(
        SmartEventGamesQuery(
          request: _request(
            minElo: 0,
            maxElo: 3500,
            formatsAndStates: const {'live'},
          ),
        ),
      );
      final gm = smartEventFetchScopeFor(
        SmartEventGamesQuery(request: _request()),
      );

      expect(live.liveOnly, isTrue);
      expect(gm.liveOnly, isFalse);
    });
  });

  group('smart event day grouping', () {
    test('buckets by game_day even when lastMoveTime is the next morning', () {
      final sorted = sortSmartGamesForTest([
        _game(
          id: 'aug11-finished-late',
          whiteRating: 2600,
          blackRating: 2600,
          gameDay: DateTime(2026, 8, 11),
          lastMoveTime: DateTime(2026, 8, 12, 2),
        ),
        _game(
          id: 'aug12',
          whiteRating: 2550,
          blackRating: 2550,
          gameDay: DateTime(2026, 8, 12),
          lastMoveTime: DateTime(2026, 8, 12, 18),
        ),
      ], pinnedIds: const []);

      expect(sorted.map((game) => game.gameId), [
        'aug12',
        'aug11-finished-late',
      ]);
    });
  });
}
