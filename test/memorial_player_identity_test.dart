import 'dart:convert';

import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/gamebase/memorial_player.dart';
import 'package:chessever2/repository/gamebase/memorial_player_about.dart';
import 'package:chessever2/repository/gamebase/memorial_player_local_search.dart';
import 'package:chessever2/repository/gamebase/memorial_tree_scope.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/utils/player_profile_share_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

FavoritePlayer favorite({
  required String id,
  required String name,
  String? fideId,
  String? memorialSourceIdentity,
}) {
  final now = DateTime.utc(2026, 8, 25);
  return FavoritePlayer(
    id: id,
    userId: 'test-user',
    fideId: fideId,
    playerName: name,
    metadata: {
      if (memorialSourceIdentity != null)
        'memorialSourceIdentity': memorialSourceIdentity,
    },
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Memorial player identity', () {
    test('opening-tree scope round-trips without pretending to be a UUID', () {
      const sourceIdentity = 'memorial:memorial-e03cdf6af47b368c';
      final scope = memorialTreeScopeKey(sourceIdentity);

      expect(scope, 'memorial-source:memorial%3Amemorial-e03cdf6af47b368c');
      expect(memorialSourceIdentityFromTreeScope(scope), sourceIdentity);
      expect(
        memorialSourceIdentityFromTreeScope('ordinary-player-uuid'),
        isNull,
      );
    });

    test('same common name does not merge distinct no-ID identities', () {
      final ordinaryIvanov = favorite(id: 'ordinary', name: 'Ivanov, Igor');
      final memorialIvanov = favorite(
        id: 'memorial-a',
        name: 'Ivanov, Igor',
        memorialSourceIdentity: 'memorial:memorial-aaaaaaaaaaaaaaaa',
      );

      expect(
        favoritePlayerMatchesIdentity(
          ordinaryIvanov,
          playerName: 'Ivanov, Igor',
          memorialSourceIdentity: 'memorial:memorial-aaaaaaaaaaaaaaaa',
        ),
        isFalse,
      );
      expect(
        favoritePlayerMatchesIdentity(
          memorialIvanov,
          playerName: 'Ivanov, Igor',
          memorialSourceIdentity: 'memorial:memorial-bbbbbbbbbbbbbbbb',
        ),
        isFalse,
      );
    });

    test('a valid shared FIDE ID unifies the established player identity', () {
      final fischer = favorite(
        id: 'fischer',
        name: 'Fischer, Robert James',
        fideId: '2000016',
      );
      expect(
        favoritePlayerMatchesIdentity(
          fischer,
          fideId: '2000016',
          playerName: 'Fischer, Robert James',
          memorialSourceIdentity: '2000016',
        ),
        isTrue,
      );
    });

    test('portrait URL uses natural-order, diacritic-safe memorial slugs', () {
      expect(
        memorialPlayerPhotoUrl(
          playerName: 'Tal, Mikhail',
          sourceIdentity: 'memorial:memorial-e03cdf6af47b368c',
        ),
        'https://chessever.com/images/memorial/players/mikhail-tal.webp',
      );
      expect(
        memorialPlayerPhotoUrl(
          playerName: 'Hernández Onna, Román',
          sourceIdentity: '3500063',
        ),
        'https://chessever.com/images/memorial/players/roman-hernandez-onna.webp',
      );
      expect(
        memorialPlayerPhotoUrl(
          playerName: 'Tal, Mikhail',
          sourceIdentity: null,
        ),
        isNull,
      );
      expect(
        memorialPlayerSlug('Hernández Onna, Román'),
        'roman-hernandez-onna',
      );
    });

    test('resolves the immutable public Memorial route', () async {
      final player = await findBundledMemorialPlayerByRouteId(
        'memorial-e03cdf6af47b368c',
      );

      expect(player?.name, 'Tal, Mikhail');
      expect(player?.sourceIdentity, 'memorial:memorial-e03cdf6af47b368c');
    });
  });

  group('Bundled Memorial search', () {
    test('finds a no-FIDE legend in natural name order', () async {
      final results = await searchBundledMemorialPlayers(query: 'Mikhail Tal');

      expect(results, isNotEmpty);
      expect(results.first.player.name, 'Tal, Mikhail');
      expect(
        results.first.player.sourceIdentity,
        'memorial:memorial-e03cdf6af47b368c',
      );
      expect(results.first.player.fideId, isNull);
    });

    test(
      'supports reviewed aliases and FIDE IDs without a network lookup',
      () async {
        final aliasResults = await searchBundledMemorialPlayers(
          query: 'Bill Goichberg',
        );
        final fideResults = await searchBundledMemorialPlayers(
          query: '2000016',
        );

        expect(aliasResults.first.player.name, 'Goichberg, William');
        expect(aliasResults.first.matchedText, 'Bill Goichberg');
        expect(fideResults.first.player.name, 'Fischer, Robert James');
        expect(bundledMemorialCatalogLoadCount, 1);
      },
    );

    test('ships the latest canonical Memorial catalog entry', () async {
      final results = await searchBundledMemorialPlayers(
        query: 'Ahmet Can Yurtseven',
      );

      expect(results, isNotEmpty);
      expect(results.first.player.sourceIdentity, '6300081');
      expect(results.first.player.hasGames, isTrue);
    });

    test(
      'canonicalizes duplicate catalog rows by reviewed source identity',
      () async {
        final results = await searchBundledMemorialPlayers(query: 'Rantanen');

        expect(results, hasLength(1));
        expect(results.single.player.name, 'Rantanen, Yrjö');
        expect(results.single.player.routeId, '500038');
        expect(results.single.player.hasGames, isTrue);
      },
    );
  });

  group('Bundled Memorial overview', () {
    test('ships rating history for every reviewed catalog identity', () async {
      final catalog =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/data/memorial-player-catalog.json',
                ),
              )
              as Map<String, dynamic>;
      final histories =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/data/memorial-player-history.json',
                ),
              )
              as Map<String, dynamic>;
      final catalogRoutes =
          (catalog['players'] as List<dynamic>)
              .map((row) => (row as Map<String, dynamic>)['routeId'])
              .toSet();
      final historyRoutes =
          (histories['profiles'] as List<dynamic>)
              .map((row) => (row as Map<String, dynamic>)['routeId'])
              .toSet();

      expect(histories['count'], catalogRoutes.length);
      expect(historyRoutes, catalogRoutes);
      expect(catalogRoutes.length, 956);
    });

    test('loads authored biography for a no-FIDE identity', () async {
      final overview = await loadBundledMemorialPlayerOverview(
        'memorial:memorial-e03cdf6af47b368c',
      );

      expect(overview, isNotNull);
      expect(overview!.player.name, 'Tal, Mikhail');
      expect(overview.player.birthDate, '1936-11-09');
      expect(overview.player.deathDate, '1992-06-28');
      expect(
        overview.about?.summary.join(' '),
        contains('World Chess Champion'),
      );
      expect(overview.about?.achievements, isNotEmpty);
      expect(overview.history?.points, hasLength(38));
      expect(overview.history?.peakPeriod, '1980-01');
      expect(overview.history?.ratingListSpan?.firstPeriod, '1967-06');
      expect(overview.sources, isNotEmpty);
    });

    test('loads authored biography for a numeric identity', () async {
      final overview = await loadBundledMemorialPlayerOverview('2000016');

      expect(overview, isNotNull);
      expect(overview!.player.name, 'Fischer, Robert James');
      expect(
        overview.about?.summary.join(' '),
        contains('eleventh World Chess Champion'),
      );
      expect(overview.history?.points, hasLength(60));
      expect(overview.history?.peakPeriod, '1972-07');
      expect(overview.history?.ratingListSpan?.lastPeriod, '2007-10');
    });
  });

  group('Memorial profile tabs', () {
    test('memorial profiles retain About, Games, and Events', () {
      expect(playerProfileTabsFor(isMemorial: true), PlayerProfileTab.values);
    });

    test('regular profiles retain all existing tabs', () {
      expect(playerProfileTabsFor(isMemorial: false), PlayerProfileTab.values);
    });
  });

  group('Memorial event history', () {
    test('aggregates exact game rows without merging unrelated years', () {
      final events = buildMemorialPlayerEventsFromRows([
        <String, dynamic>{
          'event': 'Candidates Tournament',
          'canonicalEvent': 'Candidates Tournament 1962',
          'canonicalKey': 'candidates-1962',
          'date': '1962-05-02',
          'outcome': 'win',
          'timeControl': 'CLASSICAL',
          'whiteElo': 2680,
          'blackElo': 2620,
          'site': 'Curacao',
        },
        <String, dynamic>{
          'event': 'Candidates Tournament',
          'canonicalEvent': 'Candidates Tournament 1962',
          'canonicalKey': 'candidates-1962',
          'date': '1962-06-25',
          'outcome': 'draw',
          'timeControl': 'CLASSICAL',
          'whiteElo': 2640,
          'blackElo': 2660,
          'site': 'Curacao',
        },
        <String, dynamic>{
          'event': 'Candidates Tournament',
          'canonicalKey': 'Candidates Tournament',
          'date': '1959-09-07',
          'outcome': 'loss',
          'timeControl': 'CLASSICAL',
        },
        <String, dynamic>{
          'event': 'Candidates Tournament',
          'canonicalKey': 'Candidates Tournament',
          'date': '1971-05-01',
          'outcome': 'win',
          'timeControl': 'CLASSICAL',
        },
      ]);

      expect(events, hasLength(3));
      final curacao = events.firstWhere(
        (event) => event.canonicalKey == 'candidates-1962',
      );
      expect(curacao.gamesPlayed, 2);
      expect(curacao.score, 1.5);
      expect(curacao.startDate, DateTime(1962, 5, 2));
      expect(curacao.endDate, DateTime(1962, 6, 25));
      expect(curacao.dominantTimeControl, 'CLASSICAL');
      expect(curacao.avgElo, 2650);
      expect(curacao.maxElo, 2680);
    });
  });

  group('Memorial profile sharing', () {
    test('uses the canonical Memorial route instead of a live FIDE route', () {
      expect(
        buildPlayerProfileShareUrl(
          null,
          playerName: 'Tal, Mikhail',
          memorialRouteId: 'memorial-e03cdf6af47b368c',
        ),
        'https://chessever.com/player/mikhail-tal/'
        'memorial-e03cdf6af47b368c',
      );
      expect(
        buildPlayerProfileShareUrl(2000016),
        'https://chessever.com/player/2000016',
      );
    });
  });
}
