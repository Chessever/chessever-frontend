// Trello #1228. `/api/miniatures` names a broadcast game by its pairing and
// sends nothing to recover the tournament from, so a miniature card reads it
// off the full game. These rows are copied from production (2026-10-12).
import 'package:chessever2/screens/gamebase/models/gamebase_game.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _pairing = 'Round 6: Del Rio Baena, Dani - Garcia Canals, Gerard';
const _site =
    'https://lichess.org/broadcast/catalan-age-group-team-championship-2026-sub-18/round-6/rkYWEnda/R3kJFF30';

GamebaseGameWithPgn _game({
  String? event = _pairing,
  String? site = _site,
  Map<String, dynamic>? tags,
}) {
  return GamebaseGameWithPgn(
    id: '018a297a-b637-59a2-b2be-b77c77735812',
    date: DateTime.utc(2026, 10, 12),
    result: GameResult.blackWins,
    timeControl: TimeControl.classical,
    event: event,
    site: site,
    whiteName: 'Del Rio Baena, Dani',
    blackName: 'Garcia Canals, Gerard',
    data: tags == null ? null : {'md': tags},
  );
}

void main() {
  test('the group broadcast names the tournament', () {
    expect(
      gamebaseGameEventTitle(
        _game(
          tags: {
            'Event': _pairing,
            'BroadcastName': 'Catalan Age-Group Team Championship 2026 Sub 18',
            'ChessEverTourName':
                'Catalan Age-Group Team Championship 2026 Sub 18',
            'ChessEverGroupBroadcastName':
                'Catalan Age-Group Team Championship 2026',
          },
        ),
      ),
      'Catalan Age-Group Team Championship 2026',
    );
  });

  test('without ChessEver tags, Lichess\'s BroadcastName does', () {
    expect(
      gamebaseGameEventTitle(
        _game(
          tags: {'Event': _pairing, 'BroadcastName': 'Hoogeveen Open 2026'},
        ),
      ),
      'Hoogeveen Open 2026',
    );
  });

  test('without any tag, the broadcast site does', () {
    expect(
      gamebaseGameEventTitle(_game()),
      'Catalan Age Group Team Championship 2026 Sub 18',
    );
  });

  test('a pairing with nothing behind it names no tournament', () {
    expect(gamebaseGameEventTitle(_game(site: 'Lloret de Mar ESP')), isNull);
  });

  test('a real event is kept as it is', () {
    expect(
      gamebaseGameEventTitle(_game(event: 'Linares', site: 'Linares ESP')),
      'Linares',
    );
  });

  test(
    'the provider reads the title off the game a card already fetched',
    () async {
      final container = ProviderContainer(
        overrides: [
          gameWithPgnByIdProvider.overrideWith(
            (ref, gameId) async =>
                _game(tags: {'BroadcastName': 'Hoogeveen Open 2026'}),
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        gamebaseGameEventTitleProvider('game-1'),
        (_, _) {},
      );
      addTearDown(sub.close);

      expect(sub.read(), isNull, reason: 'nothing to show while it loads');
      await container.read(gameWithPgnByIdProvider('game-1').future);
      expect(sub.read(), 'Hoogeveen Open 2026');
    },
  );
}
