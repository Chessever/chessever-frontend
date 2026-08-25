import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'memorial_player.dart';

const _catalogAsset = 'assets/data/memorial-player-catalog.json';

Future<List<_IndexedMemorialPlayer>>? _catalogFuture;
int _catalogLoadCount = 0;

class MemorialPlayerSearchMatch {
  const MemorialPlayerSearchMatch({
    required this.player,
    required this.score,
    required this.matchedText,
  });

  final MemorialPlayer player;
  final int score;
  final String matchedText;
}

class _IndexedMemorialPlayer {
  const _IndexedMemorialPlayer({
    required this.player,
    required this.searchNames,
  });

  final MemorialPlayer player;
  final List<_IndexedSearchName> searchNames;
}

class _IndexedSearchName {
  const _IndexedSearchName({required this.value, required this.normalized});

  final String value;
  final String normalized;
}

/// Loads the reviewed catalog once. JSON parsing, identity canonicalization,
/// alias expansion, and text normalization all happen in a worker isolate.
Future<void> warmBundledMemorialPlayerCatalog() async {
  await _loadCatalog();
}

/// Searches only the in-memory, reviewed Memorial catalog. There is
/// deliberately no repository or network fallback here: an unavailable
/// Memorial index must never delay or fail the existing player search path.
Future<List<MemorialPlayerSearchMatch>> searchBundledMemorialPlayers({
  required String query,
  int limit = 25,
  bool includeWithoutGames = true,
}) async {
  final index = await _loadCatalog();
  return _rankIndex(
    index,
    query: query,
    limit: limit,
    includeWithoutGames: includeWithoutGames,
  );
}

@visibleForTesting
int get bundledMemorialCatalogLoadCount => _catalogLoadCount;

List<MemorialPlayerSearchMatch> _rankIndex(
  List<_IndexedMemorialPlayer> index, {
  required String query,
  required int limit,
  required bool includeWithoutGames,
}) {
  if (limit <= 0) return const [];

  final normalizedQuery = _normalize(query);
  final queryTokens =
      normalizedQuery.split(' ').where((token) => token.isNotEmpty).toList();
  final matches = <MemorialPlayerSearchMatch>[];

  for (final entry in index) {
    final player = entry.player;
    if (!includeWithoutGames && !player.hasGames) continue;

    var bestScore = normalizedQuery.isEmpty ? 1 : 0;
    var matchedText = player.name;
    if ((player.fideId ?? '') == normalizedQuery &&
        normalizedQuery.isNotEmpty) {
      bestScore = 1200;
    }

    for (final candidate in entry.searchNames) {
      final candidateScore = _relevance(
        candidate.normalized,
        normalizedQuery,
        queryTokens,
      );
      if (candidateScore > bestScore) {
        bestScore = candidateScore;
        matchedText = candidate.value;
      }
    }

    if (bestScore > 0) {
      matches.add(
        MemorialPlayerSearchMatch(
          player: player,
          score: bestScore,
          matchedText: matchedText,
        ),
      );
    }
  }

  matches.sort((left, right) {
    final score = right.score.compareTo(left.score);
    if (score != 0) return score;
    final rating = right.player.ratingClassical.compareTo(
      left.player.ratingClassical,
    );
    if (rating != 0) return rating;
    return _normalize(
      left.player.name,
    ).compareTo(_normalize(right.player.name));
  });

  return List<MemorialPlayerSearchMatch>.unmodifiable(matches.take(limit));
}

Future<List<_IndexedMemorialPlayer>> _loadCatalog() {
  return _catalogFuture ??= _readCatalog().catchError((Object error) {
    debugPrint('[Memorial search] Bundled catalog unavailable: $error');
    return const <_IndexedMemorialPlayer>[];
  });
}

Future<List<_IndexedMemorialPlayer>> _readCatalog() async {
  _catalogLoadCount++;
  final source = await rootBundle.loadString(_catalogAsset);
  final rows = await compute(_decodeAndIndexCatalogRows, source);
  return List<_IndexedMemorialPlayer>.unmodifiable(
    rows.map((row) {
      final player = MemorialPlayer.fromJson(
        Map<String, dynamic>.from(row['player'] as Map<dynamic, dynamic>),
      );
      final searchNames = (row['searchNames'] as List<dynamic>)
          .map((rawName) {
            final name = Map<String, dynamic>.from(
              rawName as Map<dynamic, dynamic>,
            );
            return _IndexedSearchName(
              value: name['value'] as String,
              normalized: name['normalized'] as String,
            );
          })
          .toList(growable: false);
      return _IndexedMemorialPlayer(player: player, searchNames: searchNames);
    }),
  );
}

