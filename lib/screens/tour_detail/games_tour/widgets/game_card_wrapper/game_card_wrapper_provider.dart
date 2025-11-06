import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gameCardWrapperProvider = AutoDisposeProvider<_GameCardWrapperProvider>((
  ref,
) {
  return _GameCardWrapperProvider(ref);
});

class _GameCardWrapperProvider {
  _GameCardWrapperProvider(this._ref);

  final Ref _ref;

  void navigateToChessBoard({
    required BuildContext context,
    required List<GamesTourModel> orderedGames,
    required int gameIndex,
    required void Function(int)? onReturnFromChessboard,
  }) async {
    _ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;

    // Disable tournament streaming while inside the chessboard to avoid
    // periodic refreshes and repeated fetch logs.
    _ref.read(shouldStreamProvider.notifier).state = false;

    final returnedIndex = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreenNew(
              games: orderedGames,
              currentIndex: gameIndex,
            ),
      ),
    );

    // Re-enable streaming when coming back to the tournament screen
    _ref.read(shouldStreamProvider.notifier).state = true;

    // If a different index was returned from the chessboard, notify the parent
    if (returnedIndex != null &&
        returnedIndex != gameIndex &&
        onReturnFromChessboard != null) {
      onReturnFromChessboard(returnedIndex);
    }
  }
}
