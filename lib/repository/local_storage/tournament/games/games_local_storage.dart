import 'dart:convert';
import 'dart:io';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesLocalStorage = AutoDisposeProvider<GamesLocalStorage>((ref) {
  return GamesLocalStorage(ref);
});

// ============================================================================
// ISOLATE WORKERS — all heavy JSON/gzip work runs off the main thread
// ============================================================================

/// Marker prefix for gzip-compressed cache entries.
const _gzipPrefix = 'gz:';

/// Isolate worker: List<Games> → compressed string ready for SQLite storage.
/// Gzip + base64 keeps the row well under Android's 2 MB CursorWindow limit.
String _encodeAndCompress(List<Games> games) {
  final jsonStrings = games.map((g) => json.encode(g.toJson())).toList();
  final fullJson = json.encode(jsonStrings);
  final compressed = gzip.encode(utf8.encode(fullJson));
  return '$_gzipPrefix${base64.encode(compressed)}';
}

/// Isolate worker: compressed (or legacy raw) cache string → List<Games>.
/// Skips individual corrupted entries instead of throwing away the whole cache.
List<Games> _decompressAndDecode(String cached) {
  String jsonString;
  if (cached.startsWith(_gzipPrefix)) {
    final b64 = cached.substring(_gzipPrefix.length);
    jsonString = utf8.decode(gzip.decode(base64.decode(b64)));
  } else {
    // Legacy uncompressed entry — backwards compatible
    jsonString = cached;
  }

  final jsonList = json.decode(jsonString) as List;
  final games = <Games>[];
  for (final item in jsonList) {
    try {
      games.add(Games.fromJson(json.decode(item as String)));
    } catch (_) {
      // Skip individual corrupted game entries rather than losing all
    }
  }
  return games;
}

class _SearchArguments {
  final List<Games> games;
  final String query;
  _SearchArguments(this.games, this.query);
}

List<Games> _searchGamesWorker(_SearchArguments args) {
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

// ============================================================================
// GAMES LOCAL STORAGE
// ============================================================================

class GamesLocalStorage {
  GamesLocalStorage(this.ref);

  final Ref ref;

  String _getCacheKey(String tourId) => 'games_$tourId';

  /// Fetch games from Supabase, return immediately, compress+cache in background.
  Future<List<Games>> fetchAndSaveGames(String tourId) async {
    try {
      ref.read(loggerProvider).logInfo('Fetching games for tourId: $tourId');

      final games = await ref
          .read(gameRepositoryProvider)
          .getGamesByTourId(tourId);

      // Compress + save entirely in a background isolate — zero main-thread work
      compute(_encodeAndCompress, games).then((compressed) async {
        try {
          final db = ref.read(appDatabaseProvider);
          await db.setCache(key: _getCacheKey(tourId), value: compressed);
        } catch (e) {
          ref.read(loggerProvider).logError(
            'Failed to save games to cache: $e',
            null,
          );
        }
      });

      return games;
    } catch (error, st) {
      ref.read(loggerProvider).logError(error, st);
      return <Games>[];
    }
  }

  /// Read games from cache. Falls through to network fetch on any failure.
  Future<List<Games>> getGames(String tourId) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final entry = await db.getCache(key: _getCacheKey(tourId));

      if (entry != null) {
        // Decompress + decode entirely in a background isolate
        return await compute(_decompressAndDecode, entry.value);
      }
      return await fetchAndSaveGames(tourId);
    } catch (error, _) {
      // Cache corrupt / CursorWindow overflow / decode failure —
      // fall through to fresh network fetch. The next save will write
      // a proper compressed entry, self-healing the cache.
      try {
        return await fetchAndSaveGames(tourId);
      } catch (_) {
        return <Games>[];
      }
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

  Future<List<Games>> getCountrymanGames(String countryCode) async {
    try {
      final loadNow = 25;

      final gameJsonList = await ref
          .read(gameRepositoryProvider)
          .getGamesByCountryCode(countryCode)
          .then(
            (games) => games.map((g) => json.encode(g.toJson())).toList(),
          );

      if (gameJsonList.length <= loadNow) {
        return gameJsonList
            .map((e) => Games.fromJson(json.decode(e)))
            .toList();
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

final fullGamesProvider = StateProvider<List<Games>>((ref) => []);

List<Games> _decodeGamesInIsolate(List<String> gameJsonList) {
  return gameJsonList.map((e) {
    final decoded = json.decode(e) as Map<String, dynamic>;
    return Games.fromJson(decoded);
  }).toList();
}
