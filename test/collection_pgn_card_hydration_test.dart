import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _pgn = '''[Event "St Louis Summer A"]
[Site "Saint Louis"]
[Date "2026.09.26"]
[Round "4.1"]
[Board "3"]
[White "Jumabayev, Rinat"]
[Black "Durarbayli, Vasif"]
[WhiteTitle "GM"]
[BlackTitle "GM"]
[WhiteElo "2621"]
[BlackElo "2618"]
[WhiteFederation "KAZ"]
[BlackFed "AZE"]
[WhiteFideId "13702619"]
[BlackFideId "13400795"]
[WhiteTeam "Club A"]
[BlackTeam "Club B"]
[TimeControl "40/5400+30:1800+30"]
[ECO "C60"]
[Opening "Ruy Lopez"]
[Result "0-1"]

1. e4 {[%clk 1:29:30] A mainline comment.} e5 {[%clk 1:29:00]}
2. Nf3 \$1 Nc6 (2... d6) 3. Bb5 {[%clk 1:28:20]} 0-1''';

void main() {
  test(
    'incomplete legacy cards preserve names, ratings and grouping from PGN',
    () {
      final card = CollectionGameCard.fromJson({'id': 'legacy', 'pgn': _pgn});
      final game = CollectionGame.fromCard(card)!;
      expect(game.game.whitePlayer.name, 'Jumabayev, Rinat');
      expect(game.game.blackPlayer.name, 'Durarbayli, Vasif');
      expect(game.game.whitePlayer.rating, 2621);
      final group = groupCollectionGames([], [game]).single;
      expect(group.section!.label, 'St Louis Summer A');
      expect(group.section!.title, 'Round 4.1');
      expect(group.section!.startsOn, DateTime(2026, 9, 26));
    },
  );

  test(
    'a selected chapter excludes parent and sibling games from board navigation',
    () {
      const chapter = CollectionSection(
        id: 'chapter',
        parentId: 'part',
        kind: CollectionSectionKind.chapter,
        label: 'Chapter 1',
      );
      const sibling = CollectionSection(
        id: 'sibling',
        parentId: 'part',
        kind: CollectionSectionKind.chapter,
        label: 'Chapter 2',
      );
      const part = CollectionSection(
        id: 'part',
        kind: CollectionSectionKind.part,
        label: 'Part I',
        children: [chapter, sibling],
      );
      CollectionGame game(String id, String sectionId) =>
          CollectionGame.fromCard(
            CollectionGameCard.fromJson({
              'id': id,
              'sectionId': sectionId,
              'pgn': _pgn,
            }),
          )!;
      final groups = groupCollectionGames(
        [part],
        [
          game('intro', 'part'),
          game('a', 'chapter'),
          game('b', 'chapter'),
          game('c', 'sibling'),
        ],
      );
      final picked = selectCollectionGameGroups(groups, 'chapter');
      expect(picked.map((g) => g.section!.id), ['part', 'chapter']);
      expect(picked.map((g) => g.offset), [0, 0]);
      expect(picked.expand((g) => g.games).map((g) => g.id), ['a', 'b']);
      expect(
        selectCollectionGameGroups(
          groups,
          'part',
        ).expand((g) => g.games).length,
        4,
      );
      expect(selectCollectionGameGroups(groups, 'all'), groups);
    },
  );

  test(
    'structured card hydration fills catalog links without changing PGN',
    () {
      final card = CollectionGameCard(
        id: 'hydrated',
        white: const CollectionPlayerSide(
          name: 'Jumabayev, Rinat',
          key: 'fide:13702619',
          fideId: '13702619',
          title: 'GM',
          fed: 'KAZ',
          playerId: 'catalog-player',
        ),
        black: const CollectionPlayerSide(
          name: 'Durarbayli, Vasif',
          key: 'name:vasif',
        ),
        pgn: _pgn
            .replaceAll('[WhiteFideId "13702619"]', '')
            .replaceAll('[WhiteTitle "GM"]', '')
            .replaceAll('[WhiteFederation "KAZ"]', ''),
      );
      final game = CollectionGame.fromCard(card)!.game;
      expect(game.whitePlayer.fideId, 13702619);
      expect(game.whitePlayer.gamebasePlayerId, 'catalog-player');
      expect(game.whitePlayer.countryCode, 'KAZ');
      expect(game.whitePlayer.title, 'GM');
      expect(game.pgn, card.pgn);
    },
  );

  test(
    'legacy split identities merge once and retain all game-filter keys',
    () {
      final rows = deduplicateCollectionPlayers([
        const CollectionPlayer(
          key: 'fide:1503014',
          name: 'Carlsen, Magnus',
          fideId: '1503014',
          games: 3,
          wins: 2,
        ),
        const CollectionPlayer(
          key: 'name:magnus carlsen',
          name: 'Magnus Carlsen',
          games: 2,
          draws: 1,
        ),
      ]);
      expect(rows, hasLength(1));
      expect(rows.single.games, 5);
      expect(rows.single.wins, 2);
      expect(
        deduplicateCollectionPlayers([
          const CollectionPlayer(
            key: 'fide:1',
            name: 'A Player',
            fideId: '1',
            playerId: 'catalog-id',
            games: 2,
          ),
          const CollectionPlayer(
            key: 'name:a player',
            name: 'Player, A',
            playerId: 'catalog-id',
            games: 1,
          ),
        ]).single.games,
        3,
      );
      expect(
        rows.single.aliasKeys,
        containsAll(['fide:1503014', 'name:magnus carlsen']),
      );
      expect(
        deduplicateCollectionPlayers([
          const CollectionPlayer(
            key: 'fide:1',
            name: 'Alex Smith',
            fideId: '1',
            fed: 'USA',
          ),
          const CollectionPlayer(
            key: 'fide:2',
            name: 'Smith, Alex',
            fideId: '2',
            fed: 'ENG',
          ),
          const CollectionPlayer(key: 'name:alex smith', name: 'Alex Smith'),
        ]),
        hasLength(3),
      );
    },
  );

  test(
    'fallback groups separate events and dates while preserving file order',
    () {
      CollectionGame entry(String id, String event, DateTime day) =>
          CollectionGame.fromCard(
            CollectionGameCard(
              id: id,
              event: event,
              playedOn: day,
              white: const CollectionPlayerSide(name: 'A', key: 'name:a'),
              black: const CollectionPlayerSide(name: 'B', key: 'name:b'),
              pgn: _pgn,
            ),
          )!;
      final groups = groupCollectionGames([], [
        entry('a', 'Olympiad', DateTime(2024, 9, 12)),
        entry('b', 'World Cup', DateTime(2024, 9, 12)),
        entry('c', 'Olympiad', DateTime(2024, 9, 13)),
        entry('d', 'Olympiad', DateTime(2024, 9, 12)),
      ]);
      expect(groups.map((g) => g.games.map((x) => x.id).toList()), [
        ['a', 'd'],
        ['b'],
        ['c'],
      ]);
      expect(groups.map((g) => g.offset), [0, 2, 3]);
      expect(groups.first.section!.label, 'Olympiad');
    },
  );

  test(
    'round timestamps use known instants while date-only imports stay date-only',
    () {
      CollectionGame entry(String id, DateTime? instant, {bool date = true}) =>
          CollectionGame.fromCard(
            CollectionGameCard(
              id: id,
              playedAt: instant,
              white: const CollectionPlayerSide(name: 'A', key: 'name:a'),
              black: const CollectionPlayerSide(name: 'B', key: 'name:b'),
              pgn: date ? _pgn : _pgn.replaceAll('[Date "2026.09.26"]', ''),
            ),
          )!;
      final known = DateTime.utc(2026, 9, 26, 15, 30);
      final dated = entry('date', null);
      expect(
        groupCollectionGames([], [dated]).single.section!.startsAt,
        isNull,
      );
      final groups = groupCollectionGames([], [
        dated,
        entry('instant', known, date: false),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.section!.startsAt, known);
      expect(groups.single.section!.startsOn, DateTime(2026, 9, 26));
    },
  );

  test('collection PGN hydrates tournament card data and recorded clocks', () {
    final game = collectionGameModel('book-game', _pgn);
    expect(game.whitePlayer.name, 'Jumabayev, Rinat');
    expect(game.blackPlayer.name, 'Durarbayli, Vasif');
    expect(game.whitePlayer.title, 'GM');
    expect(game.blackPlayer.rating, 2618);
    expect(game.whitePlayer.countryCode, 'KAZ');
    expect(game.blackPlayer.countryCode, 'AZE');
    expect(game.whitePlayer.fideId, 13702619);
    expect(game.blackPlayer.fideId, 13400795);
    expect(game.whitePlayer.team, 'Club A');
    expect(game.blackPlayer.team, 'Club B');
    expect(game.boardNr, 3);
    expect(game.roundId, '4.1');
    expect(game.timeControl, 'standard');
    expect(game.timeControlText, '40/5400+30:1800+30');
    expect(game.whiteClockSeconds, 5300);
    expect(game.blackClockSeconds, 5340);
    expect(game.whiteTimeDisplay, '1:28:20');
    expect(game.gameDay, DateTime(2026, 9, 26));
    expect(game.eco, 'C60');
    expect(game.openingName, 'Ruy Lopez');
    expect(game.lastMove, 'f1b5');
    expect(game.gameStatus, GameStatus.blackWins);
    expect(game.pgn, _pgn, reason: 'Keep all comments, NAGs and variations.');
  });

  test(
    'an unfinished stored PGN never invents a result from absent clocks',
    () {
      final game = collectionGameModel(
        'unfinished',
        '[White "A"]\n[Black "B"]\n[Result "*"]\n\n1. e4 e5 *',
      );
      expect(game.gameStatus, GameStatus.ongoing);
      expect(game.effectiveGameStatus, GameStatus.ongoing);
      expect(game.whiteClockSeconds, isNull);
      expect(game.blackClockSeconds, isNull);
    },
  );

  test('a club name never becomes a federation flag', () {
    final game = collectionGameModel(
      'team',
      '[White "A"]\n[Black "B"]\n[WhiteTeam "Local Chess Club"]\n\n*',
    );
    expect(game.whitePlayer.countryCode, isEmpty);
    expect(game.whitePlayer.team, 'Local Chess Club');
  });

  test('a supplied starting position survives without any moves', () {
    const fen = '8/8/8/8/8/8/4K3/7k b - - 0 1';
    final game = collectionGameModel(
      'position',
      '[SetUp "1"]\n[FEN "$fen"]\n[Date "2026.02.31"]\n\n*',
    );
    expect(game.fen, fen);
    expect(game.lastMove, isNull);
    expect(game.lastMoveTime, isNull);
  });

  test('clock samples belong to their mover when a PGN starts with Black', () {
    final game = collectionGameModel('black-start', '''[SetUp "1"]
[FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1"]
[Result "*"]

1... e5 {[%clk 0:10:00]} 2. Nf3 {[%clk 0:09:58]} *''');
    expect(game.blackClockSeconds, 600);
    expect(game.whiteClockSeconds, 598);
    expect(game.lastMove, 'g1f3');
    expect(game.effectiveGameStatus, GameStatus.ongoing);
  });

  test(
    'time-control filters use PGN seconds and respect category overrides',
    () {
      GamesTourModel from(String tc, {String category = '?'}) =>
          collectionGameModel(
            tc,
            '[TimeControl "$tc"]\n[TcCategory "$category"]\n\n*',
          );
      expect(from('180+2').timeControl, 'blitz');
      expect(from('60+30').timeControl, 'rapid');
      expect(from('900+10').timeControl, 'rapid');
      expect(from('3600').timeControl, 'standard');
      expect(from('5400+30', category: 'rapid').timeControl, 'rapid');
      expect(from('900+10', category: 'unrecognized').timeControl, 'rapid');
      expect(from('?').timeControl, isNull);
    },
  );

  test('unknown tags remain absent instead of appearing as card metadata', () {
    final game = collectionGameModel('unknown', '''[White "?"]
[WhiteTitle "-"]
[WhiteElo "?"]
[WhiteFed "?"]
[WhiteCountry "USA"]
[Board "?"]
[BoardNumber "7"]
[Date "2026.??.??"]

*''');
    expect(game.whitePlayer.name, 'White');
    expect(game.whitePlayer.title, isEmpty);
    expect(game.whitePlayer.rating, 0);
    expect(game.whitePlayer.countryCode, 'USA');
    expect(game.boardNr, 7);
    expect(game.gameDay, isNull);
  });
}
