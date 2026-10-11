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

  test('a source counts exactly the games its index reads', () async {
    String tagged(String id, String tags, String moves) =>
        '''
[Event "casual blitz game"]
[Site "https://lichess.org/$id"]
[White "Me"]
[Black "$id"]
[Result "1-0"]
[UTCDate "2026.10.01"]
[TimeControl "300+3"]
$tags

$moves 1-0
''';
    // Lichess reports a game begun from a set-up position as a variant. It
    // is standard chess, so it is counted and read like any other.
    const setUp =
        '[Variant "From Position"]\n'
        '[FEN "r4rk1/1pq2pb1/1n1p2p1/pB1P4/P4p2/1N3P2/1PPQ4/2KR3R w - - 0 22"]\n'
        '[SetUp "1"]';
    final incoming = [
      tagged('white', setUp, '22. Kb1 Qc5'),
      tagged('black', setUp.replaceFirst(' w - ', ' b - '), '22... Qc5 23. Kb1'),
      tagged('standard', '[Variant "Standard"]', '1. e4 e5'),
      // Other rules, and a game nobody moved in: neither counted nor read.
      tagged('chess960', '[Variant "Chess960"]', '1. e4 e5'),
      tagged('unplayed', '[Variant "Standard"]', ''),
    ].join('\n');
    final path = '${dir.path}/variants.pgn';
    final counted = writePrepGames(path: path, incoming: incoming, merge: false);
    final db = '${dir.path}/variants.sqlite';
    final built = runGameTreeBuild(
      GameTreeBuildRequest(
        dbPath: db,
        sources: [GameTreeSourceFile(path: path, kind: 'lichess')],
        aliases: const ['me'],
      ),
    );
    expect(counted, 3);
    expect(built.games, counted);
    final store = GameTreeStore.open('variants', db, playerScope: true)!;
    addTearDown(store.close);
    final rows = await store.loadGames();
    expect(
      {for (var i = 0; i < rows.length; i++) PrepGame.fromIndex(rows[i], i).black},
      {'white', 'black', 'standard'},
    );

    // A file stored before games were sifted on the way in still holds the
    // rest; a later sync counts only what the index reads from it.
    File(path).writeAsStringSync(incoming);
    expect(
      writePrepGames(
        path: path,
        incoming: tagged('later', '', '1. d4 d5'),
        merge: true,
      ),
      4,
    );
    expect(
      runGameTreeBuild(
        GameTreeBuildRequest(
          dbPath: '${dir.path}/later.sqlite',
          sources: [GameTreeSourceFile(path: path, kind: 'lichess')],
          aliases: const ['me'],
        ),
      ).games,
      4,
    );
  });

  test('read together, a game two sources hold counts once', () async {
    String game({
      required String white,
      required String black,
      required String date,
      required String moves,
      String result = '1-0',
      String? site,
      String elo = '2600',
    }) =>
        '''
[Event "Titled Tuesday"]
[Site "${site ?? 'Chess.com INT'}"]
[Date "$date"]
[White "$white"]
[Black "$black"]
[Result "$result"]
[WhiteElo "$elo"]
[BlackElo "$elo"]
[TimeControl "180+1"]

$moves $result
''';
    const played = '1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 6. Be3 e5';
    // The database writes names, check marks and its own date; the site
    // writes handles and may leave the marks out. Both are one game.
    final database = File('${dir.path}/database.pgn')
      ..writeAsStringSync(
        [
          game(white: 'Me, Myself', black: 'Rival, Real', date: '2026.09.29', moves: '$played 7. Bb5+ Bd7', elo: '2611'),
          // Only the database has this one.
          game(white: 'Other, One', black: 'Me, Myself', date: '2026.09.30', moves: '1. d4 d5 2. c4 e6', result: '0-1', elo: '2611'),
        ].join('\n'),
      );
    final site = File('${dir.path}/site.pgn')
      ..writeAsStringSync(
        [
          // A day later by the site's clock, no check mark: the same game.
          game(white: 'me', black: 'rivalhandle', date: '2026.09.30', moves: '$played 7. Bb5 Bd7', site: 'https://www.chess.com/game/live/1', elo: '3000'),
          // The same moves a year on are another game.
          game(white: 'me', black: 'rivalhandle', date: '2027.09.30', moves: '$played 7. Bb5 Bd7', site: 'https://www.chess.com/game/live/2', elo: '3000'),
        ].join('\n'),
      );
    // Another site's game with these very moves on that very day is its own
    // game: each site gave it an address.
    final second = File('${dir.path}/second.pgn')
      ..writeAsStringSync(
        game(white: 'me', black: 'someone', date: '2027.09.30', moves: '$played 7. Bb5 Bd7', site: 'https://lichess.org/abcdefgh', elo: '2800'),
      );
    Future<(List<PrepGame>, GameTreeBuildResult)> read(String name, List<(File, String)> files) async {
      final db = '${dir.path}/$name.sqlite';
      final built = runGameTreeBuild(
        GameTreeBuildRequest(
          dbPath: db,
          sources: [for (final (file, kind) in files) GameTreeSourceFile(path: file.path, kind: kind)],
          aliases: const ['me', 'me, myself'],
        ),
      );
      final store = GameTreeStore.open(name, db, playerScope: true)!;
      addTearDown(store.close);
      expect(store.sharedGames, built.shared);
      final rows = await store.loadGames();
      return ([for (var i = 0; i < rows.length; i++) PrepGame.fromIndex(rows[i], i)], built);
    }

    final (all, built) = await read('all', [(database, 'chessever'), (site, 'chesscom'), (second, 'lichess')]);
    // Two in the database, two on the site, one on the other: five games
    // stored, four played.
    expect(built.shared, 1);
    expect(all, hasLength(4));
    // The first source to bring the game keeps it.
    expect(all.where((g) => g.source == PrepSource.chessever), hasLength(2));
    expect(all.where((g) => g.source == PrepSource.chesscom).single.date, DateTime.utc(2027, 9, 30));
    expect(all.where((g) => g.source == PrepSource.lichess), hasLength(1));
    final combined = PrepStats.of(all, ratingAccount: 'database.pgn');
    expect(combined.overall.wins, 4);
    expect(combined.overall.total, 4);
    expect(combined.accounts, 3);

    // Each source alone still holds everything it was given.
    final (alone, single) = await read('site', [(site, 'chesscom')]);
    expect(single.shared, 0);
    expect(alone, hasLength(2));

    // Three sources are three rating scales. Every rating figure of the
    // three together is the asked-for source's, never an average across.
    final (own, _) = await read('database', [(database, 'chessever')]);
    final database_ = PrepStats.of(own);
    expect(combined.ratingPath, endsWith('database.pgn'));
    expect(combined.ratingSource, PrepSource.chessever);
    expect(combined.currentRating, database_.currentRating);
    expect(combined.peakRating, 2611);
    expect(combined.averageOpponent, database_.averageOpponent);
    expect(combined.averageOpponent, 2611);
    expect(combined.performance, database_.performance);
    // Without a say, the source with most rated games is followed.
    expect(PrepStats.of(alone).averageOpponent, 3000);
  });

  test('every About count is the number of games its tap lists', () {
    var index = 0;
    PrepGame g({
      bool? white = true,
      String result = '1-0',
      String opponent = 'Rival',
      PrepTimeControl? speed = PrepTimeControl.blitz,
      int year = 2026,
      String? eco = 'B90',
    }) => PrepGame(
      index: index++,
      source: PrepSource.chessever,
      white: white == false ? opponent : 'Me',
      black: white == false ? 'Me' : opponent,
      result: result,
      plies: 60,
      date: DateTime.utc(year, 3, 4),
      speed: speed,
      eco: eco,
      playerIsWhite: white,
    );
    final games = [
      g(),
      g(result: '0-1'),
      g(result: '1/2-1/2', speed: PrepTimeControl.rapid, year: 2025),
      g(white: false, result: '0-1', eco: 'C65'),
      // Unfinished: no result to score, still a game with that colour,
      // opening, opponent, clock and year.
      g(result: '*'),
      g(white: false, result: '*', eco: 'C65', year: 2025),
      // The player's side unknown: in the slice, scored nowhere.
      g(white: null, opponent: 'Rival'),
      g(white: null, speed: PrepTimeControl.rapid, year: 2025, eco: 'C65'),
    ];
    final s = PrepStats.of(games);
    int listed(PrepFilter filter) => filter.apply(games).length;
    const all = PrepFilter();

    expect(s.games, games.length);
    expect(s.overall.total, 4);
    for (final (outcome, shown) in [
      (PrepOutcome.win, s.overall.wins),
      (PrepOutcome.draw, s.overall.draws),
      (PrepOutcome.loss, s.overall.losses),
    ]) {
      expect(shown, listed(all.copyWith(outcome: outcome)), reason: '$outcome');
    }
    expect(s.whiteGames, listed(all.copyWith(side: PrepSide.white)));
    expect(s.blackGames, listed(all.copyWith(side: PrepSide.black)));
    expect((s.whiteGames, s.asWhite.total), (4, 3));
    expect((s.blackGames, s.asBlack.total), (2, 1));
    for (final (side, lines) in [
      (PrepSide.white, s.whiteOpenings),
      (PrepSide.black, s.blackOpenings),
    ]) {
      expect(lines, isNotEmpty);
      for (final line in lines) {
        expect(
          line.games,
          listed(all.copyWith(side: side, eco: line.eco)),
          reason: '${line.eco} $side',
        );
      }
    }
    for (final (speed, shown) in s.clocks) {
      expect(shown, listed(all.withSpeed(speed)), reason: '$speed');
    }
    expect(s.clocks.fold(0, (sum, c) => sum + c.$2), games.length);
    for (final year in s.byYear) {
      expect(year.total, listed(all.copyWith(year: year.year)));
    }
    expect(s.byYear.fold(0, (sum, y) => sum + y.total), games.length);
    expect(s.lengths.fold(0, (sum, n) => sum + n), games.length);
    for (final opponent in s.opponents) {
      expect(opponent.games, listed(all.copyWith(opponent: opponent.name)));
    }
    expect(s.opponents.single.games, 6);
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
