import 'dart:convert';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesLocalStorage = AutoDisposeProvider<GamesLocalStorage>((ref) {
  return GamesLocalStorage(ref);
});

class _SearchArguments {
  final List<Games> games;
  final String query;

  _SearchArguments(this.games, this.query);
}

Future<List<Games>> _searchGamesWorker(_SearchArguments args) async {
  final queryLower = args.query.toLowerCase().trim();
  final List<MapEntry<Games, double>> gameScores = [];

  for (final game in args.games) {
    double score = 0.0;
    final searchTerms = game.search ?? [];

    for (final term in searchTerms) {
      final termLower = term.toLowerCase();
      if (termLower == queryLower) {
        score += 120.0;
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
}

class GamesLocalStorage {
  GamesLocalStorage(this.ref);

  final Ref ref;

  String _getCacheKey(String tourId) => 'games_$tourId';

  Future<List<Games>> fetchAndSaveGames(String tourId) async {
    try {
      ref.read(loggerProvider).logInfo('Fetching games for tourId: $tourId');

      final games = await ref
          .read(gameRepositoryProvider)
          .getGamesByTourId(tourId);

      // Save to cache in background - don't wait for it
      compute(_encodeMyGamesList, games).then((value) async {
        try {
          final db = ref.read(appDatabaseProvider);
          await db.setCache(key: _getCacheKey(tourId), value: jsonEncode(value));
        } catch (e) {
          ref.read(loggerProvider).logError('Failed to save games to cache: $e', null);
        }
      });

      return games;
    } catch (error, st) {
      ref.read(loggerProvider).logError(error, st);
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
      final db = ref.read(appDatabaseProvider);
      final entry = await db.getCache(key: _getCacheKey(tourId));

      if (entry != null) {
        final jsonList = jsonDecode(entry.value) as List;
        return await compute(_decodeMyGamesList, jsonList.cast<String>());
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

      compute(_decodeGamesInIsolate, remaining).then((parsedRemaining) {
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

      return await compute(_searchGamesWorker, _SearchArguments(games, query));
    } catch (e, _) {
      return <Games>[];
    }
  }
}

List<String> _encodeMyGamesList(List<Games> games) =>
    games.map((g) => json.encode(g.toJson())).toList();

List<Games> _decodeMyGamesList(List<String> gameStringList) =>
    gameStringList
        .map<Games>((s) => Games.fromJson(json.decode(s)))
        .toList();

final fullGamesProvider = StateProvider<List<Games>>((ref) => []);

List<Games> _decodeGamesInIsolate(List<String> gameJsonList) {
  return gameJsonList.map((e) {
    final decoded = json.decode(e) as Map<String, dynamic>;
    return Games.fromJson(decoded);
  }).toList();
}
