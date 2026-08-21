import 'dart:isolate';

import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/utils/player_name_search.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:chessever2/widgets/search/search_scorer.dart';
import 'package:flutter/foundation.dart';

class EnhancedSearchResult {
  final List<SearchResult> tournamentResults;
  final List<SearchResult> playerResults;
  final List<SearchPlayer> allPlayers;
  final String? countryFedCode;

  const EnhancedSearchResult({
    required this.tournamentResults,
    required this.playerResults,
    this.allPlayers = const [],
    this.countryFedCode,
  });
  factory EnhancedSearchResult.empty() => const EnhancedSearchResult(
    tournamentResults: [],
    playerResults: [],
    allPlayers: [],
    countryFedCode: null,
  );

  int get totalResults => tournamentResults.length + playerResults.length;

  bool get isEmpty => tournamentResults.isEmpty && playerResults.isEmpty;

  bool get isNotEmpty => !isEmpty;

  bool get hasTournaments => tournamentResults.isNotEmpty;

  bool get hasPlayers => playerResults.isNotEmpty;
}

@immutable
class TournamentSearchScore {
  const TournamentSearchScore({
    required this.index,
    required this.score,
    required this.matchedText,
  });

  final int index;
  final double score;
  final String matchedText;
}

/// Runs the existing tournament matcher unchanged on a helper isolate.
///
/// Only the fields used by [bestFlexibleEventSearchMatch] cross the isolate
/// boundary. Event-model construction and navigation data stay on the main
/// isolate, avoiding a second serialization pass over the full objects.
@visibleForTesting
Future<List<TournamentSearchScore>> scoreTournamentBroadcastsInBackground({
  required String query,
  required List<GroupBroadcast> broadcasts,
}) async {
  final payload = <Map<String, Object?>>[
    for (var index = 0; index < broadcasts.length; index++)
      {
        'index': index,
        'name': broadcasts[index].name,
        'aliases': broadcasts[index].search,
      },
  ];
  final hits = await Isolate.run(
    () => _scoreTournamentPayload(query.toLowerCase().trim(), payload),
    debugName: 'home-search-tournament-scorer',
  );
  return hits
      .map(
        (hit) => TournamentSearchScore(
          index: hit['index']! as int,
          score: hit['score']! as double,
          matchedText: hit['matchedText']! as String,
        ),
      )
      .toList(growable: false);
}

List<Map<String, Object?>> _scoreTournamentPayload(
  String query,
  List<Map<String, Object?>> payload,
) {
  final hits = <Map<String, Object?>>[];
  for (final item in payload) {
    final match = bestFlexibleEventSearchMatch(
      query: query,
      name: item['name']! as String,
      aliases: (item['aliases']! as List).cast<String>(),
    );
    if (match.score <= 10) continue;
    hits.add({
      'index': item['index']! as int,
      'score': match.score,
      'matchedText': match.matchedText,
    });
  }
  return hits;
}

extension GroupBroadcastLocalStorageSearch on GroupBroadcastLocalStorage {
  /// Tournament-only variant of [searchWithScoring]. The combined search
  /// provider discards local player results (they lack FIDE data), so this
  /// skips the per-player-term scoring sweep entirely. That sweep is
  /// Levenshtein-heavy and runs on the UI isolate.
  Future<EnhancedSearchResult> searchTournamentsWithScoring(
    String query, [
    List<String>? liveBroadcastId,
  ]) async {
    try {
      if (query.isEmpty) return EnhancedSearchResult.empty();
      final broadcasts = await getGroupBroadcasts();

      final scores = await scoreTournamentBroadcastsInBackground(
        query: query,
        broadcasts: broadcasts,
      );
      final tournamentResults = <SearchResult>[];

      for (final hit in scores) {
        final gb = broadcasts[hit.index];
        tournamentResults.add(
          SearchResult(
            tournament: GroupEventCardModel.fromGroupBroadcast(
              gb,
              liveBroadcastId ?? [],
            ),
            score: hit.score,
            matchedText: hit.matchedText,
            type: SearchResultType.tournament,
          ),
        );
      }

      return EnhancedSearchResult(
        tournamentResults: tournamentResults,
        playerResults: const [],
        allPlayers: const [],
      );
    } catch (_) {
      return EnhancedSearchResult.empty();
    }
  }

