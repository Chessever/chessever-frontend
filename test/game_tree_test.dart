import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/services/player_opening_tree.dart';
import 'package:chessever2/services/game_tree/game_tree_builder.dart';
import 'package:chessever2/services/game_tree/game_tree_codec.dart';
import 'package:chessever2/services/game_tree/game_tree_db.dart';
import 'package:chessever2/services/game_tree/game_tree_registry.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';
import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter_test/flutter_test.dart';

String _game({
  required String white,
  required String black,
  required String result,
  required String moves,
  String date = '2026.09.01',
  String tc = '180+0',
  String site = 'https://lichess.org/abc',
}) => '''
[Event "Rated Blitz game"]
[Site "$site"]
[Date "$date"]
[White "$white"]
[Black "$black"]
[Result "$result"]
[WhiteElo "2500"]
[BlackElo "2400"]
[TimeControl "$tc"]
[ECO "C20"]
[Opening "King's Pawn Game: Napoleon Attack"]

$moves $result''';

void main() {
  late Directory dir;
  late File pgn;
  late String dbPath;

  final games = [
    _game(
      white: 'Me',
      black: 'A',
      result: '1-0',
      moves:
          '1. e4 { [%clk 0:03:00] } 1... e5 2. Qf3 (2. Nf3 Nc6) 2... Nc6 '
          '3. Bc4 Nd4 \$4 4. Qxf7#',
      site: 'https://lichess.org/g1',
    ),
    _game(
      white: 'B',
      black: 'me',
      result: '1/2-1/2',
      moves: '1. d4 d5 2. c4 e6',
      date: '2025.01.02',
      site: 'https://lichess.org/g2',
    ),
    _game(
      white: 'C',
      black: 'Me',
      result: '1-0',
      moves: '1.e4 c5 2.Nf3 O-O',
      site: 'https://lichess.org/g3',
    ),
    // Same URL as g1: dropped.
    _game(
      white: 'Me',
      black: 'A',
      result: '1-0',
      moves: '1. e4 e5',
      site: 'https://lichess.org/g1',
    ),
  ];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('game_tree_test');
    pgn = File('${dir.path}/lichess.pgn')..writeAsStringSync(games.join('\n\n'));
    dbPath = '${dir.path}/tree.sqlite';
  });

  tearDown(() {
    GameTreeRegistry.unregister('p1');
    dir.deleteSync(recursive: true);
  });

  GameTreeBuildResult build() => runGameTreeBuild(
    GameTreeBuildRequest(
      dbPath: dbPath,
      sources: [GameTreeSourceFile(path: pgn.path, kind: 'lichess')],
      aliases: const ['me'],
    ),
  );

  test('scans headers and the main line past comments and variations', () {
    final scan = scanPgnGame(games.first);
    expect(scan.tag('White'), 'Me');
    expect(scan.sans, ['e4', 'e5', 'Qf3', 'Nc6', 'Bc4', 'Nd4', 'Qxf7#']);
    expect(scan.plies, 7);
    expect(scanPgnGame(games[2]).sans, ['e4', 'c5', 'Nf3', 'O-O']);
  });

  test('only the Event tag starts a game, not EventDate or EventType', () {
    final text =
        '[Event "One"]\r\n[EventDate "2026.10.08"]\r\n'
        '[EventType "swiss"]\r\n\r\n1. e4 e5 1-0\r\n\r\n'
        '[Event\t"Two"]\r\n[EventCountry "AZE"]\r\n';
    final bytes = Uint8List.fromList(utf8.encode(text));
    expect(pgnGameStarts(bytes), [0, text.indexOf('[Event\t')]);
    expect(pgnGameStarts(Uint8List.fromList(utf8.encode('[Event'))), isEmpty);
  });

  test(
    'EventDate preserves the complete headers, results and player side',
    () async {
      final first = games.first.replaceFirst(
        '[Result',
        '[EventDate "2026.09.01"]\n[EventType "swiss"]\n[Result',
      );
      pgn.writeAsStringSync('$first\n\n${games[1]}');
      final result = build();
      expect(result.games, 2);
      final store = GameTreeStore.open('p1', dbPath, playerScope: true)!;
      addTearDown(store.close);
      final rows = await store.loadGames();
      expect(rows.map((g) => g.side), containsAll([1, 2]));
      final win = rows.singleWhere((g) => g.side == 1);
      expect(win.white, 'Me');
      expect(treeResultText(win.result), '1-0');
      expect(store.game(win.id)!.$2, contains('[EventDate'));
      expect(store.game(win.id)!.$2, contains('[White "Me"]'));
    },
  );

  test('moves and positions encode compactly and round-trip', () {
    for (final uci in ['e2e4', 'e7e8q', 'a7a8n', 'h1h8']) {
      expect(decodeTreeMove(encodeTreeMove(uci)), uci);
    }
    expect(encodeTreeMove(''), 0);
    expect(gameTreeHashOfFen(kInitialFEN), kGameTreeRootHash);
    expect(
      gameTreeHashOfFen('$kInitialFEN '),
      gameTreeHashOfFen(kInitialFEN.replaceFirst(' 0 1', ' 5 9')),
    );
  });

  test('older parser versions rebuild even when PGN files are unchanged', () {
    build();
    final db = openGameTreeDatabase(dbPath);
    final signature = jsonDecode(readGameTreeMeta(db, 'signature')!) as Map;
    signature['v'] = kGameTreeSchemaVersion - 1;
    writeGameTreeMeta(db, 'signature', jsonEncode(signature));
    db.close();
    final store = GameTreeStore.open('p1', dbPath, playerScope: true)!;
    addTearDown(store.close);
    expect(store.isCurrentVersion, isFalse);
    expect(build().rebuilt, isTrue);
    store.refresh();
    expect(store.isCurrentVersion, isTrue);
  });

  test('indexes games, dedupes provider URLs and serves the tree', () {
    final result = build();
    expect(result.games, 3);
    expect(result.rebuilt, isTrue);
    final store = GameTreeStore.open('p1', dbPath, playerScope: true)!;
    addTearDown(store.close);
    final white = store.tree.movesForFen(
      kInitialFEN,
      filters: const PlayerOpeningTreeFilterCriteria(color: 'white'),
    );
    expect(white.single.uci, 'e2e4');
    expect(white.single.total, 1);
    final all = store.tree.movesForFen(kInitialFEN);
    expect(all.map((m) => m.uci), containsAll(['e2e4', 'd2d4']));
    expect(all.first.uci, 'e2e4');
    expect(all.first.total, 2);
    // A move played once links straight to its game.
    final d4 = all.firstWhere((m) => m.uci == 'd2d4');
    expect(d4.gameId, startsWith('prep:p1:'));
    // Castling is written king-to-destination.
    final afterNf3 = Chess.initial
        .play(Move.parse('e2e4')!)
        .play(Move.parse('c7c5')!)
        .play(Move.parse('g1f3')!);
    expect(store.tree.movesForFen(afterNf3.fen), isEmpty); // illegal O-O
  });

  test('the explorer reads position games and single games', () async {
    build();
    final store = GameTreeStore.open('p1', dbPath, playerScope: true)!;
    GameTreeRegistry.register(store);
    final page = await GamebaseLocalGames.positionResolver!(
      const GamebaseLocalPositionQuery(
        playerId: 'prep:p1',
        fen: kInitialFEN,
        uci: 'e2e4',
      ),
    )!;
    expect(page.data, hasLength(2));
    expect(page.metadata.totalCount, 2);
    final first = page.data.first;
    expect(first['fen'], isNotNull);
    final game = GamebaseLocalGames.gameResolver!(first['id'] as String);
    expect(game?.pgn, contains('[Site'));
    expect(GamebaseLocalGames.gameResolver!('prep:nope:1'), isNull);
    expect(LocalPlayerOpeningTrees.resolver!('prep:p1'), same(store.tree));
    final asBlack = await GamebaseLocalGames.positionResolver!(
      const GamebaseLocalPositionQuery(
        playerId: 'prep:p1',
        fen: kInitialFEN,
        color: 'black',
      ),
    )!;
    expect(asBlack.data, hasLength(2));
    final games = await store.loadGames();
    expect(games.first.date, 20260901);
    expect(games.last.date, 20250102);
    expect(games.where((g) => g.side == 2), hasLength(2));
  });

  test('a grown file indexes only its new tail; a replaced one rebuilds', () {
    build();
    pgn.writeAsStringSync(
      '\n\n${_game(white: 'Me', black: 'D', result: '0-1', moves: '1. c4 e5', site: 'https://lichess.org/g4')}',
      mode: FileMode.append,
    );
    final grown = build();
    expect(grown.rebuilt, isFalse);
    expect(grown.added, 1);
    expect(grown.games, 4);
    expect(build().added, 0);

    pgn.writeAsStringSync(games[1]);
    final replaced = build();
    expect(replaced.rebuilt, isTrue);
    expect(replaced.games, 1);
  });

  test('a background build reports progress from a callback that cannot cross isolates', () async {
    // A ReceivePort cannot be sent; capturing one proves the isolate's
    // closure does not carry the caller's callback along.
    final unsendable = ReceivePort();
    addTearDown(unsendable.close);
    final seen = <double>[];
    final result = await buildGameTreeInBackground(
      GameTreeBuildRequest(
        dbPath: dbPath,
        sources: [GameTreeSourceFile(path: pgn.path, kind: 'lichess')],
        aliases: const ['me'],
      ),
      onProgress: (f) {
        unsendable.hashCode;
        seen.add(f);
      },
    );
    expect(result.games, 3);
    expect(seen, isNotEmpty);
    expect(seen.last, 1);
  });

  test('a canceled build keeps its progress and the next one resumes', () {
    final many = [
      for (var i = 0; i < 3200; i++)
        _game(
          white: 'Me',
          black: 'X$i',
          result: '1-0',
          moves: i.isEven ? '1. e4 e5' : '1. d4 d5',
          site: 'https://lichess.org/m$i',
        ),
    ];
    pgn.writeAsStringSync(many.join('\n\n'));
    final cancel = File('${dir.path}/cancel')..writeAsStringSync('1');
    final first = runGameTreeBuild(
      GameTreeBuildRequest(
        dbPath: dbPath,
        sources: [GameTreeSourceFile(path: pgn.path, kind: 'lichess')],
        aliases: const ['me'],
        cancelPath: cancel.path,
      ),
    );
    expect(first.canceled, isTrue);
    expect(first.games, lessThan(3200));
    cancel.deleteSync();
    final rest = build();
    expect(rest.rebuilt, isFalse);
    expect(rest.games, 3200);
  });
}
