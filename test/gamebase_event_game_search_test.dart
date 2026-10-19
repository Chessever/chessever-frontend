import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search.dart';
import 'package:flutter_test/flutter_test.dart';

// Trello #1264: searching inside a historical (gamebase-only) event found
// nothing, because the search read the Supabase games cache by the virtual
// `gamebasev2::` id. Those events now search the games already loaded. These
// games carry no `search` terms, so matching rests on players, ECO and opening.
void main() {
  const tourId =
      'gamebasev2::name=Gothenburg+Interzonal&site=Goteborg+izt&slug=Gothenburg+Interzonal';

  Player player(String name, {String fed = ''}) => Player(
    name: name,
    title: '',
    rating: 0,
    fideId: 0,
    fed: fed,
    clock: 0,
    team: '',
  );

  Games game(
    String id,
    String white,
    String black, {
    String? eco,
    String? opening,
    String status = '1-0',
  }) => Games(
    id: id,
    roundId: '$tourId::r::1',
    roundSlug: 'Round 1',
    tourId: tourId,
    tourSlug: 'Gothenburg Interzonal',
    status: status,
    players: [player(white), player(black)],
    eco: eco,
    openingName: opening,
  );

  final games = [
    game(
      'a',
      'Keres, Paul',
      'Spassky, Boris V.',
      eco: 'B90',
      opening: 'Sicilian, Najdorf',
    ),
    game('b', 'Bronstein, David', 'Stahlberg, Gideon', eco: 'E60'),
    game('c', 'Spassky, Boris Vasily', 'Donner, Jan-Hein', status: '1/2-1/2'),
  ];

  List<String> ids(String query) =>
      searchGamesInList(games, query).results.map((r) => r.game.id).toList();

  test('matches gamebase games by player name', () {
    expect(ids('spassky'), ['a', 'c']);
    expect(ids('Keres Paul'), ['a']);
  });

  test('matches gamebase games by ECO and opening', () {
    expect(ids('B90'), ['a']);
    expect(ids('najdorf'), ['a']);
  });

  test('matches gamebase games by PGN result', () {
    expect(ids('1/2-1/2'), ['c']);
  });

  test('empty query and no match return nothing', () {
    expect(ids(''), isEmpty);
    expect(ids('carlsen'), isEmpty);
  });
}
