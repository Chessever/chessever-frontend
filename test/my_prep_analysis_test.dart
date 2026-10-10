import 'dart:io';

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/services/game_tree/game_tree_builder.dart';
import 'package:chessever2/services/game_tree/game_tree_codec.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
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

$moves $result
''';

void main() {
  final pgn = [
    _game(white: 'Me', black: 'A', result: '1-0', moves: '1. e4 e5 2. Qf3 Nc6 3. Bc4 Nd4 4. Qxf7#', site: 'https://lichess.org/g1'),
    _game(white: 'B', black: 'me', result: '1/2-1/2', moves: '1. d4 d5 2. c4 e6', date: '2025.01.02', site: 'https://lichess.org/g2'),
    _game(white: 'C', black: 'Me', result: '1-0', moves: '1. e4 c5 2. Nf3 O-O', site: 'https://lichess.org/g3'),
    // Duplicate of g1 must be dropped.
    _game(white: 'Me', black: 'A', result: '1-0', moves: '1. e4 e5', site: 'https://lichess.org/g1'),
  ].join('\n');

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('my_prep_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<List<PrepGame>> analyze() async {
    final file = File('${dir.path}/lichess.pgn')..writeAsStringSync(pgn);
    final db = '${dir.path}/p1.sqlite';
    runGameTreeBuild(
      GameTreeBuildRequest(
        dbPath: db,
        sources: [GameTreeSourceFile(path: file.path, kind: 'lichess')],
        aliases: const ['me'],
      ),
    );
    final store = GameTreeStore.open('p1', db, playerScope: true)!;
    addTearDown(store.close);
    final rows = await store.loadGames();
    return [for (var i = 0; i < rows.length; i++) PrepGame.fromIndex(rows[i], i)];
  }

  test('reads games newest first, dedupes by URL and finds the player', () async {
    final games = await analyze();
    expect(games, hasLength(3));
    expect(games.last.date, DateTime.utc(2025, 1, 2));
    expect(games.firstWhere((g) => g.white == 'Me').playerIsWhite, isTrue);
    expect(games.last.playerIsWhite, isFalse);
    expect(games.first.speed, PrepTimeControl.blitz);
    expect(games.first.source, PrepSource.lichess);
  });

  test('stats score from the player chair', () async {
    final s = PrepStats.of(await analyze());
    expect(s.overall.wins, 1);
    expect(s.overall.draws, 1);
    expect(s.overall.losses, 1);
    expect(s.asWhite.wins, 1);
    expect(s.asBlack.total, 2);
    expect(s.whiteOpenings.single.name, "King's Pawn Game: Napoleon Attack");
    expect(s.whiteOpenings.single.eco, 'C20');
    // Desktop's definitions: FIDE dp on the score, every rated opponent.
    expect(s.averageOpponent, 2467);
    expect(s.performance, 2467); // 50% scores the opposition's average
    expect(s.decisive, 2);
    expect(s.decisiveRate, closeTo(2 / 3, 1e-9));
    expect(s.clocks, [(PrepTimeControl.blitz, 3)]);
    // 4, 4 and 7 plies all fall in the first length band (0–20 moves).
    expect(s.lengths, [3, 0, 0, 0, 0]);
    expect(s.byYear.map((y) => (y.year, y.total)), [(2025, 1), (2026, 2)]);
  });

  test('performance uses FIDE dp, not a linear spread', () {
    PrepGame g(int i, String result) => PrepGame(
      index: i,
      source: PrepSource.lichess,
      white: 'Me',
      black: 'Opp$i',
      result: result,
      plies: 60,
      whiteElo: 2000,
      blackElo: 2000,
      playerIsWhite: true,
    );
    // 3 of 4 is 75%: +193 on the FIDE table.
    final s = PrepStats.of([g(0, '1-0'), g(1, '1-0'), g(2, '1-0'), g(3, '0-1')]);
    expect(s.performance, 2193);
    // 21–30 moves is the second band, as desktop draws it.
    expect(s.lengths, [0, 4, 0, 0, 0]);
  });

  test('clocks, results and names index as the desktop app indexes them', () {
    int? speed(String? tc, {String kind = 'manual', String? event}) =>
        classifyTreeSpeed(
          lichess: kind == 'lichess',
          timeControl: tc,
          event: event,
          source: kind,
        );
    // Over-the-board PGNs use the FIDE-style bands, with no bullet.
    expect(speed('600'), TreeSpeed.blitz);
    expect(speed('120+1'), TreeSpeed.blitz);
    expect(speed('1500'), TreeSpeed.rapid);
    expect(speed('40/7200:3600'), TreeSpeed.classical);
    // Each provider keeps its own bands.
    expect(speed('300+5', kind: 'chesscom'), TreeSpeed.blitz);
    expect(speed('300+5', kind: 'lichess'), TreeSpeed.rapid);
    expect(speed('-', kind: 'lichess'), TreeSpeed.correspondence);
    // A database game without a clock is read from its event.
    expect(
      speed(null, kind: 'chessever', event: 'World Blitz Championship 2024'),
      TreeSpeed.blitz,
    );
    expect(
      speed(null, kind: 'chessever', event: 'Tata Steel Masters'),
      TreeSpeed.classical,
    );
    expect(speed(null), isNull);

    for (final draw in ['1/2-1/2', '1/2', '0.5-0.5', '½-½']) {
      expect(treeResultCode(draw), 2);
    }
    expect(treePlayerKey('Carlsen,M.'), treePlayerKey('carlsen, m'));
  });

  test('a FIDE id finds the player whatever the name is spelt like', () async {
    String game(String white, String black, String ids, String site) => '''
[Event "Open"]
[Site "$site"]
[Date "2024.01.01"]
[White "$white"]
[Black "$black"]
$ids
[Result "1-0"]

