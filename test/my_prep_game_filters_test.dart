import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:libcompress/libcompress.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_pgn_intake.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_games_tab.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter_test/flutter_test.dart';

PrepGame fixture({
  int index = 0,
  int? whiteElo = 2000,
  int? blackElo = 2200,
  PrepTimeControl? speed = PrepTimeControl.blitz,
  String? eco = 'B90',
  DateTime? date,
  bool? playerWhite = true,
  int plies = 40,
  PrepSource source = PrepSource.lichess,
  String? url,
}) => PrepGame(
  index: index,
  source: source,
  white: 'ClubPlayer',
  black: 'Opponent',
  result: '1-0',
  plies: plies,
  whiteElo: whiteElo,
  blackElo: blackElo,
  speed: speed,
  eco: eco,
  date: date,
  playerIsWhite: playerWhite,
  url: url,
);

void main() {
  test('desktop game filters combine rather than override each other', () {
    final f = PrepFilter(
      base: GameFilter(
        result: GameResultFilter.whiteWins,
        color: GameColorFilter.white,
        timeControl: GameTimeControlFilter.blitz,
        online: GameOnlineFilter.online,
        eco: const GameEcoFilter(code: 'B9'),
        minYear: 2025,
        maxYear: 2025,
        minRating: 2100,
        maxRating: 2150,
        finish: GameFinishFilter.byMove20,
      ),
    );
    final date = DateTime.utc(2025, 2, 1);
    expect(f.matches(fixture(date: date)), isTrue);
    expect(
      f.matches(fixture(date: date, speed: PrepTimeControl.bullet)),
      isTrue,
    );
    expect(
      f.matches(fixture(date: date, speed: PrepTimeControl.ultrabullet)),
      isTrue,
    );
    for (final game in [
      fixture(date: DateTime.utc(2024)),
      fixture(date: null),
      fixture(date: date, speed: PrepTimeControl.rapid),
      fixture(date: date, playerWhite: false),
      fixture(date: date, playerWhite: null),
      fixture(date: date, eco: 'B20'),
      fixture(date: date, plies: 41),
      fixture(date: date, whiteElo: null, blackElo: null),
      fixture(date: date, source: PrepSource.chessever),
    ]) {
      expect(f.matches(game), isFalse);
    }
  });

  test(
    'unknown metadata is retained until its filter is explicitly applied',
    () {
      final unknown = fixture(
        date: null,
        whiteElo: null,
        blackElo: null,
        eco: null,
        plies: 0,
      );
      expect(PrepFilter(base: GameFilter()).apply([unknown]), [unknown]);
      expect(
        PrepFilter(
          base: GameFilter(finish: GameFinishFilter.byMove25),
        ).matches(unknown),
        isFalse,
      );
      expect(
        PrepFilter(
          base: GameFilter(minRating: 2100),
        ).matches(fixture(whiteElo: null, blackElo: 2150)),
        isTrue,
      );
      expect(
        PrepFilter(
          base: GameFilter(maxRating: 2100),
        ).matches(fixture(whiteElo: 2001, blackElo: 2200)),
        isTrue,
      );
      expect(
        PrepFilter(base: GameFilter(online: GameOnlineFilter.online)).matches(
          fixture(source: PrepSource.manual, url: 'https://lichess.org/a'),
        ),
        isTrue,
      );
      expect(
        PrepFilter(base: GameFilter(online: GameOnlineFilter.otb)).matches(
          fixture(
            source: PrepSource.manual,
            url: 'https://fide.com/tournament',
          ),
        ),
        isTrue,
      );
    },
  );

  test('changing clocks or dialog filters clears competing facets', () {
    final f = PrepFilter(
      base: GameFilter(timeControl: GameTimeControlFilter.blitz),
      outcome: PrepOutcome.loss,
    );
    final rapid = f.withSpeed(PrepTimeControl.rapid);
    expect(rapid.base!.timeControl, GameTimeControlFilter.all);
    expect(
      rapid.matches(fixture(speed: PrepTimeControl.rapid)),
      isFalse,
    ); // loss still selected
    final dialog = rapid.withGameFilter(
      GameFilter(
        color: GameColorFilter.black,
        timeControl: GameTimeControlFilter.rapid,
      ),
    );
    expect(dialog.speed, isNull);
    expect(dialog.outcome, isNull);
    expect(dialog.side, PrepSide.black);
    expect(
      dialog.matches(fixture(speed: PrepTimeControl.rapid, playerWhite: false)),
      isTrue,
    );
  });

  test('multi-key sorting is stable and leaves unknown ratings last', () {
    final games = [
      fixture(index: 0, whiteElo: null),
      fixture(index: 1, whiteElo: 2100, date: DateTime.utc(2024)),
      fixture(index: 2, whiteElo: 2100, date: DateTime.utc(2025)),
      fixture(index: 3, whiteElo: 1900),
    ];
    final sorted = prepSortGames(games, const [
      GameSortCriterion(field: GamebaseSortField.whiteElo),
      GameSortCriterion(field: GamebaseSortField.date),
    ]);
    expect(sorted.map((g) => g.index), [2, 1, 3, 0]);
    expect(games.map((g) => g.index), [0, 1, 2, 3]);
    expect(
      prepSortGames(games, const [
        GameSortCriterion(
          field: GamebaseSortField.whiteElo,
          direction: GamebaseSortDirection.asc,
        ),
      ]).last.index,
      0,
    );
  });

  const pgn =
      '[Event "Club match"]\n[White "ClubPlayer"]\n[Black "Opponent"]\n[Result "1-0"]\n\n1. e4 e5 2. Nf3 Nc6 1-0';
  test('filtered cloud saving parses exactly the selected PGNs', () {
    final games = parsePreparedGames([('selected', pgn)]);
    expect(games.single.gameId, 'selected');
    expect(games.single.metadata['White'], 'ClubPlayer');
    expect(games.single.mainline, hasLength(4));
  });

  test('desktop compressed PGN formats decode to the original text', () {
    final bytes = Uint8List.fromList(utf8.encode(pgn));
    expect(decodePrepPgn(('games.pgn', bytes)), pgn);
    expect(
      decodePrepPgn((
        'games.pgn.bz2',
        Uint8List.fromList(BZip2Encoder().encode(bytes)),
      )),
      pgn,
    );
    expect(decodePrepPgn(('games.PGN.ZST', ZstdCodec().compress(bytes))), pgn);
    expect(
      () => decodePrepPgn(('corrupt.bz2', Uint8List.fromList([1, 2, 3]))),
      throwsA(isA<PrepException>()),
    );
    expect(
      () => decodePrepPgn(('corrupt.zst', Uint8List.fromList([1, 2, 3]))),
      throwsA(isA<PrepException>()),
    );
  });
}
