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

GamesTourModel _game({required int whiteRating, required int blackRating}) {
  return GamesTourModel(
    gameId: 'game-1',
    whitePlayer: _player('White', whiteRating),
    blackPlayer: _player('Black', blackRating),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.ongoing,
    roundId: 'round-1',
    tourId: 'tour-1',
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

  group('SmartEventRequest favorite metadata', () {
    test('round-trips saved smart events through favorite metadata', () {
      final event = _event(
        id: 'event-a',
        start: DateTime.utc(2026, 6, 1),
        end: DateTime.utc(2026, 6, 2),
      );
      final request = SmartEventRequest(
        source: SmartEventSource.forYou,
        tierLabel: 'GM',
        titleSuffix: 'Live Games',
        minElo: 2500,
        maxElo: 3200,
        caption: 'Gathered from your 2500+ filter',
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
    });

    test(
      'reports saved smart event finished when all events are completed',
      () {
        final now = DateTime.now();
        final request = SmartEventRequest(
          source: SmartEventSource.forYou,
          tierLabel: 'GM',
          titleSuffix: 'Live Games',
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
  });
}
