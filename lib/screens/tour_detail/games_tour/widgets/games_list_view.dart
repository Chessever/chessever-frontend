import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/match_header_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/positioned_list_scrollbar.dart';
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
    required this.isKnockoutTournament,
    required this.gamesListViewMode,
    required this.itemScrollController,
    required this.itemPositionsListener,
    this.isSearchMode = false,
    this.displayMode = GameDisplayMode.all,
    this.onReturnFromChessboard,
  });

  final List<GamesAppBarModel> rounds;
  final Map<String, List<GamesTourModel>> gamesByRound;
  final GamesScreenModel gamesData;
  final bool isKnockoutTournament;
  final GamesListViewMode gamesListViewMode;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final bool isSearchMode;
  final GameDisplayMode displayMode;
  final void Function(int)? onReturnFromChessboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Expansion states for rounds and matches
    // In search mode, override expansion to show everything
    final matchExpansionState = isSearchMode
        ? <String, bool>{} // Empty map means all expanded by default
        : ref.watch(matchExpansionProvider);
    final roundExpansionState = isSearchMode
        ? <String, bool>{} // Empty map means all expanded by default
        : ref.watch(roundExpansionProvider);

    // Pre-calculate match groupings once for knockout tournaments to avoid repeated calculations
    final matchGroupsByRound = isKnockoutTournament
        ? _preCalculateMatchGroups(rounds, gamesByRound)
        : <String, Map<String, List<GamesTourModel>>>{};

    // For multi-stage knockouts, build ordered games list from gamesByRound
    final orderedGamesList = _buildOrderedGamesList(
      rounds,
      gamesByRound,
      isKnockoutTournament,
      matchGroupsByRound,
    );

    final itemCount = _computeItemCount(
      gamesListViewMode,
      rounds,
      gamesByRound,
      matchExpansionState,
      roundExpansionState,
      isKnockoutTournament,
      displayMode,
      matchGroupsByRound,
      isSearchMode: isSearchMode,
    );

    if (itemCount == 0) {
      return const SizedBox.shrink();
    }

    return PositionedListScrollbar(
      itemPositionsListener: itemPositionsListener,
      itemScrollController: itemScrollController,
      itemCount: itemCount,
      thumbWidth: 4.sp,
      padding: EdgeInsets.only(
        top: 16.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom + 8.sp,
      ),
      child: ScrollablePositionedList.builder(
        itemScrollController: itemScrollController,
        itemPositionsListener: itemPositionsListener,
        itemCount: itemCount,
        itemBuilder: (context, index) {
          final lookup = _lookupItem(
            index: index,
            rounds: rounds,
            gamesByRound: gamesByRound,
            mode: gamesListViewMode,
            matchExpansionState: matchExpansionState,
            roundExpansionState: roundExpansionState,
            isKnockoutTournament: isKnockoutTournament,
            displayMode: displayMode,
            matchGroupsByRound: matchGroupsByRound,
            isSearchMode: isSearchMode,
          );

          if (lookup == null) {
            return const SizedBox.shrink();
          }

          if (lookup is _HeaderData) {
            final isRoundExpanded = isSearchMode
                ? true
                : ref.watch(roundExpansionStateProvider(lookup.round.id));
            return Padding(
              padding: EdgeInsets.only(bottom: 16.sp),
              child: RoundHeader(
                round: lookup.round,
                roundGames: lookup.roundGames,
                isExpanded: isRoundExpanded,
                onToggle: isSearchMode
                    ? null // Disable toggle in search mode
                    : () {
                        ref
                            .read(roundExpansionProvider.notifier)
                            .toggleRound(lookup.round.id);
                      },
              ),
            );
          }

          if (lookup is _MatchHeaderData) {
            final matchKey = lookup.matchHeader.matchKey;
            final isExpanded = isSearchMode
                ? true
                : ref.watch(matchExpansionStateProvider(matchKey));

            return Padding(
              padding: EdgeInsets.only(bottom: 12.sp),
              child: MatchHeader(
                match: lookup.matchHeader,
                isExpanded: isExpanded,
                onToggle: isSearchMode
                    ? null // Disable toggle in search mode
                    : () {
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
                      ? _buildGridRow(context, ref, lookup, orderedGamesList, matchGroupsByRound)
                      : _buildCardRow(context, ref, lookup, orderedGamesList, matchGroupsByRound),
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
      ),
    );
  }

  Widget _buildGridRow(
    BuildContext context,
    WidgetRef ref,
    _GameRowData item,
    List<GamesTourModel> orderedGamesList,
    Map<String, Map<String, List<GamesTourModel>>> matchGroupsByRound,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildGridGame(
          context,
          ref,
          item.game1,
          item.globalIndex1,
          orderedGamesList,
          matchGroupsByRound,
        ),
        if (item.game2 != null)
          _buildGridGame(
            context,
            ref,
            item.game2!,
            item.globalIndex2!,
            orderedGamesList,
            matchGroupsByRound,
          ),
      ],
    );
  }

  Widget _buildGridGame(
    BuildContext context,
    WidgetRef ref,
    GamesTourModel game,
    int globalIndex,
    List<GamesTourModel> orderedGamesList,
    Map<String, Map<String, List<GamesTourModel>>> matchGroupsByRound,
  ) {
    return GridChessBoardFromFENNew(
      key: ValueKey('game_${game.gameId}'),
      gamesTourModel: game,
      onChanged:
          () => ref
              .read(gameCardWrapperProvider)
              .navigateToChessBoard(
                context: context,
                orderedGames: orderedGamesList,
                gameIndex: globalIndex,
                onReturnFromChessboard: (returnedIndex) {
                  final latestMatchExpansion = ref.read(matchExpansionProvider);
                  final latestRoundExpansion = ref.read(roundExpansionProvider);
                  _scrollToGameIndex(
                    returnedIndex,
                    rounds,
                    gamesByRound,
                    gamesListViewMode,
                    matchGroupsByRound,
                    matchExpansionState: latestMatchExpansion,
                    roundExpansionState: latestRoundExpansion,
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

  Widget _buildCardRow(
    BuildContext context,
    WidgetRef ref,
    _GameRowData item,
    List<GamesTourModel> orderedGamesList,
    Map<String, Map<String, List<GamesTourModel>>> matchGroupsByRound,
  ) {
    // Create modified gamesData with correct orderedGames for multi-stage knockouts
    final modifiedGamesData = GamesScreenModel(
      gamesTourModels: orderedGamesList,
      pinnedGamedIs: gamesData.pinnedGamedIs,
    );

    return GameCardWrapperWidget(
      game: item.game1,
      gamesData: modifiedGamesData,
      gameIndex: item.globalIndex1,
      isChessBoardVisible: gamesListViewMode == GamesListViewMode.chessBoard,
      onReturnFromChessboard: (returnedIndex) {
        final latestMatchExpansion = ref.read(matchExpansionProvider);
        final latestRoundExpansion = ref.read(roundExpansionProvider);
        _scrollToGameIndex(
          returnedIndex,
          rounds,
          gamesByRound,
          gamesListViewMode,
          matchGroupsByRound,
          matchExpansionState: latestMatchExpansion,
          roundExpansionState: latestRoundExpansion,
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
    Map<String, Map<String, List<GamesTourModel>>> matchGroupsByRound, {
    required Map<String, bool> matchExpansionState,
    required Map<String, bool> roundExpansionState,
  }) {
    final listIndex = _listIndexForGameIndex(
      gameIndex: gameIndex,
      rounds: rounds,
      gamesByRound: gamesByRound,
      mode: mode,
      isKnockoutTournament: isKnockoutTournament,
      matchExpansionState: matchExpansionState,
      roundExpansionState: roundExpansionState,
      displayMode: displayMode,
      matchGroupsByRound: matchGroupsByRound,
      isSearchMode: isSearchMode,
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
  Map<String, bool> matchExpansionState,
  Map<String, bool> roundExpansionState,
  bool isKnockoutTournament,
  GameDisplayMode displayMode,
  Map<String, Map<String, List<GamesTourModel>>> matchGroupsByRound, {
  bool isSearchMode = false,
}) {
  var count = 0;
  final isGrid = mode == GamesListViewMode.chessBoardGrid;

  for (final round in rounds) {
    final roundGames = gamesByRound[round.id] ?? const <GamesTourModel>[];
    if (roundGames.isEmpty) continue;
    // In search mode, default to expanded (true)
    final isRoundExpanded = isSearchMode ? true : (roundExpansionState[round.id] ?? true);

    count++; // round header always counted

    if (!isRoundExpanded) {
      continue;
    }

    if (_isKnockoutRound(isKnockoutTournament, round)) {
      // For knockout format: round header + match headers + games using pre-calculated groups
      final matches = matchGroupsByRound[round.id] ?? {};
      for (final entry in matches.entries) {
        final matchKey = entry.key;
        final matchGames = entry.value;
        // In search mode, default to expanded (true)
        final isExpanded = isSearchMode ? true : (matchExpansionState[matchKey] ?? true);

        count++; // match header

        // Only count games if match is expanded
        if (isExpanded) {
          // Filter games based on displayMode for knockout tournaments
          final filteredGames = matchGames.where((game) {
            return _shouldShowGame(displayMode, game);
          }).toList();

          if (isGrid) {
            count += (filteredGames.length / 2).ceil();
          } else {
            count += filteredGames.length;
          }
        }
      }
    } else {
      // Regular format: round header + games
      if (isGrid) {
        count += (roundGames.length / 2).ceil();
      } else {
        count += roundGames.length;
      }
    }
  }

  return count;
}

bool _shouldShowGame(GameDisplayMode mode, GamesTourModel game) {
  switch (mode) {
    case GameDisplayMode.hideFinishedGames:
      return !game.gameStatus.isFinished;
    case GameDisplayMode.showfinishedGame:
      return game.gameStatus.isFinished;
    case GameDisplayMode.all:
      return true;
  }
}

Object? _lookupItem({
  required int index,
  required List<GamesAppBarModel> rounds,
  required Map<String, List<GamesTourModel>> gamesByRound,
  required GamesListViewMode mode,
  required Map<String, bool> matchExpansionState,
  required Map<String, bool> roundExpansionState,
  required bool isKnockoutTournament,
  required GameDisplayMode displayMode,
  required Map<String, Map<String, List<GamesTourModel>>> matchGroupsByRound,
  bool isSearchMode = false,
}) {
  var currentIndex = 0;
  var globalGameIndex = 0;
  final isGrid = mode == GamesListViewMode.chessBoardGrid;

  for (final round in rounds) {
    final roundGames = gamesByRound[round.id] ?? const <GamesTourModel>[];
    if (roundGames.isEmpty) continue;

    final roundStartIndex = globalGameIndex;
    // In search mode, default to expanded (true)
    final isRoundExpanded = isSearchMode ? true : (roundExpansionState[round.id] ?? true);

    if (index == currentIndex) {
      return _HeaderData(round, roundGames);
    }

    currentIndex++; // move past round header

    if (!isRoundExpanded) {
      globalGameIndex = roundStartIndex + roundGames.length;
      continue;
    }

    if (_isKnockoutRound(isKnockoutTournament, round)) {
      // Handle knockout match format with match headers using pre-calculated groups
      final matches = matchGroupsByRound[round.id] ?? {};
      final matchHeaders =
          matches.entries
              .map(
                (entry) => KnockoutMatchDetector.createMatchHeader(
                  entry.key,
                  entry.value,
                ),
              )
              .toList();

      int matchGameOffset = 0;

      for (final matchHeader in matchHeaders) {
        final matchGames = matchHeader.games;
        final matchKey = matchHeader.matchKey;
        // In search mode, default to expanded (true)
        final isExpanded = isSearchMode ? true : (matchExpansionState[matchKey] ?? true);
        final matchGamesCount = matchGames.length;
        final matchStartIndex = roundStartIndex + matchGameOffset;

        // Check if this is the match header
        if (index == currentIndex) {
          return _MatchHeaderData(matchHeader);
        }

        currentIndex++; // move past match header

        // Only process games if match is expanded
        if (isExpanded) {
          // Filter games based on displayMode for knockout tournaments
          final filteredGames = matchGames.where((game) {
            return _shouldShowGame(displayMode, game);
          }).toList();

          // Build index mapping from filtered to original
          final filteredToOriginalIndex = <int, int>{};
          int filteredIdx = 0;
          for (int i = 0; i < matchGames.length; i++) {
            if (_shouldShowGame(displayMode, matchGames[i])) {
              filteredToOriginalIndex[filteredIdx] = i;
              filteredIdx++;
            }
          }

          final filteredCount = filteredGames.length;

          if (isGrid) {
            final rowCount = (filteredCount / 2).ceil();
            if (index < currentIndex + rowCount) {
              final row = index - currentIndex;
              final game1Index = row * 2;
              final game2Index = game1Index + 1;

              return _GameRowData(
                game1: filteredGames[game1Index],
                globalIndex1: matchStartIndex + filteredToOriginalIndex[game1Index]!,
                game2:
                    game2Index < filteredCount
                        ? filteredGames[game2Index]
                        : null,
                globalIndex2:
                    game2Index < filteredCount
                        ? matchStartIndex + filteredToOriginalIndex[game2Index]!
                        : null,
                isLastInSection: row == rowCount - 1,
              );
            }
            currentIndex += rowCount;
          } else {
            if (index < currentIndex + filteredCount) {
              final localIndex = index - currentIndex;
              return _GameRowData(
                game1: filteredGames[localIndex],
                globalIndex1: matchStartIndex + filteredToOriginalIndex[localIndex]!,
                isLastInSection: localIndex == filteredCount - 1,
              );
            }
            currentIndex += filteredCount;
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
  required bool isKnockoutTournament,
  required Map<String, bool> matchExpansionState,
  required Map<String, bool> roundExpansionState,
  required GameDisplayMode displayMode,
  required Map<String, Map<String, List<GamesTourModel>>> matchGroupsByRound,
  bool isSearchMode = false,
}) {
  if (gameIndex < 0) return null;

  var currentIndex = 0;
  var globalGameIndex = 0;
  final isGrid = mode == GamesListViewMode.chessBoardGrid;

  for (final round in rounds) {
    final roundGames = gamesByRound[round.id] ?? const <GamesTourModel>[];
    if (roundGames.isEmpty) continue;

    final roundStartIndex = globalGameIndex;
    final isKnockoutFormat = _isKnockoutRound(isKnockoutTournament, round);
    // In search mode, default to expanded (true)
    final isRoundExpanded = isSearchMode ? true : (roundExpansionState[round.id] ?? true);

    // skip round header
    currentIndex++;

    if (!isRoundExpanded) {
      globalGameIndex = roundStartIndex + roundGames.length;
      continue;
    }

    if (isKnockoutFormat) {
      // Handle knockout match format using pre-calculated groups
      final matches = matchGroupsByRound[round.id] ?? {};
      int matchGameOffset = 0;

      for (final entry in matches.entries) {
        final matchKey = entry.key;
        final matchGames = entry.value;
        // In search mode, default to expanded (true)
        final isExpanded = isSearchMode ? true : (matchExpansionState[matchKey] ?? true);
        final matchStartIndex = roundStartIndex + matchGameOffset;
        final matchGamesCount = matchGames.length;

        // skip match header
        currentIndex++;

        if (!isExpanded) {
          matchGameOffset += matchGamesCount;
          continue;
        }

        // Filter games based on displayMode for knockout tournaments
        final filteredGames = matchGames.where((game) {
          return _shouldShowGame(displayMode, game);
        }).toList();
        final filteredCount = filteredGames.length;

        if (gameIndex >= matchStartIndex &&
            gameIndex < matchStartIndex + matchGamesCount) {
          final localIndex = gameIndex - matchStartIndex;
          // Find position in filtered list
          int filteredPosition = 0;
          for (int i = 0; i < localIndex; i++) {
            if (_shouldShowGame(displayMode, matchGames[i])) {
              filteredPosition++;
            }
          }
          if (_shouldShowGame(displayMode, matchGames[localIndex])) {
            if (isGrid) {
              final row = filteredPosition ~/ 2;
              return currentIndex + row;
            } else {
              return currentIndex + filteredPosition;
            }
          }
        }

        if (isGrid) {
          currentIndex += (filteredCount / 2).ceil();
        } else {
          currentIndex += filteredCount;
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

bool _isKnockoutRound(bool isKnockoutTournament, GamesAppBarModel round) {
  if (!isKnockoutTournament) return false;
  final id = round.id.toLowerCase();
  return id.startsWith('$kKnockoutStagePrefix-') ||
      id.startsWith('knockout-round-');
}

/// Pre-calculate match groupings for all rounds to avoid repeated calculations
Map<String, Map<String, List<GamesTourModel>>> _preCalculateMatchGroups(
  List<GamesAppBarModel> rounds,
  Map<String, List<GamesTourModel>> gamesByRound,
) {
  final result = <String, Map<String, List<GamesTourModel>>>{};

  for (final round in rounds) {
    final roundGames = gamesByRound[round.id];
    if (roundGames == null || roundGames.isEmpty) continue;

    result[round.id] = KnockoutMatchDetector.groupByMatches(roundGames);
  }

  return result;
}

/// Build ordered list of ALL games from ALL visible rounds
/// This is critical for correct navigation in multi-stage knockouts
List<GamesTourModel> _buildOrderedGamesList(
  List<GamesAppBarModel> rounds,
  Map<String, List<GamesTourModel>> gamesByRound,
  bool isKnockoutTournament,
  Map<String, Map<String, List<GamesTourModel>>> matchGroupsByRound,
) {
  final orderedGames = <GamesTourModel>[];

  for (final round in rounds) {
    final roundGames = gamesByRound[round.id] ?? const <GamesTourModel>[];
    if (roundGames.isEmpty) continue;

    if (_isKnockoutRound(isKnockoutTournament, round)) {
      // For knockout format, add games in match order using pre-calculated groups
      final matches = matchGroupsByRound[round.id] ?? {};
      for (final matchGames in matches.values) {
        orderedGames.addAll(matchGames);
      }
    } else {
      // For regular format, add games as-is
      orderedGames.addAll(roundGames);
    }
  }

  return orderedGames;
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
