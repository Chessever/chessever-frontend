import 'package:chessever2/screens/standings/utils/player_event_share_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildPlayerEventShareUrl', () {
    test('keeps the exact event player route when canonical context exists', () {
      expect(
        buildPlayerEventShareUrl(
          hasEventContext: true,
          canonicalEventId: 'group-123',
          eventName: 'KazChess Masters',
          tourId: 'tour-456',
          tourSlug: 'kazchess-masters',
          playerFideId: 13730039,
        ),
        'https://chessever.com/broadcast/kazchess-masters/tour-456/player/13730039',
      );
    });

    test('derives the exact event player route from game context', () {
      expect(
        buildPlayerEventShareUrl(
          hasEventContext: true,
          eventName: 'KazChess Masters',
          contextTourId: 'tour-456',
          contextTourSlug: 'kazchess-masters',
          playerFideId: 13730039,
        ),
        'https://chessever.com/broadcast/kazchess-masters/tour-456/player/13730039',
      );
    });

    test(
      'falls back to the main player profile when event identity is absent',
      () {
        expect(
          buildPlayerEventShareUrl(
            hasEventContext: true,
            eventName: 'KazChess Masters',
            playerFideId: 13730039,
          ),
          'https://chessever.com/player/13730039',
        );
      },
    );

    test('returns no link when neither event nor player can be resolved', () {
      expect(
        buildPlayerEventShareUrl(
          hasEventContext: true,
          eventName: 'Unknown event',
        ),
        isNull,
      );
    });
  });
}
