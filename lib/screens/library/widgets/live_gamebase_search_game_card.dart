import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Wrapper widget for GamebaseSearchGameCard that subscribes to live updates.
/// Used in Favorites, Countrymen, and Player Profile tabs for live position streaming.
class LiveGamebaseSearchGameCard extends ConsumerWidget {
  const LiveGamebaseSearchGameCard({
    super.key,
    required this.game,
    required this.allGames,
    required this.gameIndex,
    required this.onAdd,
    this.animationIndex = 0,
    this.showRound = true,
    this.showSwipeHint = false,
    this.showGamebaseButton = false,
    this.hideEventInfo = false,
    this.onTap,
  });

  final GamesTourModel game;
  final List<GamesTourModel> allGames;
  final int gameIndex;
  final VoidCallback onAdd;
  final int animationIndex;
  final bool showRound;
  final bool showSwipeHint;
  final bool showGamebaseButton;
  final bool hideEventInfo;

  /// Optional tap callback. If provided, overrides default chessboard navigation.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch live game updates for ongoing games
    // Use gameId as the stable key to prevent provider recreation
    final liveGame = ref.watch(
      liveGameCardProvider((gameId: game.gameId, baseGame: game)),
    );

    // Build updated games list with live data for navigation
    final updatedGames = List<GamesTourModel>.from(allGames);
    if (gameIndex >= 0 && gameIndex < updatedGames.length) {
      updatedGames[gameIndex] = liveGame;
    }

    return GamebaseSearchGameCard(
      key: ValueKey('live_gamebase_${liveGame.gameId}'),
      game: liveGame,
      allGames: updatedGames,
      gameIndex: gameIndex,
      onAdd: onAdd,
      animationIndex: animationIndex,
      showRound: showRound,
      showSwipeHint: showSwipeHint,
      showGamebaseButton: showGamebaseButton,
      hideEventInfo: hideEventInfo,
      onTap: onTap,
    );
  }
}
