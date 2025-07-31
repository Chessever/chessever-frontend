import 'dart:convert';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesLocalStorage = AutoDisposeProvider<_GamesLocalStorage>((ref) {
  return _GamesLocalStorage(ref);
});

enum _GameSaver { tourId }

class _GamesLocalStorage {
  _GamesLocalStorage(this.ref);

  final Ref ref;

  String getSaveKey(String tourId) => '${_GameSaver.tourId.name}$tourId';

  Future<List<Games>> fetchAndSaveGames(String tourId) async {
    try {
      final games = await ref
          .read(gameRepositoryProvider)
          .getGamesByTourId(tourId);
      final value = _encodeMyGamesList(games);
      await ref
          .read(sharedPreferencesRepository)
          .setStringList(getSaveKey(tourId), value);
      return games;
    } catch (error, _) {
      return <Games>[];
    }
  }

  Future<List<Games>> fetchAndSaveCountrymanGames(String countryCode) async {
    try {
      final games = await ref
          .read(gameRepositoryProvider)
          .getGamesByCountryCode(countryCode);
      return games;
    } catch (error, _) {
      return <Games>[];
    }
  }

  Future<List<Games>> getGames(String tourId) async {
    try {
      final gameStringList = await ref
          .read(sharedPreferencesRepository)
          .getStringList(getSaveKey(tourId));
      if (gameStringList.isNotEmpty) {
        return _decodeMyGamesList(gameStringList);
      }
      return await fetchAndSaveGames(tourId);
    } catch (error, _) {
      return <Games>[];
    }
  }


  Future<List<Games>> getCountrymanGames(String countryCode) async {
    try {
      final loadNow = 25;

      final gameJsonList = await ref
          .read(gameRepositoryProvider)
          .getGamesByCountryCode(countryCode)
          .then((games) => games.map((g) => json.encode(g.toJson())).toList());

      if (gameJsonList.length <= loadNow) {
        return gameJsonList.map((e) => Games.fromJson(json.decode(e))).toList();
      }

      final initial = gameJsonList.take(loadNow).toList();
      final remaining = gameJsonList.skip(loadNow).toList();

      final initialParsed =
          initial.map((e) => Games.fromJson(json.decode(e))).toList();

      // Parse the rest in background isolate
      compute(decodeGamesInIsolate, remaining).then((parsedRemaining) {
        final all = [...initialParsed, ...parsedRemaining];
        ref.read(fullGamesProvider.notifier).state = all;
      });

      return initialParsed;
    } catch (error, _) {
      return <Games>[];
    }
  }

  Future<List<Games>> refresh(String tourId) async {
    try {
      return await fetchAndSaveGames(tourId);
    } catch (error, _) {
      return <Games>[];
    }
  }

  Future<List<Games>> searchGamesByName({
    required String tourId,
    required String query,
  }) async {
    try {
      final games = await getGames(tourId);

      if (query.isEmpty) {
        return games;
      }

      final queryLower = query.toLowerCase().trim();

      final List<MapEntry<Games, double>> gameScores = [];

      for (final game in games) {
        double score = 0.0;

        // Use the new `search` field as the primary matching source
        final searchTerms = game.search ?? [];

        for (final term in searchTerms) {
          final termLower = term.toLowerCase();
          if (termLower == queryLower) {
            score += 120.0; // Exact match
            break;
          } else if (termLower.startsWith(queryLower)) {
            score += 100.0;
          } else if (termLower.contains(queryLower)) {
            score += 80.0;
          }
        }

        if (score > 0) {
          gameScores.add(MapEntry(game, score));
        }
      }

      gameScores.sort((a, b) => b.value.compareTo(a.value));
      const maxResults = 20;
      return gameScores.take(maxResults).map((e) => e.key).toList();
    } catch (e, _) {
      return <Games>[];
    }
  }
}

List<String> _encodeMyGamesList(List<Games> games) =>
    games.map(_encoder).toList();

List<Games> _decodeMyGamesList(List<String> gameStringList) =>
    gameStringList
        .map<Games>((reelsString) => Games.fromJson(_decoder(reelsString)))
        .toList();

String _encoder(Games games) => json.encode(games.toJson());

Map<String, dynamic> _decoder(String gameString) =>
    json.decode(gameString) as Map<String, dynamic>;

final fullGamesProvider = StateProvider<List<Games>>((ref) => []);
