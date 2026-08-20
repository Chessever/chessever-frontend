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

    test('derives the exact event player route from URL-backed game context', () {
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

    test('keeps a group-broadcast UUID when no tour slug pair is present', () {
      const id = '550e8400-e29b-41d4-a716-446655440000';
      expect(
        buildPlayerEventShareUrl(
          hasEventContext: true,
          canonicalEventId: id,
          eventName: 'KazChess Masters',
          playerFideId: 13730039,
        ),
        'https://chessever.com/broadcast/kazchess-masters/$id/player/13730039',
      );
    });

    test(
      'rejects display-only TWIC/gamebase tour labels and falls back to profile',
      () {
        expect(
          buildPlayerEventShareUrl(
            hasEventContext: true,
            eventName: 'TCh-RUS 2026',
            contextTourId: 'TCh-RUS 2026',
            contextTourSlug: 'TCh-RUS 2026',
            playerFideId: 13730039,
          ),
          'https://chessever.com/player/13730039',
        );
        expect(
          buildPlayerEventShareUrl(
            hasEventContext: true,
            eventName: 'Some Open',
            contextTourId: 'Gamebase',
            contextTourSlug: 'Some Open',
            playerFideId: 13730039,
          ),
          'https://chessever.com/player/13730039',
        );
        expect(
          buildPlayerEventShareUrl(
            hasEventContext: true,
            canonicalEventId: 'TCh-RUS 2026',
            eventName: 'TCh-RUS 2026',
            tourId: 'TCh-RUS 2026',
            tourSlug: 'TCh-RUS 2026',
            playerFideId: 13730039,
          ),
          'https://chessever.com/player/13730039',
        );
        expect(
          buildPlayerEventShareUrl(
            hasEventContext: true,
            canonicalEventId: 'Miniatures',
            eventName: 'Miniatures',
            tourId: 'Miniatures',
            tourSlug: 'italian-game',
            playerFideId: 13730039,
          ),
          'https://chessever.com/player/13730039',
        );
      },
    );

    test('never interpolates archive labels into a /broadcast/ path', () {
      final url = buildPlayerEventShareUrl(
        hasEventContext: true,
        canonicalEventId: 'Gamebase',
        eventName: 'Titled Tuesday',
        tourId: 'Gamebase',
        tourSlug: 'Titled Tuesday',
        playerFideId: 13730039,
      );
      expect(url, isNot(contains('/broadcast/')));
      expect(url, 'https://chessever.com/player/13730039');
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

  group('buildTeamEventShareUrl', () {
    test('builds the team-event route for URL-backed tours', () {
      expect(
        buildTeamEventShareUrl(
          teamName: 'USA',
          canonicalEventId: 'gb-123',
          eventName: 'Olympiad',
          tourId: 'QXavbhIZ',
          tourSlug: 'olympiad-2024',
        ),
        'https://chessever.com/broadcast/olympiad-2024/QXavbhIZ/team/USA',
      );
    });

    test('returns null for archive / display-only identities', () {
      expect(
        buildTeamEventShareUrl(
          teamName: 'USA',
          canonicalEventId: 'TCh-RUS 2026',
          eventName: 'TCh-RUS 2026',
          tourId: 'TCh-RUS 2026',
          tourSlug: 'TCh-RUS 2026',
        ),
        isNull,
      );
    });
  });

  group('isUrlBackedTourIdentity', () {
    test('accepts real broadcast slug pairs', () {
      expect(
        isUrlBackedTourIdentity(
          tourId: 'GtTXd69H',
          tourSlug: 'tata-steel-masters-2024',
        ),
        isTrue,
      );
    });

    test('rejects written event names and archive sentinels', () {
      expect(
        isUrlBackedTourIdentity(
          tourId: 'TCh-RUS 2026',
          tourSlug: 'TCh-RUS 2026',
        ),
        isFalse,
      );
      expect(
        isUrlBackedTourIdentity(tourId: 'Gamebase', tourSlug: 'some-open'),
        isFalse,
      );
      expect(
        isUrlBackedTourIdentity(tourId: 'Miniatures', tourSlug: 'italian-game'),
        isFalse,
      );
    });
  });

  group('isUrlBackedEventId', () {
    test('accepts kebab slugs, UUIDs, and Lichess short ids', () {
      expect(isUrlBackedEventId('group-123'), isTrue);
      expect(
        isUrlBackedEventId('550e8400-e29b-41d4-a716-446655440000'),
        isTrue,
      );
      expect(isUrlBackedEventId('GtTXd69H'), isTrue);
    });

    test('rejects archive sentinels and written names', () {
      expect(isUrlBackedEventId('Gamebase'), isFalse);
      expect(isUrlBackedEventId('Miniatures'), isFalse);
      expect(isUrlBackedEventId('TCh-RUS 2026'), isFalse);
    });
  });
}
