import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/library/widgets/swipe_action_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamebaseSearchGameCard extends ConsumerWidget {
  const GamebaseSearchGameCard({
    super.key,
    required this.game,
    required this.allGames,
    required this.gameIndex,
    required this.onAdd,
    this.animationIndex = 0,
    this.showRound = true,
    this.showSwipeHint = false,
    this.showGamebaseButton = true,
  });

  final GamesTourModel game;
  final List<GamesTourModel> allGames;
  final int gameIndex;
  final VoidCallback onAdd;
  final int animationIndex;
  final bool showRound;

  /// If true, shows a one-time swipe hint animation for this card.
  final bool showSwipeHint;

  /// If true, shows the gamebase (book) button in ChessBoardScreenNew.
  /// Set to false for Countrymen/Favorites context where gamebase is not yet available.
  final bool showGamebaseButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = LibraryGameCard(
      game: game,
      eventName: game.tourSlug ?? game.tourId,
      eco: game.eco,  // Only ECO code, never round info
      date: game.lastMoveTime,
      showRound: showRound,
      onTap: () => _handleGamebaseTap(context, ref, game, allGames, gameIndex),
      onLongPress: onAdd,
    );

    final swipeCard = SwipeActionCard(
      dismissKey: ValueKey('add_${game.gameId}_$gameIndex'),
      icon: Icons.add_rounded,
      label: 'Add',
      backgroundColor: kGreenColor,
      onAction: () async {
        // Premium guard - show paywall if not subscribed
        final hasPremium = await requirePremiumGuard(context, ref);
        if (!hasPremium) return;

        HapticFeedbackService.medium();
        onAdd();
      },
      // Show swipe hint for the first card only
      showSwipeHint: showSwipeHint,
      swipeHintKey: 'library_add',
      child: card,
    );

    // Simple entry animation only - no slideX showcase
    final entryDelay = Duration(milliseconds: (animationIndex % 10) * 40);
    return swipeCard
        .animate()
        .fadeIn(duration: 200.ms, delay: entryDelay)
        .slideY(begin: 0.05, end: 0, duration: 200.ms, curve: Curves.easeOut);
  }

  Future<void> _handleGamebaseTap(
    BuildContext context,
    WidgetRef ref,
    GamesTourModel game,
    List<GamesTourModel> allGames,
    int gameIndex,
  ) async {
    // Premium guard - show paywall if not subscribed
    final hasPremium = await requirePremiumGuard(context, ref);
    if (!hasPremium) return;

    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;

    // Check if PGN has actual moves (not just headers)
    // Search results only return metadata, so we need to fetch the full game
    final hasMoves = pgnHasMoves(game.pgn);

    if (hasMoves) {
      // Already have PGN with moves, navigate directly
      _navigateToChessboard(context, allGames, gameIndex);
      return;
    }

    // Show loading indicator while fetching PGN
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: kWhiteColor),
      ),
    );

    try {
      final gamebaseRepo = ref.read(gamebaseRepositoryProvider);
      final supabaseRepo = ref.read(gameRepositoryProvider);

      debugPrint('[GamebaseSearchGameCard] Fetching PGN for game ID: ${game.gameId}');

      String? pgn;

      // 1. Try Supabase first (for live tournament games)
      try {
        final supabasePgn = await supabaseRepo.getGamePgn(game.gameId);
        if (supabasePgn != null && pgnHasMoves(supabasePgn)) {
          pgn = supabasePgn;
          debugPrint('[GamebaseSearchGameCard] Got PGN from Supabase');
        }
      } catch (e) {
        debugPrint('[GamebaseSearchGameCard] Supabase fetch failed: $e');
      }

      // 2. Try Gamebase API if Supabase didn't have it
      if (pgn == null) {
        final gameWithPgn = await gamebaseRepo.getGameWithPgn(game.gameId);

        if (gameWithPgn != null) {
          debugPrint('[GamebaseSearchGameCard] Gamebase API returned game');

          // Try raw PGN first
          if (gameWithPgn.pgn != null && gameWithPgn.pgn!.trim().isNotEmpty) {
            if (pgnHasMoves(gameWithPgn.pgn)) {
              pgn = gameWithPgn.pgn;
              debugPrint('[GamebaseSearchGameCard] Using raw PGN from Gamebase');
            }
          }

          // Try building from data field
          if (pgn == null && gameWithPgn.data != null) {
            final builtPgn = buildPgnFromGamebaseData(gameWithPgn.data);
            if (builtPgn != null && pgnHasMoves(builtPgn)) {
              pgn = builtPgn;
              debugPrint('[GamebaseSearchGameCard] Built PGN from Gamebase data');
            }
          }
        } else {
          debugPrint('[GamebaseSearchGameCard] Gamebase API returned null');
        }
      }

      if (!context.mounted) return;
      Navigator.of(context).pop(); // Dismiss loading

      // Fallback to header-only PGN if we couldn't get moves
      if (pgn == null) {
        debugPrint('[GamebaseSearchGameCard] Falling back to header-only PGN');
        pgn = buildHeaderOnlyPgn(
          whiteName: game.whitePlayer.name,
          blackName: game.blackPlayer.name,
          result: game.gameStatus.displayText,
          event: game.tourSlug?.trim().isNotEmpty == true
              ? game.tourSlug
              : game.tourId,
          eco: game.roundSlug,
          date: game.lastMoveTime,
        );
      }

      final patched = List<GamesTourModel>.from(allGames);
      patched[gameIndex] = game.copyWith(pgn: pgn);
      _navigateToChessboard(context, patched, gameIndex);
    } catch (e) {
      debugPrint('[GamebaseSearchGameCard] Error fetching PGN: $e');
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Dismiss loading

      // Fallback to header-only PGN on error
      final patched = List<GamesTourModel>.from(allGames);
      final eventName = game.tourSlug?.trim().isNotEmpty == true
          ? game.tourSlug
          : game.tourId;
      final pgn = buildHeaderOnlyPgn(
        whiteName: game.whitePlayer.name,
        blackName: game.blackPlayer.name,
        result: game.gameStatus.displayText,
        event: eventName,
        eco: game.roundSlug,
        date: game.lastMoveTime,
      );
      patched[gameIndex] = game.copyWith(pgn: pgn);
      _navigateToChessboard(context, patched, gameIndex);
    }
  }

  void _navigateToChessboard(
    BuildContext context,
    List<GamesTourModel> games,
    int index,
  ) {
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChessBoardScreenNew(
          games: games,
          currentIndex: index,
          hideEventInfo: true,
          showGamebaseButton: showGamebaseButton,
          disableGamebaseOverlayByDefault: true,
          showClock: false,
        ),
      ),
    );
  }
}