List<Map<String, dynamic>> _decodeAndIndexCatalogRows(String source) {
  final decoded = jsonDecode(source) as Map<String, dynamic>;
  final rawRows = decoded['players'] as List<dynamic>? ?? const <dynamic>[];
  final rows = rawRows
      .map((row) => Map<String, dynamic>.from(row as Map<dynamic, dynamic>))
      .toList(growable: false);

  return _canonicalizeJsonRows(rows)
      .map((player) {
        final name = player['name']?.toString() ?? '';
        final aliases = (player['aliases'] as List<dynamic>? ??
                const <dynamic>[])
            .map((alias) => alias.toString());
        final searchableNames = <String>{
          name,
          _naturalOrderName(name),
          ...aliases,
        };
        return <String, dynamic>{
          'player': player,
          'searchNames': [
            for (final searchableName in searchableNames)
              <String, String>{
                'value': searchableName,
                'normalized': _normalize(searchableName),
              },
          ],
        };
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> _canonicalizeJsonRows(
  List<Map<String, dynamic>> rows,
) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final key = row['sourceIdentity']?.toString().trim().toLowerCase() ?? '';
    if (key.isEmpty) continue;
    groups.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(row);
  }

  return groups.values
      .map((group) {
        group.sort(_compareJsonCanonicalCandidates);
        final canonical = Map<String, dynamic>.from(group.first);
        final canonicalName = canonical['name']?.toString() ?? '';
        final aliases = <String>{
          ...(canonical['aliases'] as List<dynamic>? ?? const <dynamic>[]).map(
            (alias) => alias.toString(),
          ),
        };
        for (final alternate in group.skip(1)) {
          aliases.add(alternate['name']?.toString() ?? '');
          aliases.addAll(
            (alternate['aliases'] as List<dynamic>? ?? const <dynamic>[]).map(
              (alias) => alias.toString(),
            ),
          );
        }
        aliases
          ..remove(canonicalName)
          ..remove('');
        canonical['aliases'] = aliases.toList(growable: false);
        return canonical;
      })
      .toList(growable: false);
}

int _compareJsonCanonicalCandidates(
  Map<String, dynamic> left,
  Map<String, dynamic> right,
) {
  var result = _boolScore(
    right['hasGames'],
  ).compareTo(_boolScore(left['hasGames']));
  if (result != 0) return result;
  result = _boolScore(
    right['sourceBacked'],
  ).compareTo(_boolScore(left['sourceBacked']));
  if (result != 0) return result;
  result = _boolScore(
    right['routeId']?.toString() == right['fideId']?.toString(),
  ).compareTo(
    _boolScore(left['routeId']?.toString() == left['fideId']?.toString()),
  );
  if (result != 0) return result;
  result = _intValue(
    right['ratingClassical'],
  ).compareTo(_intValue(left['ratingClassical']));
  if (result != 0) return result;
  return _normalize(
    left['name']?.toString() ?? '',
  ).compareTo(_normalize(right['name']?.toString() ?? ''));
}

int _boolScore(Object? value) => value == true ? 1 : 0;

int _intValue(Object? value) => (value as num?)?.toInt() ?? 0;

int _relevance(String name, String query, List<String> queryTokens) {
  if (query.isEmpty) return 1;
  if (name == query) return 1000;
  if (name.startsWith(query)) return 700;
  if (name.contains(query)) return 500;
  if (queryTokens.isNotEmpty &&
      queryTokens.every((token) => name.contains(token))) {
    return 300;
  }
  return 0;
}

String _naturalOrderName(String value) {
  final parts = value.split(',');
  if (parts.length < 2) return value;
  final lastName = parts.first.trim();
  final givenNames = parts.skip(1).join(' ').trim();
  return '$givenNames $lastName'.trim();
}

String _normalize(String value) {
  var normalized = value.toLowerCase();
  const replacements = <String, String>{
    r'[àáâãäåāăą]': 'a',
    r'[æ]': 'ae',
    r'[çćĉċč]': 'c',
    r'[ďđð]': 'd',
    r'[èéêëēĕėęě]': 'e',
    r'[ĝğġģ]': 'g',
    r'[ĥħ]': 'h',
    r'[ìíîïĩīĭįı]': 'i',
    r'[ĵ]': 'j',
    r'[ķ]': 'k',
    r'[ĺļľŀł]': 'l',
    r'[ñńņňŉŋ]': 'n',
    r'[òóôõöøōŏő]': 'o',
    r'[œ]': 'oe',
    r'[ŕŗř]': 'r',
    r'[śŝşš]': 's',
    r'[ß]': 'ss',
    r'[ţťŧ]': 't',
    r'[þ]': 'th',
    r'[ùúûüũūŭůűų]': 'u',
    r'[ŵ]': 'w',
    r'[ýÿŷ]': 'y',
    r'[źżž]': 'z',
  };
  for (final replacement in replacements.entries) {
    normalized = normalized.replaceAll(
      RegExp(replacement.key),
      replacement.value,
    );
  }
  return normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
