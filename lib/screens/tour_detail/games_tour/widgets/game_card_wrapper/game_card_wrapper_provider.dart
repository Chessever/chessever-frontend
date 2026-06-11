import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gameCardWrapperProvider = AutoDisposeProvider<_GameCardWrapperProvider>((
  ref,
) {
  return _GameCardWrapperProvider(ref);
});

class _ResolvedNavigation {
  final List<GamesTourModel> games;
  final int index;

  const _ResolvedNavigation({required this.games, required this.index});
}

class _GameCardWrapperProvider {
  _GameCardWrapperProvider(this._ref);

  final Ref _ref;

  Future<_ResolvedNavigation> _resolveNavigationGames({
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    required ChessboardView viewSource,
  }) async {
    if (viewSource != ChessboardView.forYou) {
      return _ResolvedNavigation(games: orderedGames, index: gameIndex);
    }

    if (orderedGames.isEmpty) {
      return _ResolvedNavigation(games: orderedGames, index: gameIndex);
    }

    final safeIndex = gameIndex.clamp(0, orderedGames.length - 1);
    await _hydrateTournamentContextForForYou(orderedGames[safeIndex]);
    return _ResolvedNavigation(games: orderedGames, index: safeIndex);
  }

  Future<void> _hydrateTournamentContextForForYou(GamesTourModel game) async {
    final tourId = game.tourId;
    if (tourId.isEmpty) return;

    try {
      final tours = await _ref
          .read(tourRepositoryProvider)
          .getTourByGroupId(tourId);
      final groupBroadcastId = tours
          .map((tour) => tour.groupBroadcastId)
          .whereType<String>()
          .firstWhere((id) => id.isNotEmpty, orElse: () => '');
      if (groupBroadcastId.isEmpty) return;

      final currentBroadcast = _ref.read(selectedBroadcastModelProvider);
      if (currentBroadcast?.id != groupBroadcastId) {
        final broadcast = await _ref
            .read(groupBroadcastRepositoryProvider)
            .getGroupBroadcastById(groupBroadcastId);
        _ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;
      }

      _ref.read(selectedTourModeProvider.notifier).state =
          TournamentDetailScreenMode.games;
      _ref.invalidate(tourDetailScreenProvider);
      _ref.invalidate(gamesAppBarProvider);
      _ref.invalidate(gamesTourScreenProvider);
    } catch (error) {
      debugPrint(
        '[GameCardWrapper] Failed to hydrate For You tournament context: $error',
      );
    }
  }

  void navigateToChessBoard({
    required BuildContext context,
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    required void Function(int)? onReturnFromChessboard,
    ChessboardView viewSource = ChessboardView.tour,
  }) async {
    _ref.read(chessboardViewFromProviderNew.notifier).state = viewSource;

    // Disable tournament streaming while inside the chessboard to avoid
    // periodic refreshes and repeated fetch logs.
    _ref.read(shouldStreamProvider.notifier).state = false;

    final resolvedNavigation = await _resolveNavigationGames(
      orderedGames: orderedGames,
      gameIndex: gameIndex,
      viewSource: viewSource,
    );

    if (!context.mounted) {
      _ref.read(shouldStreamProvider.notifier).state = true;
      return;
    }

    final returnedIndex = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreenNew(
              games: resolvedNavigation.games,
              currentIndex: resolvedNavigation.index,
            ),
      ),
    );

    // Re-enable streaming when coming back to the tournament screen
    _ref.read(shouldStreamProvider.notifier).state = true;
    _ref.invalidate(gameUpdatesStreamProvider);
    _ref.invalidate(liveGameUpdateStreamProvider);
    _ref.invalidate(gameUpdatesBatchStreamProvider);

    // If a different index was returned from the chessboard, notify the parent
    if (returnedIndex != null &&
        returnedIndex != gameIndex &&
        onReturnFromChessboard != null) {
      onReturnFromChessboard(returnedIndex);
    }
  }
}
