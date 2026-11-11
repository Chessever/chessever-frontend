import 'dart:convert';

import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A Combined ("mirror") section copies every game of its real sections under
/// new ids. Cross-event lists must read `is_mirror = false`; a tour's own
/// pages still read its games.

class _Games extends GameRepository {
  _Games(this.client);
  final SupabaseClient client;
  @override
  SupabaseClient get supabase => client;
}

class _Rounds extends RoundRepository {
  _Rounds(this.client);
  final SupabaseClient client;
  @override
  SupabaseClient get supabase => client;
}

({SupabaseClient client, List<Uri> urls}) _recordingClient() {
  final urls = <Uri>[];
  final client = SupabaseClient(
    'https://example.test',
    'placeholder',
    httpClient: MockClient((request) async {
      urls.add(request.url);
      return http.Response(
        jsonEncode(<Object>[]),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  return (client: client, urls: urls);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder',
    );
  });

  test('cross-event game lists leave Combined copies out', () async {
    final rec = _recordingClient();
    addTearDown(rec.client.dispose);
    final repo = _Games(rec.client);

    final reads = <String, Future<Object?> Function()>{
      'player by FIDE id': () => repo.getGamesByFideId('1503014', limit: 5),
      'player by FIDE id, paged': () =>
          repo.getGamesByFideIdPaginated('1503014', limit: 5, offset: 0),
      'player by name': () => repo.getGamesByPlayerName('Carlsen, Magnus'),
      'player by name, paged': () => repo.getGamesByPlayerNamePaginated(
        'Carlsen, Magnus',
        limit: 5,
        offset: 0,
      ),
      'country': () => repo.getGamesByCountryCode('NOR'),
      'country, paged': () =>
          repo.getGamesByCountryCodePaginated(countryCode: 'NOR'),
      'favorites': () => repo.getGamesByMultipleFideIds(fideIds: ['1503014']),
      'feed candidates': () =>
          repo.getFeedCandidateGames(since: DateTime.utc(2026, 11, 1)),
      'search tokens': () =>
          repo.searchGamesBySearchTermsPaginated(terms: ['carlsen']),
      'countrymen search': () =>
          repo.searchCountrymenGames(countryCode: 'NOR', query: 'carlsen'),
      'favorites search': () => repo.searchFavoritesGames(
        fideIds: ['1503014'],
        playerNames: ['Carlsen, Magnus'],
        query: 'carlsen',
      ),
      'event games': () => repo.getGamesFromTourIds(tourIds: ['a', 'b']),
      'favorites on a day': () => repo.getGamesByFideIdsAndDate(
        fideIds: ['1503014'],
        date: DateTime(2026, 11, 1),
      ),
      'countrymen on a day': () => repo.getGamesByCountryAndDate(
        countryCode: 'NOR',
        date: DateTime(2026, 11, 1),
      ),
      'smart event day': () => repo.getCurrentSmartEventGamesOnDay(
        day: DateTime(2026, 11, 1),
        deferNextDayLookup: true,
      ),
    };

    for (final entry in reads.entries) {
      rec.urls.clear();
      await entry.value();
      final gameReads = [
        for (final url in rec.urls)
          if (url.path.endsWith('/games')) url,
      ];
      expect(gameReads, isNotEmpty, reason: entry.key);
      for (final url in gameReads) {
        expect(
          url.queryParameters['is_mirror'],
          'eq.false',
          reason: '${entry.key}: $url',
        );
      }
    }
  });

  test('the default section probes skip a Combined section', () async {
    final rec = _recordingClient();
    addTearDown(rec.client.dispose);

    await _Games(rec.client).getMostRelevantTourId(tourIds: ['a', 'combined']);

    final games = rec.urls.where((u) => u.path.endsWith('/games')).toList();
    final rounds = rec.urls.where((u) => u.path.endsWith('/rounds')).toList();
    expect(games, hasLength(2));
    expect(rounds, hasLength(2));
    for (final url in games) {
      expect(url.queryParameters['is_mirror'], 'eq.false');
    }
    for (final url in rounds) {
      expect(url.queryParameters['tours.is_mirror'], 'eq.false');
      expect(url.queryParameters['select'], contains('!inner(is_mirror)'));
    }

    rec.urls.clear();
    await _Rounds(
      rec.client,
    ).getLatestPlayedRoundTimesByTourIds(['a', 'combined']);
    expect(rec.urls.single.queryParameters['games.is_mirror'], 'eq.false');
  });

  test('the player profile Events tab leaves Combined copies out', () async {
    final rec = _recordingClient();
    addTearDown(rec.client.dispose);

    final reads = <String, Future<Object?> Function()>{
      'by FIDE id': () =>
          playerEventsFromGamesForTest(rec.client, fideId: 1503014),
      'by key with FIDE id': () => playerEventsFromGamesForTest(
        rec.client,
        playerKey: const PlayerProfileKey(
          fideId: 1503014,
          playerName: 'Carlsen, Magnus',
        ),
      ),
      'by key with name only': () => playerEventsFromGamesForTest(
        rec.client,
        playerKey: const PlayerProfileKey(playerName: 'Carlsen, Magnus'),
      ),
    };

    for (final entry in reads.entries) {
      rec.urls.clear();
      await entry.value();
      final gameReads = [
        for (final url in rec.urls)
          if (url.path.endsWith('/games')) url,
      ];
      expect(gameReads, isNotEmpty, reason: entry.key);
      for (final url in gameReads) {
        expect(
          url.queryParameters['is_mirror'],
          'eq.false',
          reason: '${entry.key}: $url',
        );
      }
    }
  });

  test('a tour\'s own games still include its Combined copies', () async {
    final rec = _recordingClient();
    addTearDown(rec.client.dispose);

    await _Games(rec.client).getTopBoardGamesByTourId(tourId: 'combined');

    final url = rec.urls.single;
    expect(url.queryParameters['tour_id'], 'eq.combined');
    expect(url.queryParameters.containsKey('is_mirror'), isFalse);
  });
}
