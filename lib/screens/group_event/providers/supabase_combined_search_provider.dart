import 'package:flutter/foundation.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:country_picker/country_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/utils/player_name_search.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _countryPlayerCacheTtl = Duration(minutes: 10);
final _countryPlayerCache = <String, _CountryPlayerCacheEntry>{};

// Cache recent search results to avoid re-fetching
const _searchCacheTtl = Duration(seconds: 30);
final _searchCache = <String, _SearchCacheEntry>{};

class _SearchCacheEntry {
  final EnhancedSearchResult result;
  final DateTime cachedAt;

  _SearchCacheEntry({required this.result, required this.cachedAt});

  bool get isFresh => DateTime.now().difference(cachedAt) < _searchCacheTtl;
}

final supabaseCombinedSearchProvider = AutoDisposeFutureProvider.family<
  EnhancedSearchResult,
  String
>((ref, query) async {
  if (query.trim().length < 2) return EnhancedSearchResult.empty();

  final trimmedQuery = query.trim();

  // Check cache first
  final cacheKey = trimmedQuery.toLowerCase();
  final cached = _searchCache[cacheKey];
  if (cached != null && cached.isFresh) {
    debugPrint('[Search] Cache hit for "$trimmedQuery"');
    return cached.result;
  }
  final detectedCountryIso2 = _detectCountryIsoCode(trimmedQuery);
  final detectedFideCode =
      detectedCountryIso2 != null
          ? CountryUtils.toFideCode(detectedCountryIso2)
          : null;
  final isCountrySearch =
      detectedCountryIso2 != null && detectedFideCode != null;
  final countryIso2 = detectedCountryIso2;
  final fideCountryCode = detectedFideCode;
  final normalizedCountryKey = fideCountryCode?.toUpperCase();

  // Run all searches in parallel for better performance
  final List<String> liveIds =
      ref.read(liveGroupBroadcastIdsProvider).valueOrNull ??
      await ref.read(liveGroupBroadcastIdsProvider.future);

  final parallelResults = await Future.wait([
    // 1. Supabase RPC for events
    ref
        .read(groupBroadcastRepositoryProvider)
        .searchGroupBroadcastsFromSupabase(trimmedQuery)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => <GroupBroadcast>[],
        )
        .catchError((_) => <GroupBroadcast>[]),
    // 2. Country players (if applicable)
    isCountrySearch && normalizedCountryKey != null
        ? _fetchTopCountryPlayers(
          fideCode: normalizedCountryKey,
          countryIso2: countryIso2!,
        )
        : Future.value(<SearchResult>[]),
    // 3. Direct chess_players search
    _fetchPlayersByName(query: trimmedQuery, limit: 25),
    // 4. Local cache searches
    ref
        .read(groupBroadcastLocalStorage(GroupEventCategory.current))
        .searchWithScoring(trimmedQuery, liveIds)
        .catchError((_) => EnhancedSearchResult.empty()),
    ref
        .read(groupBroadcastLocalStorage(GroupEventCategory.past))
        .searchWithScoring(trimmedQuery, liveIds)
        .catchError((_) => EnhancedSearchResult.empty()),
  ]);

  final rawBroadcasts = parallelResults[0] as List<GroupBroadcast>;
  final countryPlayerResults = parallelResults[1] as List<SearchResult>;
  final directPlayerResults = parallelResults[2] as List<SearchResult>;
  final localSearchCurrent = parallelResults[3] as EnhancedSearchResult;
  final localSearchPast = parallelResults[4] as EnhancedSearchResult;

  // Country queries: FTS includes player names + federations in search_fts,
  // so e.g. "norway" surfaces "… Championship for Prisoners" because a player
  // there is from NOR. For a country term, the tournament list should be
  // events whose NAME references the country. Match on word-prefix so short
  // codes ("us", "no") don't slip in via mid-word substrings ("August").
  final qLowerForFilter = trimmedQuery.toLowerCase();
  final broadcasts = isCountrySearch
      ? rawBroadcasts
          .where((b) => _nameStartsWithToken(b.name, qLowerForFilter))
          .toList()
      : rawBroadcasts;

  debugPrint(
    '[Search] Query: "$trimmedQuery", results: ${broadcasts.length} events, ${directPlayerResults.length} players',
  );

  String key(String s) => s.toLowerCase().trim();

  broadcasts.sort((a, b) {
    final keyA = key(a.name);
    final keyB = key(b.name);
    final qLower = trimmedQuery.toLowerCase();

    /* 1. exact match first */
    final aExact = keyA == qLower;
    final bExact = keyB == qLower;
    if (aExact && !bExact) return -1;
    if (!aExact && bExact) return 1;

    /* 2. starts-with beats contains */
    final aStart = keyA.startsWith(qLower);
    final bStart = keyB.startsWith(qLower);
    if (aStart && !bStart) return -1;
    if (!aStart && bStart) return 1;

    /* 3. contains beats no match */
    final aContain = keyA.contains(qLower);
    final bContain = keyB.contains(qLower);
    if (aContain && !bContain) return -1;
    if (!aContain && bContain) return 1;

    /* 4. most recent first (by start date descending) */
    final aDate = a.dateStart;
    final bDate = b.dateStart;
    if (aDate != null && bDate != null) {
      final dateCompare = bDate.compareTo(aDate); // descending: newer first
      if (dateCompare != 0) return dateCompare;
    } else if (aDate != null) {
      return -1; // a has date, b doesn't -> a comes first
    } else if (bDate != null) {
      return 1; // b has date, a doesn't -> b comes first
    }

    /* 5. max avg elo as tiebreaker */
    return (b.maxAvgElo ?? 0).compareTo(a.maxAvgElo ?? 0);
  });

  final tournamentResults = <SearchResult>[];
  final playerResults = <SearchResult>[];
  final allPlayers = <SearchPlayer>[];

  for (final gb in broadcasts) {
    final tourEventModel = GroupEventCardModel.fromGroupBroadcast(gb, liveIds);

    tournamentResults.add(
      SearchResult(
        tournament: tourEventModel,
        score: 100.0,
        matchedText: gb.name,
        type: SearchResultType.tournament,
      ),
    );

    // Note: We no longer create SearchPlayers from broadcast search terms
    // because they lack FIDE IDs. Player search results now come entirely
    // from chess_players table which has comprehensive FIDE data.
  }
  final broadcastById = <String, GroupBroadcast>{
    for (final b in broadcasts) b.id: b,
  };

  /// Returns tournament start date for sorting (null if not found)
  DateTime? playerTournamentDate(SearchResult r) {
    final b = broadcastById[r.tournament.id];
    return b?.dateStart;
  }

  // Normalize name for comparison (handles "Lastname, Firstname" vs "Firstname Lastname")
  String normalizeName(String name) {
    final parts =
        name
            .toLowerCase()
            .replaceAll(',', ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .split(' ')
            .where((p) => p.isNotEmpty)
            .toList();
    parts.sort();
    return parts.join(' ');
  }

  // Add chess_players results (already fetched in parallel)
  playerResults.addAll(directPlayerResults);

  // Merge in country player results (dedupe by normalized name, prefer FIDE ID then higher Elo)
  if (countryPlayerResults.isNotEmpty) {
    final byNormalizedName = <String, SearchResult>{
      for (final r in playerResults)
        normalizeName(r.player?.name ?? r.matchedText): r,
    };

    for (final countryResult in countryPlayerResults) {
      final keyName = normalizeName(
        countryResult.player?.name ?? countryResult.matchedText,
      );
      final existing = byNormalizedName[keyName];
      if (existing == null) {
        byNormalizedName[keyName] = countryResult;
      } else {
        // Prefer player with FIDE ID
        final existingHasFideId =
            existing.player?.fideId != null && existing.player!.fideId! > 0;
        final newHasFideId =
            countryResult.player?.fideId != null &&
            countryResult.player!.fideId! > 0;
        if (newHasFideId && !existingHasFideId) {
          byNormalizedName[keyName] = countryResult;
        } else if (existingHasFideId == newHasFideId) {
          // Both have or both lack FIDE ID - prefer higher rating
          final existingElo = existing.player?.rating ?? 0;
          final newElo = countryResult.player?.rating ?? 0;
          if (newElo > existingElo) {
            byNormalizedName[keyName] = countryResult;
          }
        }
      }
    }
    playerResults
      ..clear()
      ..addAll(byNormalizedName.values);
  }

  await _backfillMissingPlayerRatings(
    playerResults,
    ref.read(gamebaseRepositoryProvider),
  );

  // Merge resilient local-search results from ALL categories (current + past)
  // This ensures we find events even if Supabase RPC is slow or returns limited results
  final allLocalSearches = [localSearchCurrent, localSearchPast];
  for (final localSearch in allLocalSearches) {
    if (localSearch.tournamentResults.isNotEmpty) {
      final existingIds = {for (final r in tournamentResults) r.tournament.id};
      for (final t in localSearch.tournamentResults) {
        if (existingIds.contains(t.tournament.id)) continue;
        // Country queries must hit the event name, not a player's federation.
        if (isCountrySearch &&
            !_nameStartsWithToken(t.tournament.title, qLowerForFilter)) {
          continue;
        }
        tournamentResults.add(t);
        existingIds.add(t.tournament.id);
      }
    }

    // Skip local search player results - they lack FIDE data
    // Player search now relies entirely on chess_players table
  }

  // Final deduplication: prefer players with FIDE ID over those without
  final deduped = <String, SearchResult>{};
  for (final r in playerResults) {
    final key = normalizeName(r.player?.name ?? r.matchedText);
    final existing = deduped[key];
    if (existing == null) {
      deduped[key] = r;
    } else {
      // Prefer the one with FIDE ID
      final existingHasFideId =
          existing.player?.fideId != null && existing.player!.fideId! > 0;
      final newHasFideId = r.player?.fideId != null && r.player!.fideId! > 0;
      if (newHasFideId && !existingHasFideId) {
        deduped[key] = r;
      } else if (existingHasFideId == newHasFideId) {
        // Both have or both lack FIDE ID - prefer higher rating
        final existingRating = existing.player?.rating ?? 0;
        final newRating = r.player?.rating ?? 0;
        if (newRating > existingRating) {
          deduped[key] = r;
        }
      }
    }
  }
  playerResults
    ..clear()
    ..addAll(deduped.values);

  playerResults.sort((a, b) {
    // 0. Country match boost (when searching by country)
    if (isCountrySearch) {
      final aMatch = a.player?.fed?.toUpperCase() == fideCountryCode;
      final bMatch = b.player?.fed?.toUpperCase() == fideCountryCode;
      if (aMatch != bMatch) return bMatch ? -1 : 1;
    }

    // 1. FIDE ID boost - players with FIDE ID are more reliable
    final aHasFideId = a.player?.fideId != null && a.player!.fideId! > 0;
    final bHasFideId = b.player?.fideId != null && b.player!.fideId! > 0;
    if (aHasFideId != bHasFideId) return aHasFideId ? -1 : 1;

    // 2. Match score (higher = better match)
    final aScore = playerNameSearchMatchScore(
      a.player?.name ?? a.matchedText,
      trimmedQuery,
    );
    final bScore = playerNameSearchMatchScore(
      b.player?.name ?? b.matchedText,
      trimmedQuery,
    );
    if (aScore != bScore) return bScore.compareTo(aScore);

    // 3. ELO (higher first)
    final aElo = a.player?.rating ?? 0;
    final bElo = b.player?.rating ?? 0;
    if (aElo != bElo) return bElo.compareTo(aElo);

    // 4. most recent tournament date first
    final aDate = playerTournamentDate(a);
    final bDate = playerTournamentDate(b);
    if (aDate != null && bDate != null) {
      final dateCompare = bDate.compareTo(aDate); // descending: newer first
      if (dateCompare != 0) return dateCompare;
    } else if (aDate != null) {
      return -1; // a has date, b doesn't -> a comes first
    } else if (bDate != null) {
      return 1; // b has date, a doesn't -> b comes first
    }

    // 5. alphabetical
    return a.matchedText.compareTo(b.matchedText);
  });
  if (playerResults.length > 20) {
    playerResults.removeRange(20, playerResults.length);
  }
  // Append country-based players to allPlayers list for completeness
  for (final result in countryPlayerResults) {
    if (result.player != null) {
      allPlayers.add(result.player!);
    }
  }

  final searchResult = EnhancedSearchResult(
    tournamentResults: tournamentResults,
    playerResults: playerResults,
    allPlayers: allPlayers,
    countryFedCode: fideCountryCode,
  );

  // Cache the result
  _searchCache[cacheKey] = _SearchCacheEntry(
    result: searchResult,
    cachedAt: DateTime.now(),
  );

  return searchResult;
});

