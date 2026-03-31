import 'package:flutter_test/flutter_test.dart';

import 'support/favorite_live_round_test_utils.dart';

void main() {
  group('favorite live round recipient filtering', () {
    test('falls back to event notification when favorite player alerts are disabled', () {
      final split = splitRoundRecipients(const [
        RecipientCandidate(
          userId: 'dual-user',
          isEventFav: true,
          isPlayerFav: true,
          favoritePlayerAlerts: false,
          favoriteEventAlerts: true,
        ),
      ]);

      expect(split.playerRecipients, isEmpty);
      expect(split.eventRecipients, ['dual-user']);
    });

    test('falls back to event notification when favorite player time-control is blocked', () {
      final split = splitRoundRecipients(
        const [
          RecipientCandidate(
            userId: 'dual-user',
            isEventFav: true,
            isPlayerFav: true,
            fpBlitz: false,
            seBlitz: true,
          ),
        ],
        timeControl: 'blitz',
      );

      expect(split.playerRecipients, isEmpty);
      expect(split.eventRecipients, ['dual-user']);
    });

    test('skips users already covered by the live round window', () {
      final aggregation = buildFavoriteLiveAggregation(
        candidateUserIds: const ['user-a', 'user-b'],
        playerFavoriteMap: const {
          'user-a': ['Magnus Carlsen'],
          'user-b': ['Fabiano Caruana'],
        },
        liveSnapshot: FavoriteLiveSnapshot(
          liveNames: {'Magnus Carlsen', 'Fabiano Caruana'},
          opponents: const {
            'Magnus Carlsen': 'Ian Nepomniachtchi',
            'Fabiano Caruana': 'Dommaraju Gukesh',
          },
        ),
        roundName: 'Round 1',
        alreadyCoveredUserIds: {'user-a'},
      );

      expect(aggregation.batches, hasLength(1));
      expect(
        aggregation.batches.single.body,
        'Caruana, Fabiano vs Gukesh, Dommaraju is live.',
      );
      expect(aggregation.recipientsToRecord, ['user-b']);
    });
  });
}

