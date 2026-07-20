import 'dart:convert';

import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_mode_provider.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Trimmed captures of the live `GET /api/miniatures/stats` and
/// `GET /api/miniatures/players` responses. These guard the contract between
/// this app and the gamebase backend: the two live in separate repos, so a
/// silent rename on either side would otherwise only surface as an empty
/// About tab on device.
const String _statsResponse = '''
{
  "status": "success",
  "data": {
    "window": "all",
    "total": 74992,
    "whiteWins": 35805,
    "blackWins": 39187,
    "whiteWinRate": 47.7,
    "blackWinRate": 52.3,
    "draws": 0,
    "avgMoves": 20.2,
    "avgPlies": 39.9,
    "minMoves": 3,
    "maxMoves": 25,
    "avgRating": 2050,
    "maxRating": 2827,
    "ratedSampleSize": 45804,
    "byTimeControl": [
      {"timeControl": "CLASSICAL", "games": 46589, "whiteWins": 22000, "blackWins": 24589},
      {"timeControl": "BLITZ", "games": 21273, "whiteWins": 10000, "blackWins": 11273}
    ],
    "byEcoCategory": [
      {"ecoCategory": "B", "games": 275, "whiteWins": 161, "blackWins": 114},
      {"ecoCategory": null, "games": 12, "whiteWins": 7, "blackWins": 5}
    ],
    "byOpening": [
      {"eco": "B23", "opening": "Sicilian", "games": 776, "avgMoves": 19.7},
      {"eco": "C50", "opening": null, "games": 522, "avgMoves": 22}
    ],
    "daily": [
      {"date": "2026-07-20", "games": 37},
      {"date": "2026-07-19", "games": 129},
      {"date": "2026-07-18", "games": 166}
    ],
    "dailyDays": 3,
    "perDayAverage": 110.7,
    "busiestDay": {"date": "2026-07-18", "games": 166},
    "shortestGames": [
      {
        "gameId": "0933bc1a-5081-4a9e-9219-1a63259c66cb",
        "date": "2025-11-27T00:00:00.000Z",
        "event": "2nd 3-0 Thu 27th Nov 2025",
        "eco": "B00",
        "opening": "Fred",
        "variation": null,
        "result": "W",
        "finalMoveNumber": 3,
        "plyCount": 5,
        "avgRating": 2497,
        "timeControl": "BLITZ",
        "isOnline": true,
        "whiteName": "Janaszak,Daw",
        "blackName": "Aravindh,Chithambaram VR.",
        "whiteElo": 2282,
        "blackElo": 2712,
        "whitePlayerId": "aaa",
        "blackPlayerId": "bbb",
        "whiteFed": "POL",
        "blackFed": "IND"
      }
    ],
    "topRatedGames": []
  }
}
''';

const String _playersResponse = '''
{
  "status": "success",
  "data": {
    "items": [
      {
        "playerId": "c19ee764-c4f2-4af4-9902-48a12ab53553",
        "name": "Carlsen, Magnus",
        "title": "GM",
        "fed": "NOR",
        "fideId": 1503014,
        "rating": 2840,
        "games": 121,
        "wins": 97,
        "losses": 24,
        "fastestWin": 16,
        "peakAvgRating": 2827
      },
      {
        "playerId": "fb77c0bd-727d-4071-9264-d6c12648f818",
        "name": "Su, Fanen",
        "title": null,
        "fed": "Unknown",
        "fideId": null,
        "rating": null,
        "games": 206,
        "wins": 120,
        "losses": 86,
        "fastestWin": null,
        "peakAvgRating": null
      }
    ],
    "total": 45364,
    "limit": 2,
    "offset": 0
  }
}
''';