Future<void> _backfillMissingPlayerRatings(
  List<SearchResult> playerResults,
  GamebaseRepository gamebaseRepository,
) async {
  final lookups = <String, SearchPlayer>{};

  for (final result in playerResults) {
    final player = result.player;
    if (player == null) continue;
    if ((player.rating ?? 0) > 0) continue;

    final lookupKey =
        (player.fideId != null && player.fideId! > 0)
            ? 'fide:${player.fideId}'
            : 'name:${_normalizePlayerLookupName(player.name)}';
    lookups.putIfAbsent(lookupKey, () => player);
  }

  if (lookups.isEmpty) return;

  final resolvedRatings = <String, int?>{};
  await Future.wait(
    lookups.entries.map((entry) async {
      resolvedRatings[entry.key] = await _fetchGamebaseDisplayRating(
        gamebaseRepository,
        entry.value,
      );
    }),
    eagerError: false,
  );

  for (var i = 0; i < playerResults.length; i++) {
    final result = playerResults[i];
    final player = result.player;
    if (player == null || (player.rating ?? 0) > 0) continue;

    final lookupKey =
        (player.fideId != null && player.fideId! > 0)
            ? 'fide:${player.fideId}'
            : 'name:${_normalizePlayerLookupName(player.name)}';
    final fallbackRating = resolvedRatings[lookupKey];
    if (fallbackRating == null || fallbackRating <= 0) continue;

    playerResults[i] = SearchResult(
      tournament: result.tournament,
      score: result.score,
      matchedText: result.matchedText,
      type: result.type,
      player: player.copyWith(rating: fallbackRating),
    );
  }
}