  Future<EnhancedSearchResult> searchWithScoring(
    String query, [
    List<String>? liveBroadcastId,
  ]) async {
    try {
      final broadcasts = await getGroupBroadcasts();
      if (query.isEmpty) {
        return const EnhancedSearchResult(
          tournamentResults: [],
          playerResults: [],
          allPlayers: [],
          countryFedCode: null,
        );
      }

      final queryLower = query.toLowerCase().trim();
      final tournamentResults = <SearchResult>[];
      final playerResults = <SearchResult>[];
      final allPlayers = <SearchPlayer>[];

      final Map<String, List<SearchPlayer>> playersByFirstNameGlobal = {};
      final Map<String, Map<String, List<SearchPlayer>>>
      playersByFirstNamePerTournament = {};

      for (final gb in broadcasts) {
        final tourEventModel = GroupEventCardModel.fromGroupBroadcast(
          gb,
          liveBroadcastId ?? [],
        );

        final tournamentMatch = bestFlexibleEventSearchMatch(
          query: queryLower,
          name: gb.name,
          aliases: gb.search,
        );

        if (tournamentMatch.score > 10.0) {
          tournamentResults.add(
            SearchResult(
              tournament: tourEventModel,
              score: tournamentMatch.score,
              matchedText: tournamentMatch.matchedText,
              type: SearchResultType.tournament,
            ),
          );
        }

        if (!playersByFirstNamePerTournament.containsKey(gb.id)) {
          playersByFirstNamePerTournament[gb.id] = {};
        }

        for (final searchTerm in gb.search) {
          if (_isPlayerName(searchTerm)) {
            final player = SearchPlayer.fromSearchTerm(
              searchTerm,
              gb.id,
              gb.name,
            );

            allPlayers.add(player);

            final firstName = _getFirstName(player.name);

            if (!playersByFirstNameGlobal.containsKey(firstName)) {
              playersByFirstNameGlobal[firstName] = [];
            }
            playersByFirstNameGlobal[firstName]!.add(player);

            if (!playersByFirstNamePerTournament[gb.id]!.containsKey(
              firstName,
            )) {
              playersByFirstNamePerTournament[gb.id]![firstName] = [];
            }
            playersByFirstNamePerTournament[gb.id]![firstName]!.add(player);
          }
        }
      }

      final processedPlayerKeys = <String>{};

      for (final gb in broadcasts) {
        final tourEventModel = GroupEventCardModel.fromGroupBroadcast(
          gb,
          liveBroadcastId ?? [],
        );

        for (final searchTerm in gb.search) {
          if (_isPlayerName(searchTerm)) {
            final player = SearchPlayer.fromSearchTerm(
              searchTerm,
              gb.id,
              gb.name,
            );

            final firstName = _getFirstName(player.name);
            final playersWithSameFirstNameGlobal =
                playersByFirstNameGlobal[firstName] ?? [];
            final playersWithSameFirstNameInTournament =
                playersByFirstNamePerTournament[gb.id]?[firstName] ?? [];

            final playerScore = SearchScorer.calculateScore(
              queryLower,
              searchTerm,
              SearchResultType.player,
            );

            final queryMatchesFirstName =
                firstName.toLowerCase().contains(queryLower) ||
                queryLower.contains(firstName.toLowerCase());

            if (playerScore > 10.0) {
              final playerKey = '${player.name}_${player.tournamentId}';

              if (processedPlayerKeys.contains(playerKey)) {
                continue;
              }

              if (queryMatchesFirstName) {
                if (playersWithSameFirstNameInTournament.length > 1) {
                  final tournamentKey = '${firstName}_${gb.id}';
                  if (!processedPlayerKeys.contains(tournamentKey)) {
                    for (final duplicatePlayer
                        in playersWithSameFirstNameInTournament) {
                      final duplicateKey =
                          '${duplicatePlayer.name}_${duplicatePlayer.tournamentId}';
                      if (!processedPlayerKeys.contains(duplicateKey)) {
                        processedPlayerKeys.add(duplicateKey);

                        final duplicateScore = SearchScorer.calculateScore(
                          queryLower,
                          duplicatePlayer.name,
                          SearchResultType.player,
                        );

                        if (duplicateScore > 5.0) {
                          playerResults.add(
                            SearchResult(
                              tournament: tourEventModel,
                              score: duplicateScore + 10.0,
                              matchedText: duplicatePlayer.name,
                              type: SearchResultType.player,
                              player: duplicatePlayer.copyWith(
                                id: '${duplicatePlayer.id}_same_tournament',
                              ),
                            ),
                          );
                        }
                      }
                    }
                    processedPlayerKeys.add(tournamentKey);
                  }
                } else if (playersWithSameFirstNameGlobal.length > 1) {
                  final globalKey = '${firstName}_global';
                  if (!processedPlayerKeys.contains(globalKey)) {
                    for (final duplicatePlayer
                        in playersWithSameFirstNameGlobal) {
                      final duplicateKey =
                          '${duplicatePlayer.name}_${duplicatePlayer.tournamentId}';
                      if (!processedPlayerKeys.contains(duplicateKey)) {
                        processedPlayerKeys.add(duplicateKey);

                        final duplicateScore = SearchScorer.calculateScore(
                          queryLower,
                          duplicatePlayer.name,
                          SearchResultType.player,
                        );

                        if (duplicateScore > 5.0) {
                          final duplicateTournament =
                              GroupEventCardModel.fromGroupBroadcast(
                                broadcasts.firstWhere(
                                  (b) => b.id == duplicatePlayer.tournamentId,
                                ),
                                liveBroadcastId ?? [],
                              );

                          playerResults.add(
                            SearchResult(
                              tournament: duplicateTournament,
                              score: duplicateScore,
                              matchedText: duplicatePlayer.name,
                              type: SearchResultType.player,
                              player: duplicatePlayer.copyWith(
                                id: '${duplicatePlayer.id}_cross_tournament',
                              ),
                            ),
                          );
                        }
                      }
                    }
                    processedPlayerKeys.add(globalKey);
                  }
                } else {
                  processedPlayerKeys.add(playerKey);
                  playerResults.add(
                    SearchResult(
                      tournament: tourEventModel,
                      score: playerScore,
                      matchedText: searchTerm,
                      type: SearchResultType.player,
                      player: player,
                    ),
                  );
                }
              } else {
                processedPlayerKeys.add(playerKey);
                playerResults.add(
                  SearchResult(
                    tournament: tourEventModel,
                    score: playerScore,
                    matchedText: searchTerm,
                    type: SearchResultType.player,
                    player: player,
                  ),
                );
              }
            }
          }
        }
      }

      return EnhancedSearchResult(
        tournamentResults: tournamentResults,
        playerResults: playerResults,
        allPlayers: allPlayers,
        countryFedCode: null,
      );
    } catch (e) {
      return const EnhancedSearchResult(
        tournamentResults: [],
        playerResults: [],
        allPlayers: [],
        countryFedCode: null,
      );
    }
  }

