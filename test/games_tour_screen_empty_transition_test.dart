import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  group('shouldInitializeGamesScreen', () {
    test('accepts a loading-to-empty games result', () {
      expect(
        shouldInitializeGamesScreen(
          currentScreen: null,
          nextGames: const AsyncValue<List<Games>>.data(<Games>[]),
        ),
        isTrue,
      );
    });

    test('waits while the games result is still loading', () {
      expect(
        shouldInitializeGamesScreen(
          currentScreen: null,
          nextGames: const AsyncValue<List<Games>>.loading(),
        ),
        isFalse,
      );
    });
  });
}
