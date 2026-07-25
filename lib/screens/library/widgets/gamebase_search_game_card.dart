import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/library/widgets/archive_game_actions.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/library/widgets/swipe_action_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
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
    // TODO: Re-enable gamebase button when ready
    // this.showGamebaseButton = true,
    this.showGamebaseButton = false,
    this.hideEventInfo = false,
    this.requirePremiumToAdd = true,
    this.playerProfileDataSource = PlayerProfileDataSource.supabase,
    this.onTap,
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

  /// If true, hides the event info button in ChessBoardScreenNew.
  /// Set to true for library/position analysis where event info is not relevant.
  final bool hideEventInfo;

  /// When false, swipe-to-add skips the premium paywall (e.g. Miniatures).
  final bool requirePremiumToAdd;

  final PlayerProfileDataSource playerProfileDataSource;

  /// Optional tap callback. If provided, overrides default chessboard navigation.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget buildCard({VoidCallback? onLongPress}) => LibraryGameCard(
      game: game,
      eventName: game.tourSlug ?? game.tourId,
      eco: game.eco, // Only ECO code, never round info
      date: game.lastMoveTime,
      showRound: showRound,
      onTap:
          onTap ??
          () => _handleGamebaseTap(context, ref, game, allGames, gameIndex),
      onLongPress: onLongPress,
    );

    final card = buildCard(
      onLongPress: () => _showActions(context, ref, buildCard),
    );

    final swipeCard = SwipeActionCard(
      dismissKey: ValueKey('add_${game.gameId}_$gameIndex'),
      icon: Icons.add_rounded,
      label: 'Add',
      backgroundColor: kGreenColor,
      onAction: () async {
        if (requirePremiumToAdd) {
          final hasPremium = await requirePremiumGuard(context, ref);
          if (!hasPremium) return;
        }

        HapticFeedbackService.medium();
        onAdd();
      },
      // Show swipe hint for the first card only
      showSwipeHint: showSwipeHint,
      swipeHintKey: 'library_add',
      child: card,
    );

    return swipeCard;
  }

  /// Long-press menu for an archive game. Swipe stays the one-gesture "add"
  /// shortcut; this is the fuller set — the same actions the board offers once
  /// the game is open, without having to open it.
  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    Widget Function({VoidCallback? onLongPress}) buildCard,
  ) {
    // Saving into the library is the metered action, so it keeps the same
    // paywall the swipe-to-add gesture uses.
    Future<bool> gateSave() async {
      if (!requirePremiumToAdd) return true;
      return requirePremiumGuard(context, ref);
    }

    // Share / copy match the board, which never gates them — except for the
    // paid gamebase archive, whose moves are premium content in the first
    // place (opening one of those games already raises the paywall).
    Future<bool> gateContent() async {
      if (!requirePremiumToAdd || !isGamebaseBackedSource(game.source)) {
        return true;
      }
      return requirePremiumGuard(context, ref);
    }

    return showLibraryContextMenu(
      context: context,
      previewBuilder: (_) => buildCard(),
      onPreviewTap: () => _open(context, ref),
      actions: [
        LibraryMenuAction(
          icon: Icons.open_in_new_rounded,
          label: 'Open game',
          onSelected: () => _open(context, ref),
        ),
        LibraryMenuAction(
          icon: Icons.library_add_outlined,
          label: 'Save to library',
          onSelected: () async {
            if (!await gateSave()) return;
            HapticFeedbackService.medium();
            onAdd();
          },
        ),
        LibraryMenuAction(
          icon: Icons.ios_share_rounded,
          label: 'Share game',
          onSelected: () async {
            if (!await gateContent() || !context.mounted) return;
            await shareArchiveGame(context: context, ref: ref, game: game);
          },
        ),
        LibraryMenuAction(
          icon: Icons.copy_rounded,
          label: 'Copy PGN',
          onSelected: () async {
            if (!await gateContent() || !context.mounted) return;
            await copyArchiveGamePgn(context: context, ref: ref, game: game);
          },
        ),
        LibraryMenuAction(
          icon: Icons.content_paste_go_rounded,
          label: 'Copy FEN',
          onSelected: () async {
            if (!await gateContent() || !context.mounted) return;
            await copyArchiveGameFen(context: context, ref: ref, game: game);
          },
        ),
      ],
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    final handler = onTap;
    if (handler != null) {
      handler();
      return;
    }
    _handleGamebaseTap(context, ref, game, allGames, gameIndex);
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

    final savedAnalysisData = await _resolveSavedAnalysisData(ref, game);
    if (!context.mounted) return;

    // Check if PGN has actual moves (not just headers)
    // Search results only return metadata, so we need to fetch the full game
    final hasMoves = pgnHasMoves(game.pgn);

    if (hasMoves) {
      // Already have PGN with moves, navigate directly
      _navigateToChessboard(
        ref,
        context,
        allGames,
        gameIndex,
        savedAnalysisData: savedAnalysisData,
      );
      return;
    }

    // Show loading indicator while fetching PGN
    if (!context.mounted) return;
    showAlertModal<void>(
      context: context,
      barrierDismissible: false,
      child: Container(
        padding: EdgeInsets.all(20.sp),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16.br),
          border: Border.all(
            color: context.colors.textPrimary.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: CircularProgressIndicator(color: context.colors.textPrimary),
      ),
    );

    try {
      final gamebaseRepo = ref.read(gamebaseRepositoryProvider);
      final supabaseRepo = ref.read(gameRepositoryProvider);

      debugPrint(
        '[GamebaseSearchGameCard] Fetching PGN for game ID: ${game.gameId}',
      );

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
          pgn = selectGamebaseBoardPgn(
            rawPgn: gameWithPgn.pgn,
            data: gameWithPgn.data,
          );
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
          event:
              game.tourSlug?.trim().isNotEmpty == true
                  ? game.tourSlug
                  : game.tourId,
          eco: game.roundSlug,
          date: game.lastMoveTime,
        );
      }

      final patched = List<GamesTourModel>.from(allGames);
      patched[gameIndex] = game.copyWith(pgn: pgn);
      _navigateToChessboard(
        ref,
        context,
        patched,
        gameIndex,
        savedAnalysisData: savedAnalysisData,
      );
    } catch (e) {
      debugPrint('[GamebaseSearchGameCard] Error fetching PGN: $e');
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Dismiss loading

      // Fallback to header-only PGN on error
      final patched = List<GamesTourModel>.from(allGames);
      final eventName =
          game.tourSlug?.trim().isNotEmpty == true
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
      _navigateToChessboard(
        ref,
        context,
        patched,
        gameIndex,
        savedAnalysisData: savedAnalysisData,
      );
    }
  }

  Future<SavedAnalysisData?> _resolveSavedAnalysisData(
    WidgetRef ref,
    GamesTourModel game,
  ) async {
    try {
      final repository = ref.read(libraryRepositoryProvider);
      final saved = await repository.getLatestSavedAnalysisBySourceGame(
        sourceGameId: game.gameId,
        sourceTournamentId: game.tourId,
      );
      if (saved == null) return null;
      return createSavedAnalysisData(saved);
    } catch (_) {
      return null;
    }
  }

  void _navigateToChessboard(
    WidgetRef ref,
    BuildContext context,
    List<GamesTourModel> games,
    int index, {
    SavedAnalysisData? savedAnalysisData,
  }) {
    if (!context.mounted) return;
    ref
        .read(gameCardWrapperProvider)
        .navigateToChessBoard(
          context: context,
          orderedGames: games,
          gameIndex: index,
          onReturnFromChessboard: (_) {},
          viewSource: ChessboardView.tour,
          hideEventInfo: hideEventInfo,
          playerProfileDataSource: playerProfileDataSource,
          showGamebaseButton: showGamebaseButton,
          disableGamebaseOverlayByDefault: true,
          showClock: playerProfileDataSource != PlayerProfileDataSource.twic,
          savedAnalysisData: savedAnalysisData,
        );
  }
}