  String _getFirstName(String fullName) {
    final nameParts = fullName.trim().split(' ');
    return nameParts.isNotEmpty ? nameParts.first : fullName;
  }

  bool _isPlayerName(String searchTerm) {
    final lowerTerm = searchTerm.toLowerCase();

    if (lowerTerm.contains('chess') ||
        lowerTerm.contains('tournament') ||
        lowerTerm.contains('championship') ||
        lowerTerm.contains('festival') ||
        lowerTerm.contains('open') ||
        lowerTerm.contains('classic') ||
        lowerTerm.contains('grand') ||
        lowerTerm.contains('master') ||
        lowerTerm.contains('cup') ||
        lowerTerm.contains('olympiad')) {
      return false;
    }

    final words = searchTerm.trim().split(' ');
    if (words.length >= 2 && words.length <= 4) {
      return words.every(
        (word) =>
            word.isNotEmpty &&
            word[0] == word[0].toUpperCase() &&
            word.length > 1,
      );
    }

    return false;
  }

  Future<Map<String, dynamic>> analyzeDuplicatePatterns(String query) async {
    final allPlayers = await getAllPlayers();
    final playersByFirstName = <String, List<SearchPlayer>>{};
    final tournamentGroups = <String, Map<String, List<SearchPlayer>>>{};

    for (final player in allPlayers) {
      final firstName = _getFirstName(player.name);

      if (!playersByFirstName.containsKey(firstName)) {
        playersByFirstName[firstName] = [];
      }
      playersByFirstName[firstName]!.add(player);

      if (!tournamentGroups.containsKey(player.tournamentId)) {
        tournamentGroups[player.tournamentId] = {};
      }
      if (!tournamentGroups[player.tournamentId]!.containsKey(firstName)) {
        tournamentGroups[player.tournamentId]![firstName] = [];
      }
      tournamentGroups[player.tournamentId]![firstName]!.add(player);
    }

    return {
      'globalDuplicates':
          playersByFirstName.entries
              .where((entry) => entry.value.length > 1)
              .map(
                (entry) => {
                  'firstName': entry.key,
                  'count': entry.value.length,
                  'players':
                      entry.value
                          .map(
                            (p) => {
                              'name': p.name,
                              'tournament': p.tournamentName,
                            },
                          )
                          .toList(),
                },
              )
              .toList(),
      'sameTournamentDuplicates':
          tournamentGroups.entries
              .map(
                (tournamentEntry) => {
                  'tournamentId': tournamentEntry.key,
                  'duplicates':
                      tournamentEntry.value.entries
                          .where((nameEntry) => nameEntry.value.length > 1)
                          .map(
                            (nameEntry) => {
                              'firstName': nameEntry.key,
                              'count': nameEntry.value.length,
                              'players':
                                  nameEntry.value.map((p) => p.name).toList(),
                            },
                          )
                          .toList(),
                },
              )
              .where(
                (tournament) => (tournament['duplicates'] as List).isNotEmpty,
              )
              .toList(),
    };
  }

