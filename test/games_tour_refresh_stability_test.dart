import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retains visible games across a transient empty refresh', () {
    final current = <Games>[_game('game-1')];

    final resolved = retainGamesAcrossTransientEmptyRefresh(
      current,
      const <Games>[],
    );

    expect(resolved, same(current));
  });

  test('accepts an authoritative non-empty refresh', () {
    final current = <Games>[_game('game-1')];
    final incoming = <Games>[_game('game-1'), _game('game-2')];

    final resolved = retainGamesAcrossTransientEmptyRefresh(current, incoming);

    expect(resolved, same(incoming));
  });

  test('keeps an initial empty result when no games were visible', () {
    const current = <Games>[];
    const incoming = <Games>[];

    final resolved = retainGamesAcrossTransientEmptyRefresh(current, incoming);

    expect(resolved, same(incoming));
  });
}

Games _game(String id) => Games(
  id: id,
  roundId: 'round-5',
  roundSlug: 'round-5',
  tourId: 'tour-1',
  tourSlug: 'tour-1',
  status: '*',
);
