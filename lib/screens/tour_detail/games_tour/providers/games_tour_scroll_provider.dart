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

  void _onItemPositionsChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      final positions = _itemPositionsListener.itemPositions.value;
      if (positions.isEmpty) return;

      final topItem =
          positions.where((pos) => pos.itemLeadingEdge < 0.5).firstOrNull;
      if (topItem == null) return;

      final visibleRoundId = _getRoundIdFromItemIndex(topItem.index);
      if (visibleRoundId != null && visibleRoundId != _lastVisibleRoundId) {
        _lastVisibleRoundId = visibleRoundId;
        _notifyRoundChange(visibleRoundId);
      }
    });
  }

  // Ensure the item anchored at the top remains the same after layout changes
  void _anchorTopAfterVisibilityChange() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    // Prefer the first item whose leadingEdge is >= 0 (visible and closest to top)
    ItemPosition? top = positions
        .where((p) => p.itemLeadingEdge >= 0)
        .fold<ItemPosition?>(null, (best, p) {
          if (best == null) return p;
          return p.itemLeadingEdge < best.itemLeadingEdge ? p : best;
        });

    // If none are >= 0, pick the one just above the top (largest negative leadingEdge)
    top ??= positions.where((p) => p.itemLeadingEdge < 0).fold<ItemPosition?>(
      null,
      (best, p) {
        if (best == null) return p;
        return p.itemLeadingEdge > best.itemLeadingEdge ? p : best;
      },
    );

    if (top == null) return;

    final targetIndex = top.index;

    // After the frame (when visibility change has re-laid out), jump to keep the same top index.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!state.isAttached) return;
      state.jumpTo(index: targetIndex, alignment: 0.0);
    });
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
