import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/match_header_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

// RoundStatus is already imported via games_app_bar_view_model.dart

class GamesListView extends ConsumerWidget {
  const GamesListView({
    super.key,
    required this.rounds,
    required this.gamesByRound,
    required this.gamesData,
    required this.gamesListViewMode,
    required this.itemScrollController,
    required this.itemPositionsListener,
    this.onReturnFromChessboard,
  });

  final List<GamesAppBarModel> rounds;
  final Map<String, List<GamesTourModel>> gamesByRound;
  final GamesScreenModel gamesData;
  final GamesListViewMode gamesListViewMode;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final void Function(int)? onReturnFromChessboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get expansion state for knockout tournaments
    final expansionState = ref.watch(matchExpansionProvider);

    // Check if this is a knockout tournament by analyzing ALL games
    final allGames = gamesData.gamesTourModels;
    final isKnockoutTournament = KnockoutMatchDetector.isKnockoutMatchFormat(allGames);

    // For knockout tournaments, group all sub-rounds into logical rounds
    final processedData = isKnockoutTournament
        ? _groupKnockoutRounds(rounds, gamesByRound, allGames)
        : _KnockoutProcessedData(rounds: rounds, gamesByRound: gamesByRound);

    final itemCount = _computeItemCount(
      gamesListViewMode,
      processedData.rounds,
      processedData.gamesByRound,
      expansionState,
      isKnockoutTournament,
    );

    if (itemCount == 0) {
      return const SizedBox.shrink();
    }

    return ScrollablePositionedList.builder(
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final lookup = _lookupItem(
          index: index,
          rounds: processedData.rounds,
          gamesByRound: processedData.gamesByRound,
          mode: gamesListViewMode,
          expansionState: expansionState,
          isKnockoutTournament: isKnockoutTournament,
        );

        if (lookup == null) {
          return const SizedBox.shrink();
        }

        if (lookup is _HeaderData) {
          return Padding(
            padding: EdgeInsets.only(bottom: 16.sp),
            child: RoundHeader(
              round: lookup.round,
              roundGames: lookup.roundGames,
            ),
          );
        }

        if (lookup is _MatchHeaderData) {
          final matchKey = lookup.matchHeader.matchKey;
          final isExpanded = ref.watch(matchExpansionStateProvider(matchKey));

          return Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: MatchHeader(
              match: lookup.matchHeader,
              isExpanded: isExpanded,
              onToggle: () {
                ref.read(matchExpansionProvider.notifier).toggleMatch(matchKey);
              },
            ),
          );
        }

