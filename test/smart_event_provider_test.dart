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
  String gameId = 'game-1',
  required int whiteRating,
  required int blackRating,
  int? boardNr,
  DateTime? gameDay,
}) {
  return GamesTourModel(
    gameId: gameId,
    whitePlayer: _player('White', whiteRating),
    blackPlayer: _player('Black', blackRating),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.ongoing,
    roundId: 'round-1',
    tourId: 'tour-1',
    boardNr: boardNr,
    gameDay: gameDay,
  );
}

GroupEventCardModel _event({
  required String id,
  required DateTime start,
  required DateTime end,
  int maxAvgElo = 2600,
}) {
  return GroupEventCardModel(
    id: id,
    title: 'Event $id',
    dates: 'Jun 1 - 2, 2026',
    maxAvgElo: maxAvgElo,
    timeUntilStart: '',
    tourEventCategory: TourEventCategory.ongoing,
    timeControl: 'Standard',
    endDate: end,
    startDate: start,
  );
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

  group('smart event game ordering', () {
    test('combined events group by day, event average, then board', () {
      final day = DateTime.utc(2026, 6, 6);
      final eventA = _event(
        id: 'event-a',
        start: day,
        end: day,
        maxAvgElo: 2600,
      );
      final eventB = _event(
        id: 'event-b',
        start: day,
        end: day,
        maxAvgElo: 2400,
      );

      final ordered = sortSmartGames(
        [
          _game(
            gameId: 'b-board-1',
            whiteRating: 2450,
            blackRating: 2400,
            boardNr: 1,
            gameDay: day,
          ),
          _game(
            gameId: 'a-board-2',
            whiteRating: 2500,
            blackRating: 2450,
            boardNr: 2,
            gameDay: day,
          ),
          _game(
            gameId: 'a-board-1',
            whiteRating: 2500,
            blackRating: 2450,
            boardNr: 1,
            gameDay: day,
          ),
        ],
        pinnedIds: const <String>[],
        gameEventIds: const {
          'a-board-1': 'event-a',
          'a-board-2': 'event-a',
          'b-board-1': 'event-b',
        },
        eventById: {'event-a': eventA, 'event-b': eventB},
        groupBySourceEvent: true,
      );

      expect(ordered.map((game) => game.gameId), [
        'a-board-1',
        'a-board-2',
        'b-board-1',
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
        countSingular: 'live event',
        countPlural: 'live events',
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
