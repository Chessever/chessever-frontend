import 'package:flutter/foundation.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
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
import 'package:supabase_flutter/supabase_flutter.dart';

const _countryPlayerCacheTtl = Duration(minutes: 10);
final _countryPlayerCache = <String, _CountryPlayerCacheEntry>{};

final supabaseCombinedSearchProvider =
    AutoDisposeFutureProvider.family<EnhancedSearchResult, String>(
      (ref, query) async {
        if (query.trim().isEmpty) return EnhancedSearchResult.empty();

        final trimmedQuery = query.trim();
        final detectedCountryIso2 = _detectCountryIsoCode(trimmedQuery);
        final detectedFideCode =
            detectedCountryIso2 != null ? CountryUtils.toFideCode(detectedCountryIso2) : null;
        final isCountrySearch = detectedCountryIso2 != null && detectedFideCode != null;
        final countryIso2 = detectedCountryIso2;
        final fideCountryCode = detectedFideCode;
        final normalizedCountryKey = fideCountryCode?.toUpperCase();

        // Always search Supabase RPC for events (searches all: current, past, upcoming)
        // RPC handles country-related searches well and is fast enough
        List<GroupBroadcast> broadcasts = [];
        try {
          broadcasts = await ref
              .read(groupBroadcastRepositoryProvider)
              .searchGroupBroadcastsFromSupabase(trimmedQuery)
              .timeout(const Duration(seconds: 6), onTimeout: () => []);
        } catch (e) {
          debugPrint('[Search] RPC error: $e');
          broadcasts = [];
        }
        debugPrint('[Search] Query: "$trimmedQuery", RPC results: ${broadcasts.length}');

        // Country-aware player fetch (directly from chess_players)
        final countryPlayerResults =
            isCountrySearch && normalizedCountryKey != null
                ? await _fetchTopCountryPlayers(
                    fideCode: normalizedCountryKey,
                    countryIso2: countryIso2!,
                  )
                : <SearchResult>[];
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
        final liveIds = ref.read(liveBroadcastIdsProvider);

        // Fallback/local cache search across ALL categories (current, past)
        // Run in parallel for efficiency, with error handling for each
        EnhancedSearchResult localSearchCurrent = EnhancedSearchResult.empty();
        EnhancedSearchResult localSearchPast = EnhancedSearchResult.empty();
        try {
          final results = await Future.wait([
            ref
                .read(groupBroadcastLocalStorage(GroupEventCategory.current))
                .searchWithScoring(trimmedQuery, liveIds)
                .catchError((_) => EnhancedSearchResult.empty()),
            ref
                .read(groupBroadcastLocalStorage(GroupEventCategory.past))
                .searchWithScoring(trimmedQuery, liveIds)
                .catchError((_) => EnhancedSearchResult.empty()),
          ]);
          localSearchCurrent = results[0];
          localSearchPast = results[1];
        } catch (_) {
          // If Future.wait fails, continue with empty local results
        }

        for (final gb in broadcasts) {
          final tourEventModel = GroupEventCardModel.fromGroupBroadcast(
            gb,
            liveIds,
          );

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
          final parts = name
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

        // Search chess_players table - the authoritative source for player data
        final directPlayerResults = await _fetchPlayersByName(
          query: trimmedQuery,
          limit: 25,
        );

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
              final existingHasFideId = existing.player?.fideId != null && existing.player!.fideId! > 0;
              final newHasFideId = countryResult.player?.fideId != null && countryResult.player!.fideId! > 0;
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

        // Merge resilient local-search results from ALL categories (current + past)
        // This ensures we find events even if Supabase RPC is slow or returns limited results
        final allLocalSearches = [localSearchCurrent, localSearchPast];
        for (final localSearch in allLocalSearches) {
          if (localSearch.tournamentResults.isNotEmpty) {
            final existingIds = {for (final r in tournamentResults) r.tournament.id};
            for (final t in localSearch.tournamentResults) {
              if (!existingIds.contains(t.tournament.id)) {
                tournamentResults.add(t);
                existingIds.add(t.tournament.id);
              }
            }
          }

          // Skip local search player results - they lack FIDE data
          // Player search now relies entirely on chess_players table
        }

        // Score how well a player name matches the query
        int matchScore(String playerName, String query) {
          String normalize(String s) => s
              .toLowerCase()
              .replaceAll(',', ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();

          final nQuery = normalize(query);
          final nName = normalize(playerName);

          // Exact match (normalized) = highest score
          if (nName == nQuery) return 100;

          // Check if name starts with query (e.g., "giri" matches "Giri, Anish")
          if (nName.startsWith(nQuery)) return 90;

          // Check if any word in name starts with query
          final nameWords = nName.split(' ');
          if (nameWords.any((w) => w.startsWith(nQuery))) return 85;

          // All query words match name words exactly
          final queryWords = nQuery.split(' ').where((w) => w.isNotEmpty).toList();
          int exactWordMatches = 0;
          for (final qw in queryWords) {
            if (nameWords.contains(qw)) exactWordMatches++;
          }
          if (exactWordMatches == queryWords.length) return 80;

          // Partial word matches
          return 50;
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
            final existingHasFideId = existing.player?.fideId != null && existing.player!.fideId! > 0;
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
          final aScore = matchScore(a.matchedText, trimmedQuery);
          final bScore = matchScore(b.matchedText, trimmedQuery);
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
        return EnhancedSearchResult(
          tournamentResults: tournamentResults,
          playerResults: playerResults,
          allPlayers: allPlayers,
          countryFedCode: fideCountryCode,
        );
      },
    );

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

  // Name match
  final byName = countryService.findByName(trimmed);
  if (byName != null) return byName.countryCode;

  // Try words split
  for (final part in trimmed.split(RegExp(r'[ ,]+'))) {
    final byPart = countryService.findByName(part);
    if (byPart != null) return byPart.countryCode;
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
        .gt('rating', 0)
        .lt('rating', 3300)
        .order('rating', ascending: false)
        .limit(limit);

    final country =
        CountryService().findByCode(countryIso2)?.name ?? fideCode;
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

    final results = (rows as List)
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
Future<List<SearchResult>> _fetchPlayersByName({
  required String query,
  int limit = 10,
}) async {
  if (query.trim().length < 2) return [];

  try {
    final supabase = Supabase.instance.client;
    final searchQuery = query.trim();

    // Use ilike for case-insensitive partial matching
    final rows = await supabase
        .from('chess_players')
        .select('fideid, name, title, rating, country')
        .ilike('name', '%$searchQuery%')
        .gt('rating', 0)
        .order('rating', ascending: false)
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

    final results = (rows as List)
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
  _CountryPlayerCacheEntry({
    required this.results,
    required this.cachedAt,
  });

  final List<SearchResult> results;
  final DateTime cachedAt;

  bool get isFresh => DateTime.now().difference(cachedAt) < _countryPlayerCacheTtl;
}