  Future<List<SearchPlayer>> getAllPlayers([
    List<String>? liveBroadcastId,
  ]) async {
    try {
      final broadcasts = await getGroupBroadcasts();
      final allPlayers = <SearchPlayer>[];

      for (final gb in broadcasts) {
        for (final searchTerm in gb.search) {
          if (_isPlayerName(searchTerm)) {
            final player = SearchPlayer.fromSearchTerm(
              searchTerm,
              gb.id,
              gb.name,
            );
            allPlayers.add(player);
          }
        }
      }

      return allPlayers;
    } catch (e) {
      return [];
    }
  }
}

SearchScoreMatch bestFlexibleEventSearchMatch({
  required String query,
  required String name,
  Iterable<String> aliases = const [],
}) {
  final playerTermMatch = bestPlayerSearchTermMatch(
    query: query,
    searchTerms: aliases,
  );
  final titleMatch = _prioritizeEventTextMatch(
    SearchScorer.bestTournamentMatch(
      query: query,
      name: name,
      aliases: aliases,
    ),
  );
  final namedTitleMatch = _bestNamedEventTitleTokenMatch(
    query: query,
    name: name,
    aliases: aliases,
  );
  final prioritizedNamedTitleMatch = _prioritizeEventTextMatch(namedTitleMatch);

  var bestMatch = titleMatch;
  if (playerTermMatch.score > bestMatch.score) {
    bestMatch = playerTermMatch;
  }
  if (prioritizedNamedTitleMatch.score > bestMatch.score) {
    bestMatch = prioritizedNamedTitleMatch;
  }

  return bestMatch;
}

SearchScoreMatch _prioritizeEventTextMatch(SearchScoreMatch match) {
  const eventTextMatchPriorityFloor = 91.0;
  if (match.score <= 0 || match.score >= eventTextMatchPriorityFloor) {
    return match;
  }
  return SearchScoreMatch(
    score: eventTextMatchPriorityFloor,
    matchedText: match.matchedText,
  );
}

