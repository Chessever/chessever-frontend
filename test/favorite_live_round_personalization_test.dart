import 'package:flutter_test/flutter_test.dart';

import 'support/favorite_live_round_test_utils.dart';

void main() {
  group('favorite live round personalization', () {
    test('builds notification bodies from each user’s own favorites', () {
      final aggregation = buildFavoriteLiveAggregation(
        candidateUserIds: const ['user-a', 'user-b'],
        playerFavoriteMap: const {
          'user-a': ['Magnus Carlsen', 'Fabiano Caruana'],
          'user-b': ['Hikaru Nakamura'],
        },
        liveSnapshot: FavoriteLiveSnapshot(
          liveNames: {'Magnus Carlsen', 'Fabiano Caruana', 'Hikaru Nakamura'},
          ratings: const {
            'Magnus Carlsen': 2830,
            'Fabiano Caruana': 2800,
            'Hikaru Nakamura': 2790,
          },
          opponents: const {
            'Hikaru Nakamura': 'Arjun Erigaisi',
          },
        ),
        roundName: 'Round 1',
      );

      expect(aggregation.batches, hasLength(2));
      expect(
        aggregation.batches.first.body,
        'Carlsen, Magnus and Caruana, Fabiano are live in Round 1.',
      );
      expect(
        aggregation.batches.last.body,
        'Nakamura, Hikaru vs Erigaisi, Arjun is live.',
      );
    });
  });
}

