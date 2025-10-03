import 'dart:async';

import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/widgets.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';

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

  ItemPositionsListener get itemPositionsListener =>
      _itemPositionsListener; // Expose for Riverpod

  String? _lastVisibleGameId;

  void _onItemPositionsChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      final positions = _itemPositionsListener.itemPositions.value;
      if (positions.isEmpty) return;

      final topItem =
          positions.where((pos) => pos.itemLeadingEdge < 0.5).firstOrNull;
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
    final allRounds =
        _ref.read(gamesAppBarProvider).valueOrNull?.gamesAppBarModels ?? [];
    final rounds = allRounds.where((r) => _getGamesInRound(r.id) > 0).toList();
    final reversedRounds = rounds.reversed.toList();

    int currentIndex = 0;
    for (final round in reversedRounds) {
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
      state.jumpTo(index: targetIndex, alignment: 0.0);
    });
  }

  int? _getItemIndexForGameId(String gameId) {
    final allRounds =
        _ref.read(gamesAppBarProvider).valueOrNull?.gamesAppBarModels ?? [];
    final rounds = allRounds.where((r) => _getGamesInRound(r.id) > 0).toList();
    final reversedRounds = rounds.reversed.toList();

    int currentIndex = 0;
    for (final round in reversedRounds) {
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
    final currentSelected = gamesAppBarAsync.valueOrNull?.selectedId;
    if (currentSelected != roundId) {
      final gamesAppBarData = gamesAppBarAsync.valueOrNull;
      if (gamesAppBarData != null) {
        final targetRound =
            gamesAppBarData.gamesAppBarModels
                .where((round) => round.id == roundId)
                .firstOrNull;
        if (targetRound != null) {
          _ref.read(gamesAppBarProvider.notifier).selectSilently(targetRound);
        }
      }
    }
  }

  String? _getRoundIdFromItemIndex(int itemIndex) {
    final allRounds =
        _ref.read(gamesAppBarProvider).valueOrNull?.gamesAppBarModels ?? [];
    final rounds =
        allRounds.where((round) => _getGamesInRound(round.id) > 0).toList();
    final reversedRounds = rounds.reversed.toList();

    int currentIndex = 0;
    for (final round in reversedRounds) {
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
    final gamesCount = _getGamesInRound(roundId);
    if (_ref.read(gamesListViewModeProvider) ==
        GamesListViewMode.chessBoardGrid) {
      return (gamesCount / 2).ceil(); // 2 per row
    }
    return gamesCount;
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