Future<int?> _fetchGamebaseDisplayRating(
  GamebaseRepository gamebaseRepository,
  SearchPlayer player,
) async {
  try {
    final fideId = player.fideId;
    final candidates =
        (fideId != null && fideId > 0)
            ? await gamebaseRepository.getPlayers(
              fideId: fideId.toString(),
              pageSize: 5,
            )
            : await gamebaseRepository.getPlayers(
              name: player.name,
              pageSize: 10,
            );

    if (candidates.isEmpty) return null;

    final normalizedTarget = _normalizePlayerLookupName(player.name);
    GamebasePlayer? bestMatch;

    if (fideId != null && fideId > 0) {
      for (final candidate in candidates) {
        if (candidate.fideId == fideId.toString()) {
          bestMatch = candidate;
          break;
        }
      }
    }

    for (final candidate in candidates) {
      final normalizedCandidate = _normalizePlayerLookupName(candidate.name);
      if (normalizedCandidate == normalizedTarget) {
        bestMatch ??= candidate;
        break;
      }
      if (bestMatch == null &&
          (normalizedCandidate.contains(normalizedTarget) ||
              normalizedTarget.contains(normalizedCandidate))) {
        bestMatch = candidate;
      }
    }

    bestMatch ??= candidates.first;

    final displayRating =
        bestMatch.ratingClassical ??
        bestMatch.ratingRapid ??
        bestMatch.ratingBlitz ??
        bestMatch.highestRating;
    return (displayRating != null && displayRating > 0) ? displayRating : null;
  } catch (_) {
    return null;
  }
}

