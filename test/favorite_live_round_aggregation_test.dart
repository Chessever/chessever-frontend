import 'package:flutter_test/flutter_test.dart';

import 'support/favorite_live_round_test_utils.dart';

void main() {
  group('favorite live round aggregation', () {
    test('aggregates multiple favorite live games into one notification', () {
      final aggregation = buildFavoriteLiveAggregation(
        candidateUserIds: const ['user-a'],
        playerFavoriteMap: const {
          'user-a': [
            'Magnus Carlsen',
            'Hikaru Nakamura',
            'Fabiano Caruana',
          ],
        },
        liveSnapshot: FavoriteLiveSnapshot(
          liveNames: {
            'Magnus Carlsen',
            'Hikaru Nakamura',
            'Fabiano Caruana',
          },
          ratings: const {
            'Magnus Carlsen': 2830,
            'Fabiano Caruana': 2800,
            'Hikaru Nakamura': 2790,
          },
        ),
        roundName: 'Round 1',
      );

      expect(aggregation.batches, hasLength(1));
      expect(aggregation.recipientsToRecord, ['user-a']);
    });

    test('formats three or more favorites as top two and others', () {
      final aggregation = buildFavoriteLiveAggregation(
        candidateUserIds: const ['user-a'],
        playerFavoriteMap: const {
          'user-a': [
            'Hikaru Nakamura',
            'Dommaraju Gukesh',
            'Magnus Carlsen',
          ],
        },
        liveSnapshot: FavoriteLiveSnapshot(
          liveNames: {
            'Magnus Carlsen',
            'Hikaru Nakamura',
            'Dommaraju Gukesh',
          },
          ratings: const {
            'Magnus Carlsen': 2830,
            'Hikaru Nakamura': 2790,
            'Dommaraju Gukesh': 2780,
          },
        ),
        roundName: 'Round 1',
      );

      expect(
        aggregation.batches.single.body,
        'Carlsen, Magnus, Nakamura, Hikaru, and others are live in Round 1.',
      );
    });
  });
}

