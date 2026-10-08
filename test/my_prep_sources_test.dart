import 'dart:io';
import 'dart:typed_data';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_player.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/services/game_tree/game_tree_builder.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';
import 'package:dio/dio.dart';
import 'package:dartchess/dartchess.dart' show kInitialFEN;
import 'package:flutter_test/flutter_test.dart';

const databasePlayer = GamebasePlayer(
  id: 'player-uuid',
  fideId: '1234567',
  name: 'Player, Local',
  gender: PlayerGender.male,
  fed: 'TUR',
  title: 'FM',
  ratingClassical: 2100,
  ratingRapid: 2080,
  ratingBlitz: 2050,
);

String sourceGame(
  String white,
  String black, {
  String site = 'Local club',
  String date = '2026.10.01',
  String result = '1-0',
}) =>
    '''
[Event "Source regression"]
[Site "$site"]
[Date "$date"]
[White "$white"]
[Black "$black"]
[Result "$result"]
[WhiteElo "2100"]
[BlackElo "2000"]
[TimeControl "180+0"]
[ECO "C20"]

1. e4 e5 2. Nf3 Nc6 $result
''';

class _PgnAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      sourceGame('Player, Local', 'Opponent'),
      status,
      headers: {
        'content-type': ['application/x-chess-pgn'],
        'x-game-count': ['1'],
      },
    );
  }
}

