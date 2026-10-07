import 'dart:io';

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/services/game_tree/game_tree_builder.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';
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
    expect(s.whiteOpenings.single.name, "King's Pawn Game");
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
