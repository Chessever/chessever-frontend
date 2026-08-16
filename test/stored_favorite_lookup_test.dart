import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/standings/providers/player_utils_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FavoritePlayer favorite({String? fideId, required String playerName}) {
    final now = DateTime.utc(2026, 1, 1);
    return FavoritePlayer(
      id: 'row-$playerName',
      userId: 'user',
      fideId: fideId,
      playerName: playerName,
      metadata: const {},
      createdAt: now,
      updatedAt: now,
    );
  }

  group('stored favourite lookup', () {
    test('matches on FIDE id when both sides have one', () {
      final favorites = [
        favorite(fideId: '1503014', playerName: 'Carlsen, Magnus'),
        favorite(fideId: '2020009', playerName: 'Firouzja, Alireza'),
      ];

      expect(
        storedFavoriteFor(
          favorites,
          fideId: '2020009',
          name: 'Alireza Firouzja',
        )?.playerName,
        'Firouzja, Alireza',
      );
    });

    test('a favourite with no FIDE id does not match every unrated player', () {
      // The regression this guards: comparing raw ids makes `null == null` a
      // hit, so one favourite stored without a FIDE id marked every
      // unidentified player in the standings as already followed.
      final favorites = [favorite(playerName: 'Some Local Player')];

      expect(
        storedFavoriteFor(favorites, fideId: null, name: 'Unrated Newcomer'),
        isNull,
      );
      expect(
        storedFavoriteFor(favorites, fideId: '', name: 'Unrated Newcomer'),
        isNull,
      );
    });

    test('falls back to the name when no FIDE id is available', () {
      final favorites = [favorite(playerName: 'Unrated Newcomer')];

      expect(
        storedFavoriteFor(
          favorites,
          fideId: null,
          name: '  unrated newcomer ',
        )?.playerName,
        'Unrated Newcomer',
      );
    });

    test('returns the stored row so removal can name it exactly', () {
      // The profile screen writes the raw profile name, the scorecard writes
      // the backfilled standings name. Removal matches on the stored
      // `player_name`, so the caller has to unfollow the row that exists.
      final favorites = [
        favorite(fideId: '1503014', playerName: 'Magnus Carlsen'),
      ];

      final stored = storedFavoriteFor(
        favorites,
        fideId: '1503014',
        name: 'Carlsen, Magnus',
      );

      expect(stored, isNotNull);
      expect(stored!.playerName, 'Magnus Carlsen');
    });

    test('an empty name with no FIDE id matches nothing', () {
      final favorites = [favorite(playerName: 'Magnus Carlsen')];

      expect(storedFavoriteFor(favorites, fideId: null, name: '  '), isNull);
    });
  });
}
