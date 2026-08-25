import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/gamebase/memorial_player.dart';
import 'package:chessever2/repository/gamebase/memorial_player_about.dart';
import 'package:chessever2/repository/gamebase/memorial_player_local_search.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:flutter_test/flutter_test.dart';

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
    });

    test('loads authored biography for a numeric identity', () async {
      final overview = await loadBundledMemorialPlayerOverview('2000016');

      expect(overview, isNotNull);
      expect(overview!.player.name, 'Fischer, Robert James');
      expect(
        overview.about?.summary.join(' '),
        contains('eleventh World Chess Champion'),
      );
    });
  });

  group('Memorial profile tabs', () {
    test('memorial profiles omit Events but keep Overview and Games', () {
      expect(playerProfileTabsFor(isMemorial: true), const <PlayerProfileTab>[
        PlayerProfileTab.about,
        PlayerProfileTab.games,
      ]);
    });

    test('regular profiles retain all existing tabs', () {
      expect(playerProfileTabsFor(isMemorial: false), PlayerProfileTab.values);
    });
  });
}