void main() {
  test(
    'date windows anchor to the selected source, including historical players',
    () {
      final games = [
        PrepGame(
          index: 0,
          source: PrepSource.lichess,
          white: 'Player',
          black: 'A',
          result: '1-0',
          plies: 4,
          date: DateTime.utc(2010, 1, 31),
        ),
        PrepGame(
          index: 1,
          source: PrepSource.lichess,
          white: 'Player',
          black: 'B',
          result: '0-1',
          plies: 4,
          date: DateTime.utc(2010, 1, 1),
        ),
        PrepGame(
          index: 2,
          source: PrepSource.lichess,
          white: 'Player',
          black: 'C',
          result: '1-0',
          plies: 4,
          date: DateTime.utc(2009, 12, 31),
        ),
        PrepGame(
          index: 3,
          source: PrepSource.chesscom,
          white: 'Player',
          black: 'D',
          result: '1-0',
          plies: 4,
          date: DateTime.utc(2026, 10, 1),
        ),
        const PrepGame(
          index: 4,
          source: PrepSource.lichess,
          white: 'Player',
          black: 'E',
          result: '1-0',
          plies: 4,
        ),
      ];
      const filter = PrepFilter(
        source: PrepSource.lichess,
        window: PrepStatsWindow.thirtyDays,
      );
      expect(filter.apply(games).map((g) => g.black), ['A', 'B']);
      expect(
        filter.copyWith(window: PrepStatsWindow.all).apply(games),
        hasLength(4),
      );
    },
  );

  test('opening drill-down includes variations with different ECO codes', () {
    const games = [
      PrepGame(
        index: 0,
        source: PrepSource.lichess,
        white: 'Player',
        black: 'A',
        result: '1-0',
        plies: 4,
        playerIsWhite: true,
        eco: 'B20',
        opening: 'Sicilian Defense: Wing Gambit',
      ),
      PrepGame(
        index: 1,
        source: PrepSource.lichess,
        white: 'Player',
        black: 'B',
        result: '0-1',
        plies: 4,
        playerIsWhite: true,
        eco: 'B21',
        opening: 'Sicilian Defense: Smith-Morra Gambit',
      ),
      PrepGame(
        index: 2,
        source: PrepSource.lichess,
        white: 'Player',
        black: 'C',
        result: '1-0',
        plies: 4,
        playerIsWhite: true,
        eco: 'C20',
        opening: 'King’s Pawn Game',
      ),
    ];
    final line = PrepStats.of(games).whiteOpenings.first;
    expect(line.name, 'Sicilian Defense');
    final filter = PrepFilter(side: PrepSide.white, opening: line.name);
    expect(filter.apply(games).length, line.tally.total);
    expect(filter.apply(games).map((g) => g.eco), ['B20', 'B21']);
    expect(filter.copyWith(opening: null).apply(games), hasLength(3));
  });

  test('database identity uses UUID and preserves both PGN name forms', () {
    final account = PrepAccount.fromPlayer(databasePlayer);
    expect(account.key, 'chessever:player-uuid');
    expect(account.displayName, 'Local Player');
    expect(account.username, 'Player, Local');
    expect(account.fideId, '1234567');
    expect(account.bestRating, 2100);
    final profile = PrepProfile(
      id: 'p',
      kind: PrepKind.opponent,
      name: 'Local Player',
      createdAtMs: 1,
      accounts: [account],
    );
    expect(profile.aliases, containsAll(['player, local', 'local player']));
    final restored = PrepProfile.fromJson(profile.toJson())!;
    expect(restored.accounts.single.key, account.key);
    expect(restored.aliases, profile.aliases);
    expect(restored.fideId, profile.fideId);
  });

  test(
    'database PGN name variants retain results and colour filters',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'prep_name_variants',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final profile = PrepProfile(
        id: 'name-variants',
        kind: PrepKind.opponent,
        name: 'Vasif Durarbayli',
        createdAtMs: 1,
        accounts: [
          PrepAccount.fromPlayer(
            databasePlayer.copyWith(name: 'Durarbayli, Vasif'),
          ),
        ],
      );
      final names = [
        'Durarbayli, Vasif',
        'Durarbayli,Vasif',
        'Durarbayli,V',
        'Durarbayli, V.',
      ];
      final pgn = File('${directory.path}/database.pgn')
        ..writeAsStringSync(
          [
            for (final (i, name) in names.indexed)
              sourceGame(
                i.isEven ? name : 'Opponent',
                i.isEven ? 'Opponent' : name,
                date: '2026.10.0${i + 1}',
                result: i.isEven ? '1-0' : '0-1',
              ),
            sourceGame('Durarbayli,Vugar', 'Opponent', date: '2026.10.05'),
          ].join('\n'),
        );
      final dbPath = '${directory.path}/tree.sqlite';
      runGameTreeBuild(
        GameTreeBuildRequest(
          dbPath: dbPath,
          sources: [GameTreeSourceFile(path: pgn.path, kind: 'chessever')],
          aliases: profile.aliases.toList(),
        ),
      );
      final store = GameTreeStore.open(profile.id, dbPath, playerScope: true)!;
      addTearDown(store.close);
      final rows = await store.loadGames();
      final games = [
        for (final (i, row) in rows.indexed) PrepGame.fromIndex(row, i),
      ];
      expect(PrepStats.of(games).overall.wins, 4);
      expect(
        games.singleWhere((g) => g.white == 'Durarbayli,Vugar').playerIsWhite,
        isNull,
      );
      for (final side in [1, 2]) {
        final matches = await store.positionGames(
          GameTreePositionQuery(fen: kInitialFEN, side: side),
        );
        expect(matches.total, 2);
      }
    },
  );

  test(
    'online handles stay exact instead of gaining database name variants',
    () {
      const profile = PrepProfile(
        id: 'online',
        kind: PrepKind.opponent,
        name: 'Vasif Durarbayli',
        createdAtMs: 1,
        accounts: [
          PrepAccount(source: PrepSource.lichess, username: 'Durarbayli,Vasif'),
        ],
      );
      expect(profile.aliases, {'durarbayli,vasif'});
    },
  );

  test(
    'non-FIDE database players keep UUID identity without a fake FIDE ID',
    () {
      final account = PrepAccount.fromPlayer(
        databasePlayer.copyWith(fideId: '0'),
      );
      expect(account.fideId, isNull);
      expect(account.externalId, databasePlayer.id);
    },
  );

  test(
    'detaching the database retains the person identity across restarts',
    () {
      final account = PrepAccount.fromPlayer(databasePlayer);
      final profile = PrepProfile(
        id: 'p',
        kind: PrepKind.opponent,
        name: 'Local Player',
        createdAtMs: 1,
        accounts: [account],
      );
      final detached = PrepProfile.fromJson(
        profile.copyWith(accounts: []).toJson(),
      )!;
      expect(detached.accounts, isEmpty);
      expect(detached.fideId, databasePlayer.fideId);
    },
  );

  test('legacy online profiles load with exactly the same source file key', () {
    final profile = PrepProfile.fromJson({
      'id': 'old',
      'name': 'Amateur',
      'kind': 'opponent',
      'createdAtMs': 1,
      'accounts': [
        {'source': 'lichess', 'username': 'AmateurHandle', 'gameCount': 12},
      ],
    })!;
    expect(profile.accounts.single.key, 'lichess:amateurhandle');
    expect(profile.fideId, isNull);
    expect(profile.accounts.single.preferences.range, PrepDateRange.year);
  });

  test('custom date scope is UTC, includes the end day and round-trips', () {
    final preferences = PrepDownloadPreferences(
      range: PrepDateRange.custom,
      fromDate: DateTime(2025, 2, 3, 14),
      toDate: DateTime(2025, 2, 10, 9),
      timeControls: const {PrepTimeControl.blitz},
    );
    expect(
      preferences.fromMs(DateTime.now()),
      DateTime.utc(2025, 2, 3).millisecondsSinceEpoch,
    );
    expect(
      preferences.untilMs,
      DateTime.utc(2025, 2, 11).millisecondsSinceEpoch,
    );
    expect(preferences.validationError, isNull);
    expect(PrepDownloadPreferences.fromJson(preferences.toJson()), preferences);
    expect(
      preferences.scopeKey(DateTime.now()),
      'blitz|${DateTime.utc(2025, 2, 3).millisecondsSinceEpoch}|${preferences.untilMs}',
    );
    expect(
      PrepDownloadPreferences(
        range: PrepDateRange.custom,
        fromDate: DateTime.utc(2025, 2, 11),
        toDate: DateTime.utc(2025, 2, 10),
      ).validationError,
      isNotNull,
    );
  });

  test('empty profiles and multiple accounts from one provider persist', () {
    const empty = PrepProfile(
      id: 'p',
      kind: PrepKind.opponent,
      name: 'Club opponent',
      createdAtMs: 1,
    );
    expect(PrepProfile.fromJson(empty.toJson())!.accounts, isEmpty);
    final profile = empty.copyWith(
      accounts: const [
        PrepAccount(source: PrepSource.chesscom, username: 'AccountOne'),
        PrepAccount(source: PrepSource.chesscom, username: 'AccountTwo'),
        PrepAccount(
          source: PrepSource.manual,
          username: 'club.pgn',
          externalId: 'file-1',
          playerAliases: ['Local Player'],
        ),
      ],
    );
    final back = PrepProfile.fromJson(profile.toJson())!;
    expect(back.accounts, hasLength(3));
    expect(back.aliases, contains('local player'));
    expect(back.accounts.last.key, 'manual:file-1');
  });

  group('player export routes', () {
    late _PgnAdapter adapter;
    late GamebaseRepository repo;
    setUp(() {
      adapter = _PgnAdapter();
      repo = GamebaseRepository(
        Dio()..httpClientAdapter = adapter,
        baseUrl: 'https://example.test',
        apiKey: 'fixture',
      );
    });
    test('FIDE players use the same compact PGN export as desktop', () async {
      final export = await repo.getPlayerGamesPgn(
        playerId: 'uuid',
        fideId: '1234567',
      );
      expect(export?.gameCount, 1);
      expect(
        adapter.requests.single.path,
        'https://example.test/api/player/fide/1234567/games.pgn',
      );
      expect(adapter.requests.single.responseType, ResponseType.plain);
      expect(
        adapter.requests.single.headers['Accept'],
        contains('application/x-chess-pgn'),
      );
    });
    test('players without FIDE records use their database UUID', () async {
      await repo.getPlayerGamesPgn(playerId: 'uuid');
      expect(
        adapter.requests.single.path,
        'https://example.test/api/player/uuid/games.pgn',
      );
    });
    test(
      'an unavailable PGN export never silently falls back to paged JSON',
      () async {
        adapter.status = 404;
        expect(await repo.getPlayerGamesPgn(playerId: 'uuid'), isNull);
        expect(adapter.requests, hasLength(1));
      },
    );
    test('external sources send bounded dates and clock preferences', () async {
      await repo.getExternalPlayerGamesPgn(
        source: GamebaseExternalPlayerSource.chesscom,
        username: 'LocalPlayer',
        dateFromMs: 100,
        untilMs: 200,
        timeControls: {'rapid', 'blitz'},
      );
      expect(
        adapter.requests.single.queryParameters,
        containsPair('until', 200),
      );
      expect(
        adapter.requests.single.queryParameters,
        containsPair('dateFrom', 100),
      );
      expect(
        adapter.requests.single.queryParameters,
        containsPair('timeControls', 'blitz,rapid'),
      );
    });
  });

  group('combined and source trees', () {
    late Directory directory;
    late List<GameTreeSourceFile> sources;
    late PrepProfile profile;
    setUp(() {
      directory = Directory.systemTemp.createTempSync('prep_sources_');
      final accounts = [
        PrepAccount.fromPlayer(databasePlayer),
        const PrepAccount(source: PrepSource.lichess, username: 'LocalHandle'),
        const PrepAccount(source: PrepSource.chesscom, username: 'ChessHandle'),
        const PrepAccount(
          source: PrepSource.manual,
          username: 'club.pgn',
          externalId: 'file-1',
          playerAliases: ['Club Player'],
        ),
      ];
      profile = PrepProfile(
        id: 'p',
        kind: PrepKind.opponent,
        name: 'Local Player',
        createdAtMs: 1,
        accounts: accounts,
      );
      final games = [
        sourceGame(
          'Player, Local',
          'OTB opponent',
        ).replaceAll('[TimeControl "180+0"]\n', ''),
        sourceGame(
          'Online opponent',
          'LocalHandle',
          site: 'https://lichess.org/sourceFixture',
          result: '0-1',
        ),
        sourceGame(
          'ChessHandle',
          'Other opponent',
          site: 'https://chess.com/game/live/fixture',
          date: '2025.09.01',
        ),
        sourceGame('Manual opponent', 'Club Player', result: '1/2-1/2'),
      ];
      sources = [
        for (var i = 0; i < accounts.length; i++)
          GameTreeSourceFile(
            kind: accounts[i].source.name,
            path: (File(
              '${directory.path}/${PrepRepository.gamesFileName(accounts[i])}',
            )..writeAsStringSync(games[i])).path,
          ),
      ];
    });
    tearDown(() => directory.deleteSync(recursive: true));

    Future<List<PrepGame>> indexed(
      List<GameTreeSourceFile> selected, {
      String scope = 'combined',
    }) async {
      final path = '${directory.path}/$scope.sqlite';
      runGameTreeBuild(
        GameTreeBuildRequest(
          dbPath: path,
          sources: selected,
          aliases: profile.aliases.toList(),
        ),
      );
      final store = GameTreeStore.open(scope, path, playerScope: true)!;
      try {
        final games = await store.loadGames();
        return [for (final (i, g) in games.indexed) PrepGame.fromIndex(g, i)];
      } finally {
        store.close();
      }
    }

    test(
      'database games with no clock tags remain in classical games and trees',
      () async {
        final games = await indexed([sources.first], scope: 'database');
        expect(games.single.speed, PrepTimeControl.classical);
        expect(
          const PrepFilter(speed: PrepTimeControl.classical).apply(games),
          hasLength(1),
        );
        final store = GameTreeStore.open(
          'database',
          '${directory.path}/database.sqlite',
          playerScope: true,
        )!;
        try {
          final classical = await store.positionGames(
            const GameTreePositionQuery(fen: kInitialFEN, clock: 3),
          );
          final blitz = await store.positionGames(
            const GameTreePositionQuery(fen: kInitialFEN, clock: 1),
          );
          expect(classical.total, 1);
          expect(blitz.total, 0);
        } finally {
          store.close();
        }
      },
    );
    test(
      'all sources read together and identify the player on either side',
      () async {
        final games = await indexed(sources);
        expect(games, hasLength(4));
        expect(games.map((g) => g.source).toSet(), PrepSource.values.toSet());
        expect(games.every((g) => g.playerIsWhite != null), isTrue);
        final stats = PrepStats.of(games);
        expect(stats.overall.wins, 3);
        expect(stats.overall.draws, 1);
        expect(stats.asBlack.total, 2);
        // FIDE, Lichess and Chess.com scales are never graphed as one rating.
        expect(stats.ratingHistory, isEmpty);
      },
    );
    test(
      'per-source trees contain only that source and removal rebuilds Combined',
      () async {
        await indexed(sources);
        final lichess = await indexed([sources[1]], scope: 'lichess');
        expect(lichess.single.source, PrepSource.lichess);
        final after = await indexed(sources.skip(1).toList());
        expect(after, hasLength(3));
        expect(after.any((g) => g.source == PrepSource.chessever), isFalse);
      },
    );
    test(
      'account and statistics filters keep the exact source file and player perspective',
      () async {
        final games = await indexed(sources);
        final account = profile.accounts[1];
        final filter = PrepFilter(
          source: account.source,
          accountKey: account.key,
          accountFile: PrepRepository.gamesFileName(account),
          outcome: PrepOutcome.win,
          side: PrepSide.black,
          opponent: 'ONLINE OPPONENT',
          year: 2026,
          eco: 'C20',
        );
        expect(filter.apply(games), hasLength(1));
        final reset = filter.copyWith(
          source: null,
          accountKey: null,
          accountFile: null,
          outcome: null,
          side: PrepSide.both,
          opponent: null,
          year: null,
          eco: null,
        );
        expect(reset.apply(games), hasLength(4));
      },
    );
    test(
      'full snapshots retain distinct OTB games and deduplicate repeats without URLs',
      () {
        final path = '${directory.path}/snapshot.pgn';
        final first = sourceGame('Local Player', 'Opponent A');
        final second = sourceGame('Local Player', 'Opponent B');
        expect(
          writePrepGames(
            path: path,
            incoming: '$first\n$second\n$first',
            merge: false,
          ),
          2,
        );
        expect(splitPrepPgn(File(path).readAsStringSync()), hasLength(2));
      },
    );
    test(
      'Combined PGN export deduplicates shared games and keeps independent OTB games',
      () {
        final first = File('${directory.path}/export-a.pgn')
          ..writeAsStringSync(
            sourceGame(
              'Local Player',
              'Opponent A',
              site: 'https://lichess.org/sharedFixture',
            ),
          );
        final second = File('${directory.path}/export-b.pgn')
          ..writeAsStringSync(
            '${first.readAsStringSync()}\n${sourceGame('Local Player', 'Opponent B')}',
          );
        final target = '${directory.path}/combined.pgn';
        expect(
          writeCombinedPrepGames(
            path: target,
            sources: [first.path, second.path],
          ),
          2,
        );
        expect(splitPrepPgn(File(target).readAsStringSync()), hasLength(2));
      },
    );
    test(
      'PGN imports select the stated player and reject a mistaken name before writing',
      () {
        final target = '${directory.path}/import.pgn';
        final pgn =
            '${sourceGame('Club Player', 'Opponent')}\n${sourceGame('Unrelated', 'Opponent')}';
        expect(
          () => writeImportedPrepGames(
            path: target,
            pgn: pgn,
            playerName: 'Typo',
          ),
          throwsA(isA<PrepException>()),
        );
        expect(File(target).existsSync(), isFalse);
        expect(
          writeImportedPrepGames(
            path: target,
            pgn: pgn,
            playerName: 'club player',
          ),
          1,
        );
        expect(File(target).readAsStringSync(), isNot(contains('Unrelated')));
      },
    );
  });
}
