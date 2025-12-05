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

        // Supabase RPC search can get slow on very short queries (e.g. "az").
        // For country-style queries we skip/short-circuit the RPC to avoid timeouts.
        List<GroupBroadcast> broadcasts = [];
        if (!isCountrySearch || trimmedQuery.length >= 3) {
          try {
            broadcasts = await ref
                .read(groupBroadcastRepositoryProvider)
                .searchGroupBroadcastsFromSupabase(trimmedQuery)
                .timeout(const Duration(seconds: 6), onTimeout: () => []);
          } catch (_) {
            broadcasts = [];
          }
        }

        // Country-aware player fetch (directly from chess_players)
        final countryPlayerResults =
            isCountrySearch
                ? await _fetchTopCountryPlayers(
                    fideCode: fideCountryCode!,
                    countryIso2: countryIso2!,
                  )
                : <SearchResult>[];
        final now = DateTime.now();

        int delta(GroupBroadcast b) =>
            (b.dateStart?.difference(now).abs().inSeconds ?? 999999).toInt();

        String key(String s) => s.toLowerCase().trim();

        broadcasts.sort((a, b) {
          final keyA = key(a.name);
          final keyB = key(b.name);
          final qLower = trimmedQuery.toLowerCase();

          /* 1. exact */
          final aExact = keyA == qLower;
          final bExact = keyB == qLower;
          if (aExact && !bExact) return -1;
          if (!aExact && bExact) return 1;

          /* 2. starts-with */
          final aStart = keyA.startsWith(qLower);
          final bStart = keyB.startsWith(qLower);
          if (aStart && !bStart) return -1;
          if (!aStart && bStart) return 1;
          if (aStart && bStart) return keyA.compareTo(keyB);

          /* 3. contains */
          final aContain = keyA.contains(qLower);
          final bContain = keyB.contains(qLower);
          if (aContain && !bContain) return -1;
          if (!aContain && bContain) return 1;
          if (aContain && bContain) return keyA.compareTo(keyB);
          final d = delta(a).compareTo(delta(b));
          if (d != 0) return d;
          return (b.maxAvgElo ?? 0).compareTo(a.maxAvgElo ?? 0);
        });

        final tournamentResults = <SearchResult>[];
        final playerResults = <SearchResult>[];
        final allPlayers = <SearchPlayer>[];
        final liveIds = ref.read(liveBroadcastIdsProvider);

        // Fallback/local cache search to stay resilient when Supabase returns little/slow
        final localSearch = await ref
            .read(groupBroadcastLocalStorage(GroupEventCategory.current))
            .searchWithScoring(trimmedQuery, liveIds);

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

          for (final searchTerm in gb.search) {
            if (_isPlayerName(searchTerm, gb.name)) {
              final player = SearchPlayer.fromSearchTerm(
                searchTerm,
                gb.id,
                gb.name,
              );
              allPlayers.add(player);

              playerResults.add(
                SearchResult(
                  tournament: tourEventModel,
                  score: 90.0,
                  matchedText: searchTerm,
                  type: SearchResultType.player,
                  player: player,
                ),
              );
            }
          }
        }
        final broadcastById = <String, GroupBroadcast>{
          for (final b in broadcasts) b.id: b,
        };

        int deltaPlayer(SearchResult r) {
          final b = broadcastById[r.tournament.id];
          return (b?.dateStart?.difference(now).abs().inSeconds ?? 999999);
        }

        final qLower = trimmedQuery.toLowerCase();

        // Smart matching function that handles word reordering
        bool matchesFlexibly(String query, String playerName) {
          // Normalize: remove commas, extra spaces, convert to lowercase
          String normalize(String s) => s
              .toLowerCase()
              .replaceAll(',', ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();

          final normalizedQuery = normalize(query);
          final normalizedName = normalize(playerName);

          // Split into words
          final queryWords = normalizedQuery.split(' ').where((w) => w.isNotEmpty).toList();
          final nameWords = normalizedName.split(' ').where((w) => w.isNotEmpty).toList();

          if (queryWords.isEmpty) return false;

          // Check if ALL query words match ANY name word (prefix match)
          for (final qWord in queryWords) {
            bool found = false;
            for (final nWord in nameWords) {
              // Exact match or prefix match (e.g., "gir" matches "giri")
              if (nWord == qWord || nWord.startsWith(qWord) || qWord.startsWith(nWord)) {
                found = true;
                break;
              }
            }
            if (!found) return false;
          }
          return true;
        }

        playerResults.retainWhere((r) {
          final fed = r.player?.fed?.toUpperCase();
          if (isCountrySearch && fed == fideCountryCode) {
            return true; // Keep country matches even if name doesn't include query text
          }
          return matchesFlexibly(qLower, r.matchedText);
        });

        // Fetch player ELOs from chess_players table
        final playerNames = playerResults
            .where((r) => r.player != null)
            .map((r) => r.player!.name)
            .toSet()
            .toList();

        final playerEloMap = <String, int>{};
        if (playerNames.isNotEmpty) {
          try {
            final supabase = Supabase.instance.client;
            // Fetch ELO for all matching player names
            final response = await supabase
                .from('chess_players')
                .select('name, rating')
                .filter('name', 'in', '(${playerNames.map((n) => '"$n"').join(',')})');

            for (final row in response as List) {
              final name = row['name'] as String?;
              final rating = row['rating'] as int?;
              if (name != null && rating != null) {
                playerEloMap[name.toLowerCase()] = rating;
              }
            }
          } catch (e) {
            // Ignore ELO fetch errors, continue with default sorting
          }
        }

        // Update player results with ELO ratings
        for (final result in playerResults) {
          if (result.player != null) {
            final elo = playerEloMap[result.player!.name.toLowerCase()];
            if (elo != null) {
              // Create updated player with rating
              final updatedPlayer = SearchPlayer(
                id: result.player!.id,
                name: result.player!.name,
                rating: elo,
                tournamentId: result.player!.tournamentId,
                tournamentName: result.player!.tournamentName,
                fideId: result.player!.fideId,
                fed: result.player!.fed,
                title: result.player!.title,
                gameId: result.player!.gameId,
                roundId: result.player!.roundId,
                isWhitePlayer: result.player!.isWhitePlayer,
              );
              // Update the result's player reference
              playerResults[playerResults.indexOf(result)] = SearchResult(
                tournament: result.tournament,
                score: result.score,
                matchedText: result.matchedText,
                type: result.type,
                player: updatedPlayer,
              );
            }
          }
        }

        // Merge in country player results (dedupe by name, prefer higher Elo)
        if (countryPlayerResults.isNotEmpty) {
          final byName = <String, SearchResult>{
            for (final r in playerResults)
              (r.player?.name.toLowerCase() ?? r.matchedText.toLowerCase()): r,
          };

          for (final countryResult in countryPlayerResults) {
            final keyName =
                countryResult.player?.name.toLowerCase() ??
                countryResult.matchedText.toLowerCase();
            final existing = byName[keyName];
            if (existing == null) {
              byName[keyName] = countryResult;
            } else {
              final existingElo = existing.player?.rating ?? 0;
              final newElo = countryResult.player?.rating ?? 0;
              if (newElo > existingElo) {
                byName[keyName] = countryResult;
              }
            }
          }
          playerResults
            ..clear()
            ..addAll(byName.values);
        }

        // Merge resilient local-search results (helps short/typo queries)
        if (localSearch.tournamentResults.isNotEmpty) {
          final existingIds = {for (final r in tournamentResults) r.tournament.id};
          for (final t in localSearch.tournamentResults) {
            if (!existingIds.contains(t.tournament.id)) {
              tournamentResults.add(t);
            }
          }
        }

        if (localSearch.playerResults.isNotEmpty) {
          final byName = <String, SearchResult>{
            for (final r in playerResults)
              (r.player?.name.toLowerCase() ?? r.matchedText.toLowerCase()): r,
          };
          for (final r in localSearch.playerResults) {
            final keyName = r.player?.name.toLowerCase() ?? r.matchedText.toLowerCase();
            final existing = byName[keyName];
            if (existing == null) {
              byName[keyName] = r;
            } else {
              final existingElo = existing.player?.rating ?? 0;
              final newElo = r.player?.rating ?? 0;
              if (newElo > existingElo) {
                byName[keyName] = r;
              }
            }
          }
          playerResults
            ..clear()
            ..addAll(byName.values);
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

        playerResults.sort((a, b) {
          // 0. Country match boost (when searching by country)
          if (isCountrySearch) {
            final aMatch = a.player?.fed?.toUpperCase() == fideCountryCode;
            final bMatch = b.player?.fed?.toUpperCase() == fideCountryCode;
            if (aMatch != bMatch) return bMatch ? -1 : 1;
          }

          // 1. Match score (higher = better match)
          final aScore = matchScore(a.matchedText, trimmedQuery);
          final bScore = matchScore(b.matchedText, trimmedQuery);
          if (aScore != bScore) return bScore.compareTo(aScore);

          // 2. ELO (higher first)
          final aElo = a.player?.rating ?? 0;
          final bElo = b.player?.rating ?? 0;
          if (aElo != bElo) return bElo.compareTo(aElo);

          // 3. nearest tournament date
          final d = deltaPlayer(a).compareTo(deltaPlayer(b));
          if (d != 0) return d;

          // 4. alphabetical
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

bool _isPlayerName(String searchTerm, String tournamentName) {
  final t = searchTerm.trim().toLowerCase();
  final tn = tournamentName.trim().toLowerCase();

  if (t == tn || t.startsWith('$tn |')) return false;

  if ([
    'chess',
    'tournament',
    'championship',
    'festival',
    'open',
    'classic',
  ].any((w) => t.contains(w))) {
    return false;
  }

  final words = searchTerm.trim().split(' ');
  if (words.length == 1 || (words.length >= 2 && words.length <= 4)) {
    return words.every(
      (w) => w.isNotEmpty && w[0] == w[0].toUpperCase(),
    );
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

    return (rows as List)
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
  } catch (_) {
    return [];
  }
}
