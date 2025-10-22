import 'dart:async';

import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/widgets.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';

final gamesTourScrollProvider =
    StateNotifierProvider<_GamesTourScrollProvider, ItemScrollController>(
      (ref) => _GamesTourScrollProvider(ref),
    );

class _GamesTourScrollProvider extends StateNotifier<ItemScrollController> {
  _GamesTourScrollProvider(this._ref) : super(ItemScrollController()) {
    _itemPositionsListener = ItemPositionsListener.create();
    _itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);

    // Keep the same top item when chessBoard visibility toggles
    _ref.listen<GamesListViewMode>(
      gamesListViewModeProvider,
      (previous, next) => _anchorTopAfterVisibilityChange(),
    );
  }

  final Ref _ref;
  late ItemPositionsListener _itemPositionsListener;
  Timer? _debounceTimer;
  String? _lastVisibleRoundId;
  bool _isProgrammaticScroll = false;

  ItemPositionsListener get itemPositionsListener =>
      _itemPositionsListener; // Expose for Riverpod

  String? _lastVisibleGameId;

  /// Compute rounds visible in the list view: hide upcoming by default,
  /// include the selected upcoming round only when user explicitly selected it.
  List<GamesAppBarModel> _getVisibleRounds() {
    final vm = _ref.read(gamesAppBarProvider).valueOrNull;
    if (vm == null) return <GamesAppBarModel>[];
    final selectedId = vm.selectedId;
    final userSelected = vm.userSelectedId;

    final models = vm.gamesAppBarModels;
    final visible = <GamesAppBarModel>[];
    for (final r in models) {
      final hasGames = _getGamesInRound(r.id) > 0;
      if (!hasGames) continue;
      if (userSelected && r.id == selectedId) {
        visible.add(r);
        continue;
      }
      if (r.roundStatus != RoundStatus.upcoming) {
        visible.add(r);
      }
    }
    return visible;
  }

  /// Set flag to prevent scroll listener from updating dropdown during programmatic scroll
  void startProgrammaticScroll() {
    _isProgrammaticScroll = true;
  }

  /// Reset flag after programmatic scroll completes to re-enable scroll sync
  void endProgrammaticScroll() {
    // Add a small delay to ensure the scroll has fully completed
    Future.delayed(const Duration(milliseconds: 200), () {
      _isProgrammaticScroll = false;
    });
  }

  void _onItemPositionsChanged() {
    // Skip updates during programmatic scroll
    if (_isProgrammaticScroll) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      final positions = _itemPositionsListener.itemPositions.value;
      if (positions.isEmpty) return;

      // Find the topmost visible item (considering items that are at least partially visible)
      final topItem =
          positions.where((pos) => pos.itemLeadingEdge < 0.3).firstOrNull;
      if (topItem == null) return;

      final gameId = _getGameIdFromItemIndex(topItem.index);
      if (gameId != null && gameId != _lastVisibleGameId) {
        _lastVisibleGameId = gameId;
      }

      final visibleRoundId = _getRoundIdFromItemIndex(topItem.index);
      if (visibleRoundId != null && visibleRoundId != _lastVisibleRoundId) {
        _lastVisibleRoundId = visibleRoundId;
        _notifyRoundChange(visibleRoundId);
      }
    });
  }

  String? _getGameIdFromItemIndex(int itemIndex) {
    final rounds = _getVisibleRounds();

    int currentIndex = 0;
    for (final round in rounds) {
      if (itemIndex == currentIndex) {
        return null; // header row, no game
      }
      currentIndex++; // skip header

      final games =
          _ref
              .read(gamesTourScreenProvider)
              .valueOrNull
              ?.gamesTourModels
              .where((g) => g.roundId == round.id)
              .toList() ??
          [];

      if (_ref.read(gamesListViewModeProvider) ==
          GamesListViewMode.chessBoardGrid) {
        final rowCount = (games.length / 2).ceil();
        if (itemIndex < currentIndex + rowCount) {
          final row = itemIndex - currentIndex;
          return games[row * 2].gameId; // first game in that row
        }
        currentIndex += rowCount;
      } else {
        if (itemIndex < currentIndex + games.length) {
          return games[itemIndex - currentIndex].gameId;
        }
        currentIndex += games.length;
      }
    }
    return null;
  }

  // Ensure the item anchored at the top remains the same after layout changes
  void _anchorTopAfterVisibilityChange() {
    if (_lastVisibleGameId == null) return;

    final targetIndex = _getItemIndexForGameId(_lastVisibleGameId!);
    if (targetIndex == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!state.isAttached) return;
      state.jumpTo(index: targetIndex, alignment: 0.1);
    });
  }

  int? _getItemIndexForGameId(String gameId) {
    final rounds = _getVisibleRounds();

    int currentIndex = 0;
    for (final round in rounds) {
      // header
      currentIndex++;

      final games =
          _ref
              .read(gamesTourScreenProvider)
              .valueOrNull
              ?.gamesTourModels
              .where((g) => g.roundId == round.id)
              .toList() ??
          [];

      if (_ref.read(gamesListViewModeProvider) ==
          GamesListViewMode.chessBoardGrid) {
        for (int i = 0; i < games.length; i += 2) {
          final rowIndex = currentIndex + (i ~/ 2);
          if (games[i].gameId == gameId ||
              (i + 1 < games.length && games[i + 1].gameId == gameId)) {
            return rowIndex;
          }
        }
        currentIndex += (games.length / 2).ceil();
      } else {
        for (int i = 0; i < games.length; i++) {
          if (games[i].gameId == gameId) {
            return currentIndex + i;
          }
        }
        currentIndex += games.length;
      }
    }
    return null;
  }

  void _notifyRoundChange(String roundId) {
    final gamesAppBarAsync = _ref.read(gamesAppBarProvider);
    final gamesAppBarData = gamesAppBarAsync.valueOrNull;
    if (gamesAppBarData == null) return;

    final currentSelected = gamesAppBarData.selectedId;
    final wasUserSelected = gamesAppBarData.userSelectedId;

    // Only update if round actually changed and it wasn't a user selection
    if (currentSelected != roundId && !wasUserSelected) {
      final targetRound =
          gamesAppBarData.gamesAppBarModels
              .where((round) => round.id == roundId)
              .firstOrNull;
      if (targetRound != null) {
        _ref.read(gamesAppBarProvider.notifier).selectSilently(targetRound);
      }
    }
  }

  String? _getRoundIdFromItemIndex(int itemIndex) {
    final rounds = _getVisibleRounds();

    int currentIndex = 0;
    for (final round in rounds) {
      if (itemIndex == currentIndex) return round.id; // header
      final itemCount =
          1 +
          _getGamesInRoundAsListItems(round.id); // header + games (grid aware)
      currentIndex += itemCount;
      if (itemIndex < currentIndex) return round.id;
    }
    return null;
  }

  int _getGamesInRoundAsListItems(String roundId) {
    // Check if we're in group event mode
    final screenMode = _ref.read(gamesTourScreenModeProvider).valueOrNull;
    final isGroupEvent = screenMode == GamesTourScreenMode.groupEvent;

    if (isGroupEvent) {
      // For group events, count team matchup cards
      return _getTeamMatchupCardsInRound(roundId);
    }

    // For regular events, count games (grid or list)
    final gamesCount = _getGamesInRound(roundId);
    if (_ref.read(gamesListViewModeProvider) ==
        GamesListViewMode.chessBoardGrid) {
      return (gamesCount / 2).ceil(); // 2 per row
    }
    return gamesCount;
  }

  int _getTeamMatchupCardsInRound(String roundId) {
    // Get games for this round
    final gamesData = _ref.read(gamesTourScreenProvider).valueOrNull;
    if (gamesData == null) return 0;

    final roundGames =
        gamesData.gamesTourModels.where((g) => g.roundId == roundId).toList();
    if (roundGames.isEmpty) return 0;

    // Use the same grouping logic as the UI
    final grouped = _ref.read(gamesTourContentProvider).getGroupHeader(
          selectedRoundId: roundId,
          gamesScreenModel: gamesData,
        );

    // Return the number of team matchup cards
    return grouped.keys.length;
  }

  int _getGamesInRound(String roundId) {
    return _ref
            .read(gamesTourScreenProvider)
            .valueOrNull
            ?.gamesTourModels
            .where((g) => g.roundId == roundId)
            .length ??
        0;
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(
      _onItemPositionsChanged,
    );
    _debounceTimer?.cancel();
    super.dispose();
  }
}