1. e4 e5 1-0
''';
    final file = File('${dir.path}/chessever.pgn')
      ..writeAsStringSync(
        [
          // Spelt unlike any alias, but carrying the id.
          game('Pragg R', 'A', '[WhiteFideId "25059530"]', 's1'),
          // Punctuation aside, the alias itself.
          game('B', 'Praggnanandhaa,R.', '', 's2'),
          // A namesake with someone else's id is not the player.
          game('Praggnanandhaa R', 'C', '[WhiteFideId "111"]', 's3'),
        ].join('\n'),
      );
    final db = '${dir.path}/fide.sqlite';
    runGameTreeBuild(
      GameTreeBuildRequest(
        dbPath: db,
        sources: [GameTreeSourceFile(path: file.path, kind: 'chessever')],
        aliases: const ['praggnanandhaa r'],
        fideId: '25059530',
      ),
    );
    final store = GameTreeStore.open('fide', db, playerScope: true)!;
    addTearDown(store.close);
    final rows = await store.loadGames();
    final sides = {for (final r in rows) r.white: r.side};
    expect(sides, {'Pragg R': 1, 'B': 2, 'Praggnanandhaa R': 0});
  });

  test('Format reads a database game\'s Site, as desktop does', () async {
    String game(String site, String black) => '''
[Event "Open"]
[Site "$site"]
[Date "2024.01.01"]
[White "Me"]
[Black "$black"]
[Result "1-0"]

1. e4 e5 1-0
''';
    final file = File('${dir.path}/chessever.pgn')
      ..writeAsStringSync(
        [
          game('chess.com INT', 'A'),
          game('Lichess.org INT', 'B'),
          game('Wijk aan Zee NED', 'C'),
        ].join('\n'),
      );
    final db = '${dir.path}/format.sqlite';
    runGameTreeBuild(
      GameTreeBuildRequest(
        dbPath: db,
        sources: [GameTreeSourceFile(path: file.path, kind: 'chessever')],
        aliases: const ['me'],
      ),
    );
    final store = GameTreeStore.open('format', db, playerScope: true)!;
    addTearDown(store.close);
    final rows = await store.loadGames();
    final games = [
      for (var i = 0; i < rows.length; i++) PrepGame.fromIndex(rows[i], i),
    ];
    expect({for (final g in games) g.black: g.isOnline}, {
      'A': true,
      'B': true,
      'C': false,
    });
    PrepFilter format(GameOnlineFilter value) =>
        PrepFilter(base: GameFilter().copyWith(online: value));
    expect(
      format(GameOnlineFilter.online).apply(games).map((g) => g.black).toSet(),
      {'A', 'B'},
    );
    expect(format(GameOnlineFilter.otb).apply(games).single.black, 'C');
  });

  test('a sync of the same selection appends only new games', () {
    final path = '${dir.path}/account.pgn';
    expect(writePrepGames(path: path, incoming: pgn, merge: true), 3);
    final before = File(path).readAsStringSync();
    final more = _game(
      white: 'Me',
      black: 'D',
      result: '0-1',
      moves: '1. c4 e5',
      site: 'https://lichess.org/g4',
    );
    expect(writePrepGames(path: path, incoming: '$pgn\n$more', merge: true), 4);
    final after = File(path).readAsStringSync();
    // Every stored byte stays where it was; the new game is the tail.
    expect(after.startsWith(before), isTrue);
    expect(after.substring(before.length), contains('lichess.org/g4'));
    // A changed selection replaces the file.
    expect(writePrepGames(path: path, incoming: more, merge: false), 1);
  });

  test('chess.com TimeClass is authoritative and Daily maps to correspondence', () {
    expect(
      prepSpeedOf(source: PrepSource.chesscom, timeControl: '600', timeClass: 'blitz'),
      PrepTimeControl.blitz,
    );
    expect(
      prepSpeedOf(source: PrepSource.chesscom, timeControl: '1/86400', timeClass: 'daily'),
      PrepTimeControl.correspondence,
    );
    expect(prepSpeedOf(source: PrepSource.lichess, timeControl: '15+0'),
        PrepTimeControl.ultrabullet);
    expect(prepExplorerTimeControl(PrepTimeControl.bullet), 'blitz');
    expect(prepExplorerTimeControl(PrepTimeControl.correspondence), 'classical');
  });

  test('relative periods anchor to the month so the server scope is stable', () {
    final a = PrepDateRange.year.fromDate(DateTime.utc(2026, 10, 6));
    final b = PrepDateRange.year.fromDate(DateTime.utc(2026, 10, 28));
    expect(a, DateTime.utc(2025, 11, 1));
    expect(a, b);
    const prefs = PrepDownloadPreferences(timeControls: {PrepTimeControl.blitz});
    expect(
      PrepDownloadPreferences.fromJson(prefs.toJson()),
      prefs,
    );
  });

  test('profile JSON round-trips', () {
    const profile = PrepProfile(
      id: 'x',
      kind: PrepKind.favorite,
      name: 'Magnus Carlsen',
      createdAtMs: 1,
      favoriteId: 'carlsen',
      accounts: [
        PrepAccount(source: PrepSource.chesscom, username: 'MagnusCarlsen', gameCount: 3),
      ],
    );
    final back = PrepProfile.fromJson(profile.toJson())!;
    expect(back.kind, PrepKind.favorite);
    expect(back.accounts.single.key, 'chesscom:magnuscarlsen');
    expect(back.accounts.single.gameCount, 3);
  });

  test('game keys prefer the provider link', () {
    expect(prepGameKey('[Site "Chess.com"]\n[Link "https://www.chess.com/game/live/1"]'),
        'https://www.chess.com/game/live/1');
    expect(splitPrepPgn(pgn), hasLength(4));
  });
}