void main() {
  group('MiniatureStats.fromJson', () {
    final stats = MiniatureStats.fromJson(
      Map<String, dynamic>.from(jsonDecode(_statsResponse) as Map),
    );

    test('reads the headline figures', () {
      expect(stats.total, 74992);
      expect(stats.whiteWins, 35805);
      expect(stats.blackWins, 39187);
      expect(stats.whiteWinRate, closeTo(47.7, 0.001));
      expect(stats.avgMoves, closeTo(20.2, 0.001));
      expect(stats.avgRating, 2050);
      expect(stats.minMoves, 3);
      expect(stats.maxMoves, 25);
      expect(stats.dailyDays, 3);
      expect(stats.perDayAverage, closeTo(110.7, 0.001));
    });

    test('keeps White and Black wins summing to the bucket total', () {
      for (final bucket in stats.byTimeControl) {
        expect(bucket.whiteWins + bucket.blackWins, bucket.games);
      }
    });

    test('pulls the value out of each differently-keyed bucket list', () {
      expect(stats.byTimeControl.first.value, 'CLASSICAL');
      expect(stats.byEcoCategory.first.value, 'B');
      // Games with no ECO letter come back as a null bucket, not a crash.
      expect(stats.byEcoCategory.last.value, isNull);
      expect(stats.byEcoCategory.first.whiteWinRate, closeTo(58.5, 0.1));
    });

    test('falls back to the ECO code when the opening name is blank', () {
      expect(stats.byOpening.first.displayName, 'Sicilian');
      expect(stats.byOpening.last.displayName, 'C50');
      // Postgres returns a whole-number average as an int, not a double.
      expect(stats.byOpening.last.avgMoves, 22);
    });

    test('reads the daily series newest-first with a busiest day', () {
      expect(stats.daily.map((day) => day.date).toList(), [
        '2026-07-20',
        '2026-07-19',
        '2026-07-18',
      ]);
      expect(stats.busiestDay?.date, '2026-07-18');
      expect(stats.busiestDay?.games, 166);
    });

    test('parses notable games into openable miniatures', () {
      expect(stats.shortestGames, hasLength(1));
      final game = stats.shortestGames.single;
      expect(game.finalMoveNumber, 3);
      expect(game.result, 'W');
      expect(game.openingDisplayName, 'Fred');

      // The About tab hands these straight to the board launcher.
      final boardGame = game.toGamesTourModel();
      expect(boardGame.gameId, '0933bc1a-5081-4a9e-9219-1a63259c66cb');
      expect(boardGame.whitePlayer.name, 'Janaszak,Daw');

      expect(stats.topRatedGames, isEmpty);
    });
  });

  group('MiniaturePlayersPage.fromJson', () {
    final page = MiniaturePlayersPage.fromJson(
      Map<String, dynamic>.from(jsonDecode(_playersResponse) as Map),
    );

    test('reads the leaderboard rows', () {
      expect(page.total, 45364);
      expect(page.hasMore, isTrue);
      expect(page.items, hasLength(2));

      final carlsen = page.items.first;
      expect(carlsen.name, 'Carlsen, Magnus');
      expect(carlsen.title, 'GM');
      expect(carlsen.fideId, 1503014);
      expect(carlsen.games, 121);
      expect(carlsen.fastestWin, 16);
      expect(carlsen.winRate, closeTo(80.2, 0.1));
    });

    test('tolerates unlinked players with no title, FIDE id or rating', () {
      final unlinked = page.items.last;
      expect(unlinked.title, isNull);
      expect(unlinked.fideId, isNull);
      expect(unlinked.rating, isNull);
      expect(unlinked.fastestWin, isNull);
      expect(unlinked.games, 206);
    });
  });

  group('MiniaturePlayersQuery', () {
    test('compares by value so the provider refetches only on real changes', () {
      const a = MiniaturePlayersQuery(
        titles: {MiniaturePlayerTitle.gm, MiniaturePlayerTitle.im},
      );
      const b = MiniaturePlayersQuery(
        titles: {MiniaturePlayerTitle.im, MiniaturePlayerTitle.gm},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      expect(a == a.copyWith(titles: {MiniaturePlayerTitle.gm}), isFalse);
      expect(a == a.copyWith(sort: MiniaturePlayerSort.fastest), isFalse);
    });

    test('tab labels stay positionally aligned with the enum', () {
      // SegmentedSwitcher is driven by `miniaturesModeNames.values.toList()`
      // indexed against `MiniaturesScreenMode.values`, and the screen's
      // PageView children are ordered by hand. If the map and the enum ever
      // disagree, tapping a tab silently opens a different one.
      expect(
        miniaturesModeNames.keys.toList(),
        MiniaturesScreenMode.values,
      );
      expect(miniaturesModeNames.values.toList(), [
        'About',
        'Games',
        'Players',
      ]);
    });

    test('screen lands on Games, not on the first tab in the strip', () {
      // About is index 0 so it reads first, but the list is what the screen is
      // for. MiniaturesScreen seeds its PageController from this default.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(selectedMiniaturesModeProvider),
        MiniaturesScreenMode.games,
      );
    });

    test('clearSearch wins over a passed search value', () {
      const query = MiniaturePlayersQuery(search: 'carlsen');
      expect(query.copyWith(clearSearch: true).search, isNull);
    });
  });
}