        if (lookup is _GameRowData) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: lookup.isLastInSection ? 20.sp : 12.sp,
            ),
            child:
                gamesListViewMode == GamesListViewMode.chessBoardGrid
                    ? _buildGridRow(context, ref, lookup)
                    : _buildCardRow(context, ref, lookup),
          );
        }

        return const SizedBox.shrink();
      },
      padding: EdgeInsets.only(
        left: 16.sp,
        right: 16.sp,
        top: 16.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom + 8.sp,
      ),
    );
  }

  Widget _buildGridRow(BuildContext context, WidgetRef ref, _GameRowData item) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildGridGame(context, ref, item.game1, item.globalIndex1),
        if (item.game2 != null)
          _buildGridGame(context, ref, item.game2!, item.globalIndex2!),
      ],
    );
  }

  Widget _buildGridGame(
    BuildContext context,
    WidgetRef ref,
    GamesTourModel game,
    int globalIndex,
  ) {
    return GridChessBoardFromFENNew(
      key: ValueKey('game_${game.gameId}'),
      gamesTourModel: game,
      onChanged:
          () => ref
              .read(gameCardWrapperProvider)
              .navigateToChessBoard(
                context: context,
                orderedGames: gamesData.gamesTourModels,
                gameIndex: globalIndex,
                onReturnFromChessboard: (returnedIndex) {
                  _scrollToGameIndex(
                    returnedIndex,
                    rounds,
                    gamesByRound,
                    gamesListViewMode,
                  );
                  onReturnFromChessboard?.call(returnedIndex);
                },
              ),
      pinnedIds: gamesData.pinnedGamedIs,
      onPinToggle:
          (_) async => await ref
              .read(gamesTourScreenProvider.notifier)
              .togglePinGame(game.gameId),
    );
  }

  Widget _buildCardRow(BuildContext context, WidgetRef ref, _GameRowData item) {
    return GameCardWrapperWidget(
      game: item.game1,
      gamesData: gamesData,
      gameIndex: item.globalIndex1,
      isChessBoardVisible: gamesListViewMode == GamesListViewMode.chessBoard,
      onReturnFromChessboard: (returnedIndex) {
        _scrollToGameIndex(
          returnedIndex,
          rounds,
          gamesByRound,
          gamesListViewMode,
        );
        onReturnFromChessboard?.call(returnedIndex);
      },
    );
  }

  void _scrollToGameIndex(
    int gameIndex,
    List<GamesAppBarModel> rounds,
    Map<String, List<GamesTourModel>> gamesByRound,
    GamesListViewMode mode,
  ) {
    final listIndex = _listIndexForGameIndex(
      gameIndex: gameIndex,
      rounds: rounds,
      gamesByRound: gamesByRound,
      mode: mode,
    );
    if (listIndex != null) {
      itemScrollController.scrollTo(
        index: listIndex,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }
}

int _computeItemCount(
  GamesListViewMode mode,
  List<GamesAppBarModel> rounds,
  Map<String, List<GamesTourModel>> gamesByRound,
  Map<String, bool> expansionState,
  bool isKnockoutTournament,
) {
  var count = 0;
  final isGrid = mode == GamesListViewMode.chessBoardGrid;

  for (final round in rounds) {
    final roundGames = gamesByRound[round.id] ?? const <GamesTourModel>[];
    if (roundGames.isEmpty) continue;

    if (isKnockoutTournament) {
      // For knockout format: round header + match headers + games
      count++; // round header

      final matches = KnockoutMatchDetector.groupByMatches(roundGames);
      for (final entry in matches.entries) {
        final matchKey = entry.key;
        final matchGames = entry.value;
        final isExpanded = expansionState[matchKey] ?? true;

        count++; // match header

        // Only count games if match is expanded
        if (isExpanded) {
          if (isGrid) {
            count += (matchGames.length / 2).ceil();
          } else {
            count += matchGames.length;
          }
        }
      }
    } else {
      // Regular format: round header + games
      count++; // header
      if (isGrid) {
        count += (roundGames.length / 2).ceil();
      } else {
        count += roundGames.length;
      }
    }
  }

  return count;
}

Object? _lookupItem({
  required int index,
  required List<GamesAppBarModel> rounds,
  required Map<String, List<GamesTourModel>> gamesByRound,
  required GamesListViewMode mode,
  required Map<String, bool> expansionState,
  required bool isKnockoutTournament,
}) {
  var currentIndex = 0;
  var globalGameIndex = 0;
  final isGrid = mode == GamesListViewMode.chessBoardGrid;

  for (final round in rounds) {
    final roundGames = gamesByRound[round.id] ?? const <GamesTourModel>[];
    if (roundGames.isEmpty) continue;

    final roundStartIndex = globalGameIndex;

    if (index == currentIndex) {
      return _HeaderData(round, roundGames);
    }

    currentIndex++; // move past round header

    if (isKnockoutTournament) {
      // Handle knockout match format with match headers
      final matches = KnockoutMatchDetector.groupByMatches(roundGames);
      final matchHeaders = matches.entries.map((entry) {
        return KnockoutMatchDetector.createMatchHeader(entry.key, entry.value);
      }).toList();

      int matchGameOffset = 0;

      for (final matchHeader in matchHeaders) {
        final matchGames = matchHeader.games;
        final matchKey = matchHeader.matchKey;
        final isExpanded = expansionState[matchKey] ?? true;
        final matchGamesCount = matchGames.length;
        final matchStartIndex = roundStartIndex + matchGameOffset;

        // Check if this is the match header
        if (index == currentIndex) {
          return _MatchHeaderData(matchHeader);
        }

        currentIndex++; // move past match header

        // Only process games if match is expanded
        if (isExpanded) {
          if (isGrid) {
            final rowCount = (matchGamesCount / 2).ceil();
            if (index < currentIndex + rowCount) {
              final row = index - currentIndex;
              final game1Index = row * 2;
              final game2Index = game1Index + 1;

              return _GameRowData(
                game1: matchGames[game1Index],
                globalIndex1: matchStartIndex + game1Index,
                game2: game2Index < matchGamesCount ? matchGames[game2Index] : null,
                globalIndex2:
                    game2Index < matchGamesCount ? matchStartIndex + game2Index : null,
                isLastInSection: row == rowCount - 1,
              );
            }
            currentIndex += rowCount;
          } else {
            if (index < currentIndex + matchGamesCount) {
              final localIndex = index - currentIndex;
              return _GameRowData(
                game1: matchGames[localIndex],
                globalIndex1: matchStartIndex + localIndex,
                isLastInSection: localIndex == matchGamesCount - 1,
              );
            }
            currentIndex += matchGamesCount;
          }
        }

        matchGameOffset += matchGamesCount;
      }

      globalGameIndex = roundStartIndex + matchGameOffset;
    } else {
      // Regular format without match headers
      final gamesCount = roundGames.length;

      if (isGrid) {
        final rowCount = (gamesCount / 2).ceil();
        if (index < currentIndex + rowCount) {
          final row = index - currentIndex;
          final game1Index = row * 2;
          final game2Index = game1Index + 1;

          return _GameRowData(
            game1: roundGames[game1Index],
            globalIndex1: roundStartIndex + game1Index,
            game2: game2Index < gamesCount ? roundGames[game2Index] : null,
            globalIndex2:
                game2Index < gamesCount ? roundStartIndex + game2Index : null,
            isLastInSection: row == rowCount - 1,
          );
        }
        currentIndex += rowCount;
      } else {
        if (index < currentIndex + gamesCount) {
          final localIndex = index - currentIndex;
          return _GameRowData(
            game1: roundGames[localIndex],
            globalIndex1: roundStartIndex + localIndex,
            isLastInSection: localIndex == gamesCount - 1,
          );
        }
        currentIndex += gamesCount;
      }

      globalGameIndex = roundStartIndex + gamesCount;
    }
  }

  return null;
}

int? _listIndexForGameIndex({
  required int gameIndex,
  required List<GamesAppBarModel> rounds,
  required Map<String, List<GamesTourModel>> gamesByRound,
  required GamesListViewMode mode,
}) {
  if (gameIndex < 0) return null;

  var currentIndex = 0;
  var globalGameIndex = 0;
  final isGrid = mode == GamesListViewMode.chessBoardGrid;

  for (final round in rounds) {
    final roundGames = gamesByRound[round.id] ?? const <GamesTourModel>[];
    if (roundGames.isEmpty) continue;

    final roundStartIndex = globalGameIndex;
    final isKnockoutFormat = KnockoutMatchDetector.isKnockoutMatchFormat(roundGames);

    // skip round header
    currentIndex++;

    if (isKnockoutFormat) {
      // Handle knockout match format
      final matches = KnockoutMatchDetector.groupByMatches(roundGames);
      int matchGameOffset = 0;

      for (final matchGames in matches.values) {
        final matchStartIndex = roundStartIndex + matchGameOffset;
        final matchGamesCount = matchGames.length;

        // skip match header
        currentIndex++;

        if (gameIndex >= matchStartIndex &&
            gameIndex < matchStartIndex + matchGamesCount) {
          final localIndex = gameIndex - matchStartIndex;
          if (isGrid) {
            final row = localIndex ~/ 2;
            return currentIndex + row;
          } else {
            return currentIndex + localIndex;
          }
        }

        if (isGrid) {
          currentIndex += (matchGamesCount / 2).ceil();
        } else {
          currentIndex += matchGamesCount;
        }

        matchGameOffset += matchGamesCount;
      }

      globalGameIndex = roundStartIndex + matchGameOffset;
    } else {
      // Regular format
      final gamesCount = roundGames.length;

      if (gameIndex >= roundStartIndex &&
          gameIndex < roundStartIndex + gamesCount) {
        final localIndex = gameIndex - roundStartIndex;
        if (isGrid) {
          final row = localIndex ~/ 2;
          return currentIndex + row;
        } else {
          return currentIndex + localIndex;
        }
      }

      if (isGrid) {
        currentIndex += (gamesCount / 2).ceil();
      } else {
        currentIndex += gamesCount;
      }

      globalGameIndex = roundStartIndex + gamesCount;
    }
  }

  return null;
}

// ============================================================================
// KNOCKOUT ROUND GROUPING
// ============================================================================

/// Groups sub-rounds (game-1, game-2, tiebreak-*) into logical rounds for knockout tournaments
_KnockoutProcessedData _groupKnockoutRounds(
  List<GamesAppBarModel> rounds,
  Map<String, List<GamesTourModel>> gamesByRound,
  List<GamesTourModel> allGames,
) {
  if (rounds.isEmpty) {
    return _KnockoutProcessedData(rounds: rounds, gamesByRound: gamesByRound);
  }

  // Group games by player matchups to determine which sub-rounds belong together
  final matchupToGames = <String, List<GamesTourModel>>{};
  for (final game in allGames) {
    final key = _getMatchupKey(game.whitePlayer.name, game.blackPlayer.name);
    matchupToGames.putIfAbsent(key, () => []).add(game);
  }

  // All games with same matchups are part of the same logical round
  // Since this is a knockout tournament, all current games are in Round 1
  final allGamesInRound = allGames.toList();

  // Determine the round status based on existing rounds
  RoundStatus roundStatus = RoundStatus.ongoing;
  DateTime? startsAt;

  if (rounds.isNotEmpty) {
    // Use the earliest start time and most relevant status
    startsAt = rounds.map((r) => r.startsAt).whereType<DateTime>().reduce((a, b) => a.isBefore(b) ? a : b);

    // If any round is live, the logical round is live
    if (rounds.any((r) => r.roundStatus == RoundStatus.live)) {
      roundStatus = RoundStatus.live;
    } else if (rounds.any((r) => r.roundStatus == RoundStatus.ongoing)) {
      roundStatus = RoundStatus.ongoing;
    } else if (rounds.every((r) => r.roundStatus == RoundStatus.completed)) {
      roundStatus = RoundStatus.completed;
    } else if (rounds.every((r) => r.roundStatus == RoundStatus.upcoming)) {
      roundStatus = RoundStatus.upcoming;
    }
  }

  // Create a single logical round that contains all games
  final logicalRound = GamesAppBarModel(
    id: 'knockout-round-1',
    name: 'Round 1',
    startsAt: startsAt,
    roundStatus: roundStatus,
  );

  return _KnockoutProcessedData(
    rounds: [logicalRound],
    gamesByRound: {logicalRound.id: allGamesInRound},
  );
}

String _getMatchupKey(String player1, String player2) {
  final sorted = [player1.trim(), player2.trim()]..sort();
  return '${sorted[0]}|${sorted[1]}';
}

// ============================================================================
// DATA CLASSES
// ============================================================================

class _KnockoutProcessedData {
  final List<GamesAppBarModel> rounds;
  final Map<String, List<GamesTourModel>> gamesByRound;

  _KnockoutProcessedData({
    required this.rounds,
    required this.gamesByRound,
  });
}

class _HeaderData {
  _HeaderData(this.round, this.roundGames);

  final GamesAppBarModel round;
  final List<GamesTourModel> roundGames;
}

class _MatchHeaderData {
  _MatchHeaderData(this.matchHeader);

  final MatchHeaderModel matchHeader;
}

class _GameRowData {
  _GameRowData({
    required this.game1,
    required this.globalIndex1,
    this.game2,
    this.globalIndex2,
    required this.isLastInSection,
  });

  final GamesTourModel game1;
  final int globalIndex1;
  final GamesTourModel? game2;
  final int? globalIndex2;
  final bool isLastInSection;
}
