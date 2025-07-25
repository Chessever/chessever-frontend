import 'dart:convert';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesLocalStorage = AutoDisposeProvider<_GamesLocalStorage>((ref) {
  return _GamesLocalStorage(ref);
});

class _GamesLocalStorage {
  _GamesLocalStorage(this.ref);

  final Ref ref;

  Future<List<Games>> fetchAndSaveGames(String tourId) async {
    try {
      final games = await ref
          .read(gameRepositoryProvider)
          .getGamesByTourId(tourId);
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

      // Create a list of tours with their relevance scores
      final List<MapEntry<Games, double>> gameScore = [];

      for (final game in games) {
        double score = 0.0;

        // Search in tournament name (highest weight)
        final nameLower = game.name?.toLowerCase();
        if (nameLower != null) {
          if (nameLower.contains(queryLower)) {
            if (nameLower.startsWith(queryLower)) {
              score += 100.0; // Exact start match gets highest score
            } else {
              score += 80.0; // Contains match gets high score
            }
          } else {
            // Check for partial word matches in name
            final nameWords = nameLower.split(' ');
            for (final word in nameWords) {
              if (word.startsWith(queryLower)) {
                score += 60.0;
              } else if (word.contains(queryLower)) {
                score += 40.0;
              }
            }
          }
        }

        // Search in location (medium weight)
        final locationLower = game.tourSlug.toLowerCase();
        if (locationLower.isNotEmpty) {
          if (locationLower.contains(queryLower)) {
            if (locationLower.startsWith(queryLower)) {
              score += 50.0;
            } else {
              score += 30.0;
            }
          } else {
            // Check for partial word matches in location
            final locationWords = locationLower.split(' ');
            for (final word in locationWords) {
              if (word.startsWith(queryLower)) {
                score += 25.0;
              } else if (word.contains(queryLower)) {
                score += 15.0;
              }
            }
          }
        }

        // Search in notable players (lower weight)
        final players = game.players?.map((e) => e.name) ?? <String>[];
        for (final player in players) {
          final playerLower = player.toLowerCase();
          if (playerLower.contains(queryLower)) {
            if (playerLower.startsWith(queryLower)) {
              score += 20.0;
            } else {
              score += 10.0;
            }
          } else {
            // Check for partial word matches in player names
            final playerWords = playerLower.split(' ');
            for (final word in playerWords) {
              if (word.startsWith(queryLower)) {
                score += 15.0;
              } else if (word.contains(queryLower)) {
                score += 8.0;
              }
            }
          }
        }

        // Search in notable players (lower weight)
        final playerTitle = game.players?.map((e) => e.title) ?? <String>[];
        for (final title in playerTitle) {
          final titleLower = title!.toLowerCase();
          if (titleLower.contains(queryLower)) {
            if (titleLower.startsWith(queryLower)) {
              score += 20.0;
            } else {
              score += 10.0;
            }
          } else {
            // Check for partial word matches in player names
            final playerWords = titleLower.split(' ');
            for (final word in playerWords) {
              if (word.startsWith(queryLower)) {
                score += 15.0;
              } else if (word.contains(queryLower)) {
                score += 8.0;
              }
            }
          }
        }

        // Only include tours with a minimum relevance score
        if (score > 0) {
          gameScore.add(MapEntry(game, score));
        }
      }

      // Sort by relevance score (highest first) and return the tours
      gameScore.sort((a, b) => b.value.compareTo(a.value));

      // Return only the most relevant results (top matches)
      const maxResults = 20; // Adjust this number as needed
      final relevantTours =
          gameScore.take(maxResults).map((entry) => entry.key).toList();

      return relevantTours;
    } catch (error, _) {
      return <Games>[];
    }
  }
}

List<String> _encodeMyReelsList(List<Games> games) =>
    games.map(_encoder).toList();

List<Games> _decodeMyReelsList(List<String> gameStringList) =>
    gameStringList
        .map<Games>((reelsString) => Games.fromJson(_decoder(reelsString)))
        .toList();

String _encoder(Games games) => json.encode(games.toJson());

Map<String, dynamic> _decoder(String gameString) =>
    json.decode(gameString) as Map<String, dynamic>;

final fullGamesProvider = StateProvider<List<Games>>((ref) => []);