SearchScoreMatch bestPlayerSearchTermMatch({
  required String query,
  required Iterable<String> searchTerms,
}) {
  final normalizedQuery = normalizePlayerSearchText(query);
  if (normalizedQuery.isEmpty) return SearchScorer.noMatch;

  var bestScore = 0.0;
  var bestMatch = '';

  for (final term in searchTerms) {
    if (!_looksLikeSearchPlayerName(term)) continue;

    final playerScore = playerNameSearchMatchScore(term, normalizedQuery);
    if (playerScore <= 0) continue;

    // Keep player-term event hits strong enough to surface related events,
    // but still below exact event-title matches.
    final score = 30.0 + playerScore * 0.6;
    if (score > bestScore) {
      bestScore = score;
      bestMatch = term;
    }
  }

  if (bestScore <= 0) return SearchScorer.noMatch;
  return SearchScoreMatch(
    score: bestScore.clamp(0.0, 90.0),
    matchedText: bestMatch,
  );
}

bool _looksLikeSearchPlayerName(String searchTerm) {
  final lowerTokens =
      searchTerm
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9]+'))
          .where((token) => token.isNotEmpty)
          .toSet();

  if (lowerTokens.any(_eventSearchStopWords.contains)) {
    return false;
  }

  final words = searchTerm.trim().split(RegExp(r'\s+'));
  if (words.length >= 2 && words.length <= 4) {
    return words.every(
      (word) =>
          word.isNotEmpty &&
          word[0] == word[0].toUpperCase() &&
          word.length > 1,
    );
  }

  return false;
}

SearchScoreMatch _bestNamedEventTitleTokenMatch({
  required String query,
  required String name,
  required Iterable<String> aliases,
}) {
  final queryTokens =
      _normalizedEventSearchTokens(
        query,
      ).where((token) => !_eventSearchStopWords.contains(token)).toList();
  if (queryTokens.length < 2) return SearchScorer.noMatch;

  final distinctiveTokens =
      queryTokens.where((token) => token.length >= 6).toList()
        ..sort((a, b) => b.length.compareTo(a.length));
  if (distinctiveTokens.isEmpty) return SearchScorer.noMatch;

  var bestScore = 0.0;
  var bestMatch = '';

  for (final title in [name, ...aliases]) {
    if (_looksLikeSearchPlayerName(title)) continue;

    final titleTokens = _normalizedEventSearchTokens(title);
    if (titleTokens.isEmpty) continue;

    for (final queryToken in distinctiveTokens) {
      if (!_tokenMatchesAnyTitleToken(queryToken, titleTokens)) continue;

      final tokenBoost = queryToken.length.clamp(0, 12).toDouble() * 2.0;
      final score = 70.0 + tokenBoost;
      if (score > bestScore) {
        bestScore = score;
        bestMatch = title;
      }
      break;
    }
  }

  if (bestScore <= 0) return SearchScorer.noMatch;
  return SearchScoreMatch(
    score: bestScore.clamp(0.0, 90.0),
    matchedText: bestMatch,
  );
}

bool _tokenMatchesAnyTitleToken(String queryToken, List<String> titleTokens) {
  return titleTokens.any(
    (titleToken) =>
        titleToken == queryToken ||
        titleToken.startsWith(queryToken) ||
        queryToken.startsWith(titleToken) && titleToken.length >= 6,
  );
}

List<String> _normalizedEventSearchTokens(String value) {
  final normalized =
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  if (normalized.isEmpty) return const [];
  return normalized.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
}

const _eventSearchStopWords = {
  'arena',
  'blitz',
  'challenge',
  'championship',
  'chess',
  'classic',
  'cup',
  'festival',
  'final',
  'finals',
  'grand',
  'invitational',
  'league',
  'master',
  'masters',
  'match',
  'memorial',
  'open',
  'olympiad',
  'qualifier',
  'rapid',
  'super',
  'team',
  'tournament',
};
