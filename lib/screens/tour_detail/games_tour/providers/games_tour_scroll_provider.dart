import 'dart:async';

import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

final gamesTourScrollProvider =
    StateNotifierProvider<_GamesTourScrollProvider, ItemScrollController>(
      (ref) => _GamesTourScrollProvider(ref),
    );

class _GamesTourScrollProvider extends StateNotifier<ItemScrollController> {
  _GamesTourScrollProvider(this._ref) : super(ItemScrollController()) {
    _itemPositionsListener = ItemPositionsListener.create();
    _itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);
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
    final rounds =
        _ref.read(gamesAppBarProvider).valueOrNull?.gamesAppBarModels ?? [];
    final reversedRounds = rounds.reversed.toList();
    int currentIndex = 0;
    for (final round in reversedRounds) {
      if (itemIndex == currentIndex) return round.id;
      final gamesInRound = _getGamesInRound(round.id);
      currentIndex += 1 + gamesInRound;
      if (itemIndex < currentIndex) return round.id;
    }
    return null;
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
