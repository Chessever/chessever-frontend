import 'package:chessever2/screens/player_profile/utils/player_rating_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('preferCanonicalFideRating', () {
    test('uses the canonical FIDE rating when Gamebase is stale', () {
      expect(
        preferCanonicalFideRating(canonicalRating: 2538, gamebaseRating: 2522),
        2538,
      );
    });

    test('falls back to Gamebase when canonical FIDE data is unavailable', () {
      expect(
        preferCanonicalFideRating(canonicalRating: null, gamebaseRating: 2522),
        2522,
      );
    });
  });
}
