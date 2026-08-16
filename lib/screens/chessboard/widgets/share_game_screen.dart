import 'dart:typed_data';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:chessever2/screens/chessboard/widgets/share_game_card_overlay.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/pgn_clock_utils.dart';
import 'package:chessever2/utils/string_utils.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Everything the branded share card needs, resolved once before the overlay
/// is pushed. Built by the board (from live analysis state) or by a library
/// card (from a stored PGN) — [ShareGameScreen] renders both identically.
class ResolvedGameShareData {
  final String pgn;
  final String? shareUrl;
  final GameShareSnapshot snapshot;
  final double? evaluation;
  final int mate;
  final bool isFlipped;
  final bool isAtGameEnd;
  final Uint8List? boardImageBytes;

  const ResolvedGameShareData({
    required this.pgn,
    required this.shareUrl,
    required this.snapshot,
    required this.evaluation,
    required this.mate,
    required this.isFlipped,
    required this.isAtGameEnd,
    this.boardImageBytes,
  });
}

/// Pushes the share overlay the same way the board's 3-dot "Share Game" does:
/// a transparent fade-in route over the current screen.
Future<void> pushGameShareScreen({
  required BuildContext context,
  required GamesTourModel game,
  required ResolvedGameShareData shareData,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      pageBuilder:
          (context, animation, secondaryAnimation) =>
              ShareGameScreen(game: game, shareData: shareData),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class ShareGameScreen extends ConsumerWidget {
  final GamesTourModel game;
  final ResolvedGameShareData shareData;

  const ShareGameScreen({
    super.key,
    required this.game,
    required this.shareData,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get board settings for creating the board widget
    final boardSettingsAsync = ref.watch(boardSettingsProviderNew);
    final boardSettingsNew =
        boardSettingsAsync.valueOrNull ?? const BoardSettingsNew();

    // Get the base color scheme from settings
    final baseColorScheme = boardSettingsNew.colorScheme;

    // Build board settings for the share overlay board (sized responsively inside the overlay)
    // We use the theme colors but hide all highlights for clean screenshots
    // IMPORTANT: Disable animations for instant static frame capture in GIF generation
    final chessboardSettings = ChessboardSettings(
      enableCoordinates: false,
      animationDuration: Duration.zero, // Disable animations for screenshot/GIF
      colorScheme: ChessboardColorScheme(
        lightSquare: baseColorScheme.lightSquare,
        darkSquare: baseColorScheme.darkSquare,
        background: baseColorScheme.background,
        whiteCoordBackground: baseColorScheme.whiteCoordBackground,
        blackCoordBackground: baseColorScheme.blackCoordBackground,
        // Hide most highlights for clean screenshots, but show last move
        lastMove: baseColorScheme.lastMove,
        selected: HighlightDetails(
          solidColor: baseColorScheme.lightSquare.withValues(alpha: 0),
        ),
        validMoves: baseColorScheme.lightSquare.withValues(alpha: 0),
        validPremoves: baseColorScheme.lightSquare.withValues(alpha: 0),
      ),
      // Use piece set from settings
      pieceAssets: boardSettingsNew.pieceAssets,
      borderRadius: const BorderRadius.all(Radius.circular(0)),
      boxShadow: const [],
    );

    // Calculate clock times at current position (same logic as PlayerFirstRowDetailWidget)
    final effectiveMoveIndex = shareData.snapshot.currentMoveIndex;

    String? whiteTime;
    String? blackTime;

    if (shareData.snapshot.moveTimes.isNotEmpty) {
      // Find white player's most recent move up to current position
      for (int i = effectiveMoveIndex; i >= 0; i--) {
        final isWhiteMove = i % 2 == 0;
        if (isWhiteMove && i < shareData.snapshot.moveTimes.length) {
          whiteTime = shareData.snapshot.moveTimes[i];
          break;
        }
      }

      // Find black player's most recent move up to current position
      for (int i = effectiveMoveIndex; i >= 0; i--) {
        final isBlackMove = i % 2 == 1;
        if (isBlackMove && i < shareData.snapshot.moveTimes.length) {
          blackTime = shareData.snapshot.moveTimes[i];
          break;
        }
      }
    }

    // Fallback to game model's time display
    whiteTime ??= game.whiteTimeDisplay;
    blackTime ??= game.blackTimeDisplay;

    // Games without real clocks store placeholders like "--:--" / "-:--:--".
    // Hide those on the share card instead of painting ugly dashes.
    if (!hasUsableClockDisplay(whiteTime)) whiteTime = null;
    if (!hasUsableClockDisplay(blackTime)) blackTime = null;

    // Format tournament and round names for better display. Archive rows keep
    // a written event name in `tourSlug`, so only real slugs get title-cased.
    final tournamentName =
        game.tourSlug?.trim().isNotEmpty == true
            ? StringUtils.titleFromSlugOrName(game.tourSlug!)
            : null;
    final roundInfo =
        game.roundSlug != null
            ? StringUtils.formatRoundLabel(game.roundSlug)
            : null;

    return ShareGameCardOverlay(
      boardSettings: chessboardSettings,
      positionFen: shareData.snapshot.positionFen,
      lastMove: shareData.snapshot.lastMove,
      boardImageBytes: shareData.boardImageBytes,
      pgn: shareData.pgn,
      moveSans: shareData.snapshot.moveSans,
      whitePlayerName: game.whitePlayer.name,
      blackPlayerName: game.blackPlayer.name,
      // Use countryCode first (inactive profile games often only populate this),
      // then fall back to federation for older payloads.
      whitePlayerCountry:
          game.whitePlayer.countryCode.isNotEmpty
              ? game.whitePlayer.countryCode
              : game.whitePlayer.federation,
      blackPlayerCountry:
          game.blackPlayer.countryCode.isNotEmpty
              ? game.blackPlayer.countryCode
              : game.blackPlayer.federation,
      whitePlayerElo:
          game.whitePlayer.rating > 0
              ? game.whitePlayer.rating.toString()
              : null,
      blackPlayerElo:
          game.blackPlayer.rating > 0
              ? game.blackPlayer.rating.toString()
              : null,
      whitePlayerTitle: game.whitePlayer.title,
      blackPlayerTitle: game.blackPlayer.title,
      whitePlayerFideId: game.whitePlayer.fideId,
      blackPlayerFideId: game.blackPlayer.fideId,
      whitePlayerClock: whiteTime,
      blackPlayerClock: blackTime,
      tournamentName: tournamentName,
      roundInfo: roundInfo,
      currentMoveIndex: shareData.snapshot.currentMoveIndex,
      evaluation: shareData.evaluation,
      mate: shareData.mate,
      isFlipped: shareData.isFlipped,
      gameStatus: game.gameStatus,
      isAtGameEnd: shareData.isAtGameEnd,
      shareUrl: shareData.shareUrl,
      gameId: game.gameId, // Pass game ID for correct eval display
      onClose: () => Navigator.of(context).pop(),
    );
  }
}
