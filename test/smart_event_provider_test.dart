import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
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
  group('smartGameAverageElo', () {
    test('uses individual game average instead of event average', () {
      expect(
        smartGameAverageElo(_game(whiteRating: 2600, blackRating: 2400)),
        2500,
      );
    });

    test('falls back to available player rating when one side is missing', () {
      expect(
        smartGameAverageElo(_game(whiteRating: 2600, blackRating: 0)),
        2600,
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

  group('SmartEventRequest favorite metadata', () {
    test('round-trips saved level games through favorite metadata', () {
      final event = _event(
        id: 'event-a',
        start: DateTime.utc(2026, 6, 1),
        end: DateTime.utc(2026, 6, 2),
      );
      final request = SmartEventRequest(
        source: SmartEventSource.forYou,
        tierLabel: 'GM',
        titleSuffix: 'Games',
        minElo: 2500,
        maxElo: 3200,
        caption: 'From your 2500+ filter',
        countSingular: 'event',
        countPlural: 'events',
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

    test(
      'reports saved level games finished when all events are completed',
      () {
        final now = DateTime.now();
        final request = SmartEventRequest(
          source: SmartEventSource.forYou,
          tierLabel: 'GM',
          titleSuffix: 'Games',
          minElo: 2500,
          maxElo: 3200,
          caption: 'Saved',
          countSingular: 'event',
          countPlural: 'events',
          events: [
            _event(
              id: 'old',
              start: now.subtract(const Duration(days: 4)),
              end: now.subtract(const Duration(days: 2)),
            ),
          ],
        );

        expect(
          smartEventHasUnfinishedEvents(request, const <String>[]),
          isFalse,
        );
      },
    );

    test('reports saved level games inactive when no event is current', () {
      final now = DateTime.now();
      final request = SmartEventRequest(
        source: SmartEventSource.current,
        tierLabel: 'GM',
        titleSuffix: 'Games',
        minElo: 2500,
        maxElo: 3200,
        caption: 'Saved',
        countSingular: 'event',
        countPlural: 'events',
        events: [
          _event(
            id: 'old-current-event',
            start: now.subtract(const Duration(days: 1)),
            end: now.add(const Duration(days: 1)),
          ),
        ],
      );

      expect(smartEventHasCurrentEvents(request, const <String>{}), isFalse);
      expect(
        smartEventHasCurrentEvents(request, {'different-current-event'}),
        isFalse,
      );
      expect(
        smartEventHasCurrentEvents(request, {'old-current-event'}),
        isTrue,
      );
    });
  });
}
