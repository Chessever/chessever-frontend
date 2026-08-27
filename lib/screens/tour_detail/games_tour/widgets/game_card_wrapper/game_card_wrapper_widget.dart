import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/live_focus_finish_overlay.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GameCardWrapperWidget extends ConsumerWidget {
  final GamesTourModel game;
  final GamesScreenModel gamesData;
  final int gameIndex;
  final bool isChessBoardVisible;
  final Future<void> Function(GamesTourModel game)? onPinToggle;
  final void Function(int)? onReturnFromChessboard;
  final ChessboardView viewSource;
  final BoardNavigationListPolicy? navigationListPolicy;
  final PlayerProfileDataSource playerProfileDataSource;
  final Side? fixedBottomSide;
  final bool allowStockfishFallback;
  final bool streamEnabled;
  final LiveGamesBatchKey? liveBatchKey;
  final Future<bool> Function()? onBeforeOpen;

  /// Side mapping for compact cards (left/right players, clocks, score, eval).
  /// Defaults to white-left; team score card / games-tab pass opposite when the
  /// anchored team is Black so that team stays on one visual side.
  final MatchComparison comparison;

  /// Metadata line for the card footer, used by archive lists whose games have
  /// no clock and no last move so the footer strip would otherwise be blank.
  final String? footerDetail;

  /// Passed through to [GameCard]: drops the long-press Pin item where there is
  /// no pin target (archive lists stub [onPinToggle] out).
  final bool showPin;

  const GameCardWrapperWidget({
    super.key,
    required this.game,
    required this.gamesData,
    required this.gameIndex,
    required this.isChessBoardVisible,
    this.onPinToggle,
    this.onReturnFromChessboard,
    this.viewSource = ChessboardView.tour,
    this.navigationListPolicy,
    this.playerProfileDataSource = PlayerProfileDataSource.supabase,
    this.fixedBottomSide,
    this.allowStockfishFallback = true,
    this.streamEnabled = true,
    this.liveBatchKey,
    this.onBeforeOpen,
    this.comparison = MatchComparison.sameOrder,
    this.footerDetail,
    this.showPin = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveLiveBatchKey =
        liveBatchKey ??
        liveContextBatchKeyForGame(
          game: game,
          contextGames: gamesData.gamesTourModels,
          scopePrefix: 'mobile_card_context',
        );
    // Watch live game updates for ongoing games
    // Use gameId as the stable key to prevent provider recreation
    final liveGame =
        isChessBoardVisible
            ? watchLiveGamePosition(
              ref,
              game,
              batchKey: effectiveLiveBatchKey,
              streamEnabled: streamEnabled,
            )
            : watchLiveGame(
              ref,
              game,
              batchKey: effectiveLiveBatchKey,
              streamEnabled: streamEnabled,
            );
    // `streamEnabled: false` means "no realtime subscription" (archive feeds
    // such as Miniatures), not "no evaluation". Only live cards answer to the
    // global streaming switch; archive cards still need the engine to fill in
    // positions the Gamebase eval cache does not have.
    final effectiveAllowStockfishFallback =
        allowStockfishFallback &&
        !ref.watch(liveGameCardsPausedProvider) &&
        (!streamEnabled || ref.watch(shouldStreamProvider));
    final keyValue = 'game_${liveGame.gameId}';

    // Build updated games list with the live game data for navigation
    List<GamesTourModel> getUpdatedGamesList() {
      final games = List<GamesTourModel>.from(gamesData.gamesTourModels);
      if (gameIndex >= 0 && gameIndex < games.length) {
        games[gameIndex] = liveGame;
      }
      return games;
    }

    Future<void> handlePinToggle(GamesTourModel game) async {
      if (onPinToggle != null) {
        await onPinToggle!(game);
        return;
      }

      await ref
          .read(gamesTourScreenProvider.notifier)
          .togglePinGame(game.gameId, sourceTourId: game.tourId);
    }

    Future<void> navigateToGame() async {
      final allowed = await (onBeforeOpen?.call() ?? Future<bool>.value(true));
      if (!allowed || !context.mounted) return;
      ref
          .read(gameCardWrapperProvider)
          .navigateToChessBoard(
            context: context,
            orderedGames: getUpdatedGamesList(),
            gameIndex: gameIndex,
            onReturnFromChessboard: onReturnFromChessboard,
            viewSource: viewSource,
            listPolicy:
                navigationListPolicy ??
                boardNavigationListPolicyForGamesData(gamesData),
            playerProfileDataSource: playerProfileDataSource,
          );
    }

    // Per-card RepaintBoundary: isolates a card's live clock/eval repaints from
    // its siblings. In For You/Current many cards share one ListView item (the
    // event section), so without this a single live tick repaints the whole
    // section. One cheap compositing layer, big win on live-heavy lists.
    return RepaintBoundary(
      child: LiveFocusFinishLayer(
        game: liveGame,
        comparison: comparison,
        child:
            isChessBoardVisible
                ? ChessBoardFromFENNew(
                  key: ValueKey(keyValue),
                  gamesTourModel: liveGame,
                  onChanged: navigateToGame,
                  pinnedIds: gamesData.pinnedGamedIs,
                  onPinToggle: handlePinToggle,
                  fixedBottomSide: fixedBottomSide,
                  allowStockfishFallback: effectiveAllowStockfishFallback,
                  liveBatchKey: effectiveLiveBatchKey,
                  scoreCardViewSource: viewSource,
                  scoreCardGamesContext: getUpdatedGamesList(),
                  playerProfileDataSource: playerProfileDataSource,
                )
                : GameCard(
                  key: ValueKey(keyValue),
                  matchComparison: MatchWithComparison(
                    game: liveGame,
                    comparison: comparison,
                  ),
                  pinnedIds: gamesData.pinnedGamedIs,
                  onPinToggle: handlePinToggle,
                  onShare: (game) => showGameShareOverlay(context, ref, game),
                  allowStockfishFallback: effectiveAllowStockfishFallback,
                  footerDetail: footerDetail,
                  showPin: showPin,
                  onTap: navigateToGame,
                ),
      ),
    );
  }
}
