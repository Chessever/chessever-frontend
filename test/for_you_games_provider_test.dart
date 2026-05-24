import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mergeMissingFavoriteCurrentBroadcasts', () {
    test(
      'prepends favorite current broadcasts missing from the first page',
      () {
        final page = [
          _broadcast('krefelder', '13. Krefelder Pfingstopen 2026'),
          _broadcast('zalakarosi', '45. Zalakarosi Sakkfesztivál'),
        ];
        final favoriteBroadcasts = [
          _broadcast('olimpiada', 'Olimpiada Nacional CONADE San Luis Potosí'),
        ];

        final merged = mergeMissingFavoriteCurrentBroadcasts(
          pageBroadcasts: page,
          favoriteBroadcasts: favoriteBroadcasts,
          favoriteIds: const ['olimpiada'],
        );

        expect(merged.map((broadcast) => broadcast.id), [
          'olimpiada',
          'krefelder',
          'zalakarosi',
        ]);
      },
    );

    test('does not duplicate favorites already present on the page', () {
      final page = [
        _broadcast('olimpiada', 'Olimpiada Nacional CONADE San Luis Potosí'),
        _broadcast('krefelder', '13. Krefelder Pfingstopen 2026'),
      ];
      final favoriteBroadcasts = [
        _broadcast('olimpiada', 'Olimpiada Nacional CONADE San Luis Potosí'),
      ];

      final merged = mergeMissingFavoriteCurrentBroadcasts(
        pageBroadcasts: page,
        favoriteBroadcasts: favoriteBroadcasts,
        favoriteIds: const ['olimpiada'],
      );

      expect(merged, page);
    });

    test(
      'keeps favorite timestamp order when multiple favorites are injected',
      () {
        final page = [
          _broadcast('krefelder', '13. Krefelder Pfingstopen 2026'),
        ];
        final favoriteBroadcasts = [
          _broadcast('olimpiada', 'Olimpiada Nacional CONADE San Luis Potosí'),
          _broadcast('serbian', '12th Serbian Cup'),
        ];

        final merged = mergeMissingFavoriteCurrentBroadcasts(
          pageBroadcasts: page,
          favoriteBroadcasts: favoriteBroadcasts,
          favoriteIds: const ['serbian', 'olimpiada'],
        );

        expect(merged.map((broadcast) => broadcast.id), [
          'serbian',
          'olimpiada',
          'krefelder',
        ]);
      },
    );
  });
}

GroupBroadcast _broadcast(String id, String name) {
  return GroupBroadcast(
    id: id,
    createdAt: DateTime.utc(2026, 5, 24),
    name: name,
    search: const [],
    maxAvgElo: 2200,
    dateStart: DateTime.utc(2026, 5, 21),
    dateEnd: DateTime.utc(2026, 5, 24),
    timeControl: 'standard',
  );
}