String _normalizePlayerLookupName(String name) {
  return name
      .toLowerCase()
      .replaceAll(',', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// True when any whitespace/punctuation-separated word in `name` starts with
/// `token` (lowercase). Avoids mid-word false positives like "us" → "August".
bool _nameStartsWithToken(String name, String token) {
  if (token.isEmpty) return true;
  final lowered = name.toLowerCase();
  for (final word in lowered.split(RegExp(r'[^a-z0-9]+'))) {
    if (word.isNotEmpty && word.startsWith(token)) return true;
  }
  return false;
}

/// Detects ISO-2 country code from a user query.
/// Supports ISO2/ISO3/FIDE codes and country names.
String? _detectCountryIsoCode(String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return null;

  final upper = trimmed.toUpperCase();
  final countryService = CountryService();

  // Direct code match (ISO2/ISO3)
  final byCode = countryService.findByCode(upper);
  if (byCode != null) return byCode.countryCode;

  // FIDE code -> ISO2
  final isoFromFide = CountryUtils.toIso2Code(upper);
  if (isoFromFide.length == 2 &&
      countryService.findByCode(isoFromFide) != null) {
    return isoFromFide;
  }

  // Name match — case-insensitive. CountryService.findByName compares names
  // with EXACT case (country.name == name), so "norway" (how users actually
  // type it) misses "Norway" and returns null. That disables country-search
  // filtering entirely, letting unrelated events (player-federation FTS hits,
  // fuzzy local matches) leak into the results. Compare lower-cased instead.
  final allCountries = countryService.getAll();
  final lowerName = trimmed.toLowerCase();
  for (final country in allCountries) {
    if (country.name.toLowerCase() == lowerName) return country.countryCode;
  }

  // Try words split (also case-insensitive) e.g. "norway chess" -> Norway.
  for (final part in trimmed.split(RegExp(r'[ ,]+'))) {
    if (part.isEmpty) continue;
    final lowerPart = part.toLowerCase();
    for (final country in allCountries) {
      if (country.name.toLowerCase() == lowerPart) return country.countryCode;
    }
  }

  return null;
}

/// Fetches top players for a country directly from Supabase chess_players.
Future<List<SearchResult>> _fetchTopCountryPlayers({
  required String fideCode,
  required String countryIso2,
  int limit = 30,
}) async {
  final cached = _countryPlayerCache[fideCode];
  if (cached != null && cached.isFresh) {
    return cached.results;
  }

  try {
    final supabase = Supabase.instance.client;
    final rows = await supabase
        .from('chess_players')
        .select('fideid, name, title, rating, country')
        .eq('country', fideCode)
        .or('rating.lt.3300,rating.is.null')
        .order('rating', ascending: false, nullsFirst: false)
        .limit(limit);

    final country = CountryService().findByCode(countryIso2)?.name ?? fideCode;
    final placeholderTournament = GroupEventCardModel(
      id: 'country_$fideCode',
      title: '$country players',
      dates: '',
      maxAvgElo: 0,
      timeUntilStart: '',
      tourEventCategory: TourEventCategory.completed,
      timeControl: 'Standard',
      endDate: null,
      startDate: null,
      location: country,
      searchTerms: const [],
    );

    final results =
        (rows as List)
            .map((row) {
              final fideId = row['fideid'] as int?;
              final name = row['name'] as String?;
              if (name == null || name.isEmpty) return null;
              final player = SearchPlayer(
                id: 'country_${fideId ?? name.hashCode}',
                name: name,
                title: row['title'] as String?,
                rating: (row['rating'] as num?)?.toInt(),
                fideId: fideId,
                fed: row['country'] as String?,
                tournamentId: placeholderTournament.id,
                tournamentName: placeholderTournament.title,
              );
              return SearchResult(
                tournament: placeholderTournament,
                score: 95.0,
                matchedText: name,
                type: SearchResultType.player,
                player: player,
              );
            })
            .whereType<SearchResult>()
            .toList();

    _countryPlayerCache[fideCode] = _CountryPlayerCacheEntry(
      results: results,
      cachedAt: DateTime.now(),
    );
    return results;
  } catch (_) {
    return [];
  }
}

/// Fetches players by name search directly from Supabase chess_players.
/// Supports flexible word order: "guy gov", "gov guy", "gov, guy" all match "Gov, Guy"
Future<List<SearchResult>> _fetchPlayersByName({
  required String query,
  int limit = 10,
}) async {
  if (query.trim().length < 2) return [];

  try {
    final supabase = Supabase.instance.client;
    final searchQuery = query.trim();

    // Split query into words for flexible matching
    // "guy gov" → ["guy", "gov"] → matches "Gov, Guy"
    final words =
        searchQuery
            .replaceAll(',', ' ')
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty && w.length >= 2)
            .toList();

    if (words.isEmpty) return [];

    // Build query - each word must appear in name (any order)
    var queryBuilder = supabase
        .from('chess_players')
        .select('fideid, name, title, rating, country');

    // Apply ILIKE filter for each word (AND logic)
    for (final word in words) {
      queryBuilder = queryBuilder.ilike('name', '%$word%');
    }

    queryBuilder = queryBuilder.or('rating.lt.3300,rating.is.null');

    final rows = await queryBuilder
        .order('rating', ascending: false, nullsFirst: false)
        .limit(limit);

    final placeholderTournament = GroupEventCardModel(
      id: 'player_search',
      title: 'Player Search',
      dates: '',
      maxAvgElo: 0,
      timeUntilStart: '',
      tourEventCategory: TourEventCategory.completed,
      timeControl: 'Standard',
      endDate: null,
      startDate: null,
      location: '',
      searchTerms: const [],
    );

    final results =
        (rows as List)
            .map((row) {
              final fideId = row['fideid'] as int?;
              final name = row['name'] as String?;
              if (name == null || name.isEmpty) return null;
              final player = SearchPlayer(
                id: 'search_${fideId ?? name.hashCode}',
                name: name,
                title: row['title'] as String?,
                rating: (row['rating'] as num?)?.toInt(),
                fideId: fideId,
                fed: row['country'] as String?,
                tournamentId: placeholderTournament.id,
                tournamentName: placeholderTournament.title,
              );
              return SearchResult(
                tournament: placeholderTournament,
                score: 95.0,
                matchedText: name,
                type: SearchResultType.player,
                player: player,
              );
            })
            .whereType<SearchResult>()
            .toList();

    return results;
  } catch (_) {
    return [];
  }
}

class _CountryPlayerCacheEntry {
  _CountryPlayerCacheEntry({required this.results, required this.cachedAt});

  final List<SearchResult> results;
  final DateTime cachedAt;

  bool get isFresh =>
      DateTime.now().difference(cachedAt) < _countryPlayerCacheTtl;
}
