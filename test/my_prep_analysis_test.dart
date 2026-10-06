import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/services/player_opening_tree.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_local_gamebase.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:dartchess/dartchess.dart';
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

  PrepAnalysis analyze() => buildPrepAnalysis(
    PrepAnalysisRequest(
      profileId: 'p1',
      aliases: {'me'},
      sources: [(PrepSource.lichess, pgn)],
    ),
  );

  test('parses games newest first, dedupes by URL and finds the player', () {
    final a = analyze();
    expect(a.games, hasLength(3));
    expect(a.games.last.date, DateTime.utc(2025, 1, 2));
    expect(a.games.first.playerIsWhite, isTrue);
    expect(a.games.last.playerIsWhite, isFalse);
    expect(a.games.first.speed, PrepTimeControl.blitz);
  });

  test('stats score from the player chair', () {
    final s = PrepStats.of(analyze().games);
    expect(s.overall.wins, 1);
    expect(s.overall.draws, 1);
    expect(s.overall.losses, 1);
    expect(s.asWhite.wins, 1);
    expect(s.asBlack.total, 2);
    expect(s.whiteOpenings.single.name, "King's Pawn Game");
  });

  test('tree buckets by colour and serves the explorer', () {
    final a = analyze();
    final white = a.tree.movesForFen(
      kInitialFEN,
      filters: const PlayerOpeningTreeFilterCriteria(color: 'white'),
    );
    expect(white.single.uci, 'e2e4');
    final all = a.tree.movesForFen(kInitialFEN);
    expect(all.map((m) => m.uci), containsAll(['e2e4', 'd2d4']));
    expect(all.firstWhere((m) => m.uci == 'e2e4').total, 2);
  });

  test('local gamebase answers position games and game lookups', () {
    final a = analyze();
    PrepLocalGamebase.publish(a);
    final rows = GamebaseLocalGames.positionResolver!(
      const GamebaseLocalPositionQuery(
        playerId: 'prep:p1',
        fen: kInitialFEN,
        uci: 'e2e4',
      ),
    )!;
    expect(rows.data, hasLength(2));
    final game = GamebaseLocalGames.gameResolver!(rows.data.first['id'] as String);
    expect(game?.pgn, contains('[Site'));
    expect(LocalPlayerOpeningTrees.resolver!('prep:p1'), same(a.tree));
    expect(GamebaseLocalGames.gameResolver!('prep:nope:0'), isNull);
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
