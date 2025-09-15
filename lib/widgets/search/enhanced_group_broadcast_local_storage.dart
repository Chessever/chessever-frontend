import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:chessever2/widgets/search/search_scorer.dart';

import '../../screens/group_event/group_event_screen.dart';

class EnhancedSearchResult {
  final List<SearchResult> tournamentResults;
  final List<SearchResult> playerResults;
  final List<SearchPlayer> allPlayers;

  const EnhancedSearchResult({
    required this.tournamentResults,
    required this.playerResults,
    this.allPlayers = const [],
  });
  factory EnhancedSearchResult.empty() => const EnhancedSearchResult(
    tournamentResults: [],
    playerResults: [],
    allPlayers: [],
  );

  int get totalResults => tournamentResults.length + playerResults.length;

  bool get isEmpty => tournamentResults.isEmpty && playerResults.isEmpty;

  bool get isNotEmpty => !isEmpty;

  bool get hasTournaments => tournamentResults.isNotEmpty;

  bool get hasPlayers => playerResults.isNotEmpty;
}

extension GroupBroadcastLocalStorageSearch on GroupBroadcastLocalStorage {
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

        final tournamentScore = SearchScorer.calculateScore(
          queryLower,
          gb.name,
          SearchResultType.tournament,
        );

        if (tournamentScore > 10.0) {
          tournamentResults.add(
            SearchResult(
              tournament: tourEventModel,
              score: tournamentScore,
              matchedText: gb.name,
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
      );
    } catch (e) {
      return const EnhancedSearchResult(
        tournamentResults: [],
        playerResults: [],
        allPlayers: [],
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
