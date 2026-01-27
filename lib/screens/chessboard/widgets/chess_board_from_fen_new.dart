import 'package:chessever2/screens/chessboard/widgets/context_pop_up_menu.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/share_game_card_overlay.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/string_utils.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

bool _shouldShowEvalBar(WidgetRef ref) {
  final settings = ref.watch(engineSettingsProviderNew).valueOrNull;
  return (settings?.showEngineAnalysis ?? true) &&
      (settings?.showEngineGauge ?? true);
}

/// Shows the share overlay for a game from the grid/list view
void _showShareOverlay(BuildContext context, WidgetRef ref, GamesTourModel game) {
  final boardSettingsAsync = ref.read(boardSettingsProviderNew);
  final boardSettingsNew = boardSettingsAsync.valueOrNull ?? const BoardSettingsNew();

  // Get the base color scheme from settings
  final baseColorScheme = boardSettingsNew.colorScheme;

  // Build board settings for the share overlay board
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
      // Hide all highlights for clean screenshots
      lastMove: HighlightDetails(
        solidColor: baseColorScheme.lightSquare.withValues(alpha: 0),
      ),
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

  // Format tournament and round names
  final tournamentName = game.tourSlug != null
      ? StringUtils.slugToTitle(game.tourSlug!)
      : null;
  final roundInfo = game.roundSlug != null
      ? StringUtils.formatRoundLabel(game.roundSlug)
      : null;

  // For grid/list view, we show the current position (latest move)
  // We don't have full move history, so moveSans will be empty
  final positionFen = game.fen ?? 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  final lastMove = _uciToMove(game.lastMove ?? '');

  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      pageBuilder: (context, animation, secondaryAnimation) => ShareGameCardOverlay(
        boardSettings: chessboardSettings,
        positionFen: positionFen,
        lastMove: lastMove,
        pgn: '',
        moveSans: const [], // No move history available from grid view
        whitePlayerName: game.whitePlayer.name,
        blackPlayerName: game.blackPlayer.name,
        whitePlayerCountry: game.whitePlayer.federation,
        blackPlayerCountry: game.blackPlayer.federation,
        whitePlayerElo: game.whitePlayer.rating.toString(),
        blackPlayerElo: game.blackPlayer.rating.toString(),
        whitePlayerTitle: game.whitePlayer.title,
        blackPlayerTitle: game.blackPlayer.title,
        whitePlayerClock: game.whiteTimeDisplay,
        blackPlayerClock: game.blackTimeDisplay,
        tournamentName: tournamentName,
        roundInfo: roundInfo,
        currentMoveIndex: -1, // No specific move index
        evaluation: null, // No evaluation available from grid view
        mate: 0,
        isFlipped: false,
        gameStatus: game.gameStatus,
        onClose: () => Navigator.of(context).pop(),
        gameId: game.gameId,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class ChessBoardFromFENNew extends ConsumerWidget {
  const ChessBoardFromFENNew({
    super.key,
    required this.gamesTourModel,
    required this.onChanged,
    required this.pinnedIds,
    required this.onPinToggle,
  });

  final GamesTourModel gamesTourModel;
  final VoidCallback onChanged;
  final List<String> pinnedIds;
  final void Function(GamesTourModel game) onPinToggle;

  bool get isPinned => pinnedIds.contains(gamesTourModel.gameId);

  void _showBlurredPopup(BuildContext context, WidgetRef ref, LongPressStartDetails details) {
    final RenderBox boardRenderBox = context.findRenderObject() as RenderBox;
    final Offset boardPosition = boardRenderBox.localToGlobal(Offset.zero);
    final Size boardSize = boardRenderBox.size;

    final double screenHeight = MediaQuery.of(context).size.height;
    const double popupHeight = 100;
    final double spaceBelow =
        screenHeight - (boardPosition.dy + boardSize.height);

    bool showAbove = spaceBelow < popupHeight;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      pageBuilder: (
        BuildContext buildContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        final double menuTop =
            showAbove
                ? boardPosition.dy - popupHeight - 8.sp
                : boardPosition.dy + boardSize.height + 8.sp;
        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () => Navigator.of(buildContext).pop(),
            child: Stack(
              children: [
                SelectiveBlurBackground(
                  clearPosition: boardPosition,
                  clearSize: boardSize,
                ),
                Positioned(
                  left: boardPosition.dx,
                  top: boardPosition.dy,
                  child: _ChessBoardContent(
                    gamesTourModel: gamesTourModel,
                    lastMove: _uciToMove(gamesTourModel.lastMove ?? ''),
                    boardSize: boardSize,
                    isPinned: isPinned,
                  ),
                ),

                Positioned(
                  left: details.globalPosition.dx - 120.w,
                  top: menuTop,
                  child: ContextPopupMenu(
                    isPinned: isPinned,
                    onPinToggle: () {
                      onPinToggle(gamesTourModel);

                      Future.microtask(() {
                        Navigator.pop(buildContext);
                      });
                    },
                    onShare: () {
                      Navigator.pop(buildContext);
                      _showShareOverlay(context, ref, gamesTourModel);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showEvalBar = _shouldShowEvalBar(ref) && gamesTourModel.hasStarted;
    final sideBarWidth = showEvalBar ? 20.w : 0.w;

    return Padding(
      padding: EdgeInsets.only(left: 24.sp, right: 24.sp, bottom: 8.sp),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Get width AFTER padding is applied
          final availableWidth = constraints.maxWidth;
          // Board size is available width minus the evaluation bar
          final boardSize = availableWidth - sideBarWidth;

          return GestureDetector(
            onTap: () {
              HapticFeedbackService.cardTap();
              onChanged();
            },
            onLongPressStart: (details) {
              HapticFeedbackService.contextMenu();
              _showBlurredPopup(context, ref, details);
            },
            child: _ChessBoardLayout(
              gamesTourModel: gamesTourModel,
              lastMove: _uciToMove(gamesTourModel.lastMove ?? ''),
              sideBarWidth: sideBarWidth,
              boardSize: boardSize,
              isPinned: isPinned,
              showEvalBar: showEvalBar,
            ),
          );
        },
      ),
    );
  }
}

class GridChessBoardFromFENNew extends ConsumerWidget {
  const GridChessBoardFromFENNew({
    super.key,
    required this.gamesTourModel,
    required this.onChanged,
    required this.pinnedIds,
    required this.onPinToggle,
  });

  final GamesTourModel gamesTourModel;
  final VoidCallback onChanged;
  final List<String> pinnedIds;
  final void Function(GamesTourModel game) onPinToggle;

  bool get isPinned => pinnedIds.contains(gamesTourModel.gameId);

  void _showBlurredPopup({
    required BuildContext context,
    required WidgetRef ref,
    required double size,
    required double screenWidth,
    required double sideBarWidth,
    required bool showEvalBar,
    required LongPressStartDetails details,
  }) {
    final boardRenderBox = context.findRenderObject() as RenderBox;
    final boardPosition = boardRenderBox.localToGlobal(Offset.zero);

    final screenHeight = MediaQuery.of(context).size.height;
    final popupHeight = 100.h;
    final spaceBelow = screenHeight - (boardPosition.dy + screenWidth);

    bool showAbove = spaceBelow < popupHeight;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      pageBuilder: (
        BuildContext buildContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () => Navigator.of(buildContext).pop(),
            child: Stack(
              children: [
                SelectiveBlurBackground(
                  clearPosition: boardPosition,
                  clearSize: Size(size, size),
                ),
                Positioned(
                  left: boardPosition.dx,
                  top: boardPosition.dy - (showAbove ? popupHeight : 0),
                  width: screenWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showAbove)
                        Padding(
                          padding: EdgeInsets.only(left: sideBarWidth),
                          child: ContextPopupMenu(
                            isPinned: isPinned,
                            onPinToggle: () {
                              onPinToggle(gamesTourModel);

                              Future.microtask(() {
                                Navigator.pop(buildContext);
                              });
                            },
                            onShare: () {
                              Navigator.pop(buildContext);
                              _showShareOverlay(context, ref, gamesTourModel);
                            },
                          ),
                        ),
                      _PlayerRow(
                        gamesTourModel: gamesTourModel,
                        isWhitePlayer: false,
                        isCurrentPlayer:
                            gamesTourModel.activePlayer == Side.black,
                        isPinned: isPinned,
                        playerView: PlayerView.gridView,
                      ),
                      SizedBox(height: 4.h),
                      SizedBox(
                        height: size,
                        child: _ChessBoardWithEvaluation(
                          gamesTourModel: gamesTourModel,
                          lastMove: _uciToMove(gamesTourModel.lastMove ?? ''),
                          sideBarWidth: sideBarWidth,
                          boardSize: size,
                          playerView: PlayerView.gridView,
                          showEvalBar: showEvalBar,
                          showCoordinates: false,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      _PlayerRow(
                        gamesTourModel: gamesTourModel,
                        isWhitePlayer: true,
                        isCurrentPlayer:
                            gamesTourModel.activePlayer == Side.white,
                        isPinned: false,
                        playerView: PlayerView.gridView,
                      ),

                      if (!showAbove)
                        Padding(
                          padding: EdgeInsets.only(left: sideBarWidth),
                          child: ContextPopupMenu(
                            isPinned: isPinned,
                            onPinToggle: () {
                              onPinToggle(gamesTourModel);

                              Future.microtask(() {
                                Navigator.pop(buildContext);
                              });
                            },
                            onShare: () {
                              Navigator.pop(buildContext);
                              _showShareOverlay(context, ref, gamesTourModel);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showEvalBar = _shouldShowEvalBar(ref) && gamesTourModel.hasStarted;
    final sideBarWidth = showEvalBar ? 10.w : 0.w;

    // On phone, use the original fixed calculation for 2-column grid
    if (ResponsiveHelper.isPhone) {
      final screenWidth = (MediaQuery.of(context).size.width / 2) - 24.sp;
      final boardSize = screenWidth - sideBarWidth;
      return GestureDetector(
        onTap: () {
          HapticFeedbackService.cardTap();
          onChanged();
        },
        onLongPressStart: (details) {
          HapticFeedbackService.contextMenu();
          _showBlurredPopup(
            context: context,
            ref: ref,
            size: boardSize,
            screenWidth: screenWidth,
            sideBarWidth: sideBarWidth,
            showEvalBar: showEvalBar,
            details: details,
          );
        },
        child: SizedBox(
          width: screenWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PlayerRow(
                gamesTourModel: gamesTourModel,
                isWhitePlayer: false,
                isCurrentPlayer: gamesTourModel.activePlayer == Side.black,
                isPinned: isPinned,
                playerView: PlayerView.gridView,
              ),
              SizedBox(height: 4.h),
              _ChessBoardWithEvaluation(
                gamesTourModel: gamesTourModel,
                lastMove: _uciToMove(gamesTourModel.lastMove ?? ''),
                sideBarWidth: sideBarWidth,
                boardSize: boardSize,
                playerView: PlayerView.gridView,
                showEvalBar: showEvalBar,
                showCoordinates: false,
              ),
              SizedBox(height: 4.h),
              _PlayerRow(
                gamesTourModel: gamesTourModel,
                isWhitePlayer: true,
                isCurrentPlayer: gamesTourModel.activePlayer == Side.white,
                isPinned: false,
                playerView: PlayerView.gridView,
              ),
            ],
          ),
        ),
      );
    }

    // On tablet, use LayoutBuilder to adapt to parent constraints
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final boardSize = availableWidth - sideBarWidth;

        return GestureDetector(
          onTap: () {
            HapticFeedbackService.cardTap();
            onChanged();
          },
          onLongPressStart: (details) {
            HapticFeedbackService.contextMenu();
            _showBlurredPopup(
              context: context,
              ref: ref,
              size: boardSize,
              screenWidth: availableWidth,
              sideBarWidth: sideBarWidth,
              showEvalBar: showEvalBar,
              details: details,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PlayerRow(
                gamesTourModel: gamesTourModel,
                isWhitePlayer: false,
                isCurrentPlayer: gamesTourModel.activePlayer == Side.black,
                isPinned: isPinned,
                playerView: PlayerView.gridView,
              ),
              SizedBox(height: 4.h),
              _ChessBoardWithEvaluation(
                gamesTourModel: gamesTourModel,
                lastMove: _uciToMove(gamesTourModel.lastMove ?? ''),
                sideBarWidth: sideBarWidth,
                boardSize: boardSize,
                playerView: PlayerView.gridView,
                showEvalBar: showEvalBar,
                showCoordinates: false,
              ),
              SizedBox(height: 4.h),
              _PlayerRow(
                gamesTourModel: gamesTourModel,
                isWhitePlayer: true,
                isCurrentPlayer: gamesTourModel.activePlayer == Side.white,
                isPinned: false,
                playerView: PlayerView.gridView,
              ),
            ],
          ),
        );
      },
    );
  }
}

Move? _uciToMove(String uci) {
  if (uci.length != 4 && uci.length != 5) {
    return null;
  }
  final from = _square(uci.substring(0, 2));
  final to = _square(uci.substring(2, 4));
  final promo = uci.length == 5 ? Role.fromChar(uci[4]) : null;
  return NormalMove(from: from, to: to, promotion: promo);
}

Square _square(String name) => Square.fromName(name);

class _ChessBoardLayout extends ConsumerWidget {
  const _ChessBoardLayout({
    required this.gamesTourModel,
    required this.lastMove,
    required this.sideBarWidth,
    required this.boardSize,
    required this.isPinned,
    required this.showEvalBar,
  });

  final GamesTourModel gamesTourModel;
  final Move? lastMove;
  final double sideBarWidth;
  final double boardSize;
  final bool isPinned;
  final bool showEvalBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _PlayerRow(
          gamesTourModel: gamesTourModel,
          isWhitePlayer: false,
          isCurrentPlayer: gamesTourModel.activePlayer == Side.black,
          isPinned: isPinned,
          playerView: PlayerView.listView,
        ),
        SizedBox(height: 4.h),
        _ChessBoardWithEvaluation(
          gamesTourModel: gamesTourModel,
          lastMove: lastMove,
          sideBarWidth: sideBarWidth,
          boardSize: boardSize,
          playerView: PlayerView.listView,
          showEvalBar: showEvalBar,
          showCoordinates: false,
        ),
        SizedBox(height: 4.h),
        _PlayerRow(
          gamesTourModel: gamesTourModel,
          isWhitePlayer: true,
          isCurrentPlayer: gamesTourModel.activePlayer == Side.white,
          isPinned: false,
          playerView: PlayerView.listView,
        ),
      ],
    );
  }
}

class _ChessBoardContent extends ConsumerWidget {
  const _ChessBoardContent({
    required this.gamesTourModel,
    required this.lastMove,
    required this.boardSize,
    required this.isPinned,
  });

  final GamesTourModel gamesTourModel;
  final Move? lastMove;
  final Size boardSize;
  final bool isPinned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showEvalBar = _shouldShowEvalBar(ref) && gamesTourModel.hasStarted;
    final sideBarWidth = showEvalBar ? 20.w : 0.w;

    return SizedBox(
      width: boardSize.width,
      height: boardSize.height,
      child: Padding(
        padding: EdgeInsets.only(left: 24.sp, right: 24.sp, bottom: 8.sp),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Get width AFTER padding is applied
            final availableWidth = constraints.maxWidth;
            // Board size is available width minus the evaluation bar
            final chessBoardSize = availableWidth - sideBarWidth;

            return Column(
              children: [
                _PlayerRow(
                  gamesTourModel: gamesTourModel,
                  isWhitePlayer: false,
                  isCurrentPlayer: gamesTourModel.activePlayer == Side.black,
                  isPinned: isPinned,
                  playerView: PlayerView.listView,
                ),
                SizedBox(height: 4.h),
                _ChessBoardWithEvaluation(
                  gamesTourModel: gamesTourModel,
                  lastMove: lastMove,
                  sideBarWidth: sideBarWidth,
                  boardSize: chessBoardSize,
                  playerView: PlayerView.listView,
                  showEvalBar: showEvalBar,
                  showCoordinates: false,
                ),
                SizedBox(height: 4.h),
                _PlayerRow(
                  gamesTourModel: gamesTourModel,
                  isWhitePlayer: true,
                  isCurrentPlayer: gamesTourModel.activePlayer == Side.white,
                  isPinned: false,
                  playerView: PlayerView.listView,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.gamesTourModel,
    required this.isWhitePlayer,
    required this.isCurrentPlayer,
    required this.isPinned,
    required this.playerView,
  });

  final GamesTourModel gamesTourModel;
  final bool isWhitePlayer;
  final bool isCurrentPlayer;
  final bool isPinned;
  final PlayerView playerView;

  @override
  Widget build(BuildContext context) {
    return PlayerFirstRowDetailWidget(
      gamesTourModel: gamesTourModel,
      isWhitePlayer: isWhitePlayer,
      isCurrentPlayer: isCurrentPlayer,
      playerView: playerView,
      isPinned: isPinned,
      showClock: gamesTourModel.hasStarted,
    );
  }
}

class _ChessBoardWithEvaluation extends StatelessWidget {
  const _ChessBoardWithEvaluation({
    required this.gamesTourModel,
    required this.lastMove,
    required this.sideBarWidth,
    required this.boardSize,
    required this.playerView,
    required this.showEvalBar,
    this.showCoordinates = true,
  });

  final GamesTourModel gamesTourModel;
  final Move? lastMove;
  final double sideBarWidth;
  final double boardSize;
  final PlayerView playerView;
  final bool showEvalBar;
  final bool showCoordinates;

  @override
  Widget build(BuildContext context) {
    // Get effective game status for ended games
    final gameStatus = gamesTourModel.gameStatus;

    if (!showEvalBar || !gamesTourModel.hasStarted) {
      return _ChessBoardWidget(
        fen: gamesTourModel.fen ?? '',
        lastMove: lastMove,
        boardSize: boardSize,
        showCoordinates: showCoordinates,
        gameStatus: gameStatus,
      );
    }

    return Row(
      children: [
        EvaluationBarWidgetForGames(
          width: sideBarWidth,
          height: boardSize,
          fen: gamesTourModel.fen ?? '',
          playerView: playerView,
        ),
        _ChessBoardWidget(
          fen: gamesTourModel.fen ?? '',
          lastMove: lastMove,
          boardSize: boardSize,
          showCoordinates: showCoordinates,
          gameStatus: gameStatus,
        ),
      ],
    );
  }
}

class _ChessBoardWidget extends ConsumerWidget {
  const _ChessBoardWidget({
    required this.fen,
    required this.lastMove,
    required this.boardSize,
    this.showCoordinates = true,
    this.gameStatus,
  });

  final String? fen;
  final Move? lastMove;
  final double boardSize;
  final bool showCoordinates;
  final GameStatus? gameStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettingsAsync = ref.watch(boardSettingsProviderNew);
    final boardSettings = boardSettingsAsync.valueOrNull ?? const BoardSettingsNew();

    // Check if game has ended with a winner or draw
    final isGameEnded = gameStatus?.isFinished ?? false;
    final isWhiteWins = gameStatus == GameStatus.whiteWins;
    final isBlackWins = gameStatus == GameStatus.blackWins;
    final isDraw = gameStatus == GameStatus.draw;

    // Parse FEN to find king positions
    String displayFen = fen ?? '';
    Square? loserKingSquare;
    Square? whiteKingSquare;
    Square? blackKingSquare;

    if (isGameEnded && displayFen.isNotEmpty) {
      final position = Chess.fromSetup(Setup.parseFen(displayFen));
      final board = position.board;
      whiteKingSquare = board.kingOf(Side.white);
      blackKingSquare = board.kingOf(Side.black);

      if (isWhiteWins && blackKingSquare != null) {
        loserKingSquare = Square.fromName(blackKingSquare.name);
        displayFen = _removeKingFromFen(displayFen, loserKingSquare, 'k');
      } else if (isBlackWins && whiteKingSquare != null) {
        loserKingSquare = Square.fromName(whiteKingSquare.name);
        displayFen = _removeKingFromFen(displayFen, loserKingSquare, 'K');
      }
    }

    final chessboard = Container(
      height: boardSize,
      width: boardSize,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: kBoardLightGrey.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: AbsorbPointer(
        child: Chessboard.fixed(
          size: boardSize,
          settings: ChessboardSettings(
            enableCoordinates: showCoordinates,
            // Use theme colors from settings with our custom app colors
            colorScheme: boardSettings.colorScheme,
            // Use piece set from settings
            pieceAssets: boardSettings.pieceAssets,
          ),
          orientation: Side.white,
          fen: displayFen,
          lastMove: lastMove,
        ),
      ),
    );

    // Add fallen king overlay for wins
    if ((isWhiteWins || isBlackWins) && loserKingSquare != null) {
      final squareSize = boardSize / 8;
      final loserSide = isWhiteWins ? Side.black : Side.white;
      final pieceKind = loserSide == Side.white
          ? PieceKind.whiteKing
          : PieceKind.blackKing;
      final pieceImage = boardSettings.pieceAssets[pieceKind];

      // Position on board (not flipped, always white at bottom)
      final effectiveFile = loserKingSquare.file;
      final effectiveRank = 7 - loserKingSquare.rank;

      return SizedBox(
        width: boardSize,
        height: boardSize,
        child: Stack(
          children: [
            chessboard,
            // Red background for loser's king square
            _SquareHighlight(
              left: effectiveFile * squareSize,
              top: effectiveRank * squareSize,
              squareSize: squareSize,
              color: const Color(0xCCF53236), // Red with alpha
            ),
            _SmallFallenKingOverlay(
              left: effectiveFile * squareSize,
              top: effectiveRank * squareSize,
              squareSize: squareSize,
              pieceImage: pieceImage!,
            ),
          ],
        ),
      );
    }

    // Add dove icons for draws
    if (isDraw && whiteKingSquare != null && blackKingSquare != null) {
      final squareSize = boardSize / 8;
      final whiteKingCg = Square.fromName(whiteKingSquare.name);
      final blackKingCg = Square.fromName(blackKingSquare.name);

      // Calculate positions for both kings
      final whiteEffectiveFile = whiteKingCg.file;
      final whiteEffectiveRank = 7 - whiteKingCg.rank;
      final blackEffectiveFile = blackKingCg.file;
      final blackEffectiveRank = 7 - blackKingCg.rank;

      return SizedBox(
        width: boardSize,
        height: boardSize,
        child: Stack(
          children: [
            chessboard,
            // Mint/teal background for white king's square
            _SquareHighlight(
              left: whiteEffectiveFile * squareSize,
              top: whiteEffectiveRank * squareSize,
              squareSize: squareSize,
              color: const Color(0xCCADE1CD), // Mint green with alpha
            ),
            // Mint/teal background for black king's square
            _SquareHighlight(
              left: blackEffectiveFile * squareSize,
              top: blackEffectiveRank * squareSize,
              squareSize: squareSize,
              color: const Color(0xCCADE1CD), // Mint green with alpha
            ),
            _SmallPeaceIcon(
              square: whiteKingCg,
              squareSize: squareSize,
              delayMs: 0,
            ),
            _SmallPeaceIcon(
              square: blackKingCg,
              squareSize: squareSize,
              delayMs: 100,
            ),
          ],
        ),
      );
    }

    return chessboard;
  }

  /// Remove a king from FEN string to hide it when showing fallen king overlay
  static String _removeKingFromFen(String fen, Square square, String kingChar) {
    final parts = fen.split(' ');
    if (parts.isEmpty) return fen;

    final ranks = parts[0].split('/');
    final rankIndex = 7 - square.rank;
    if (rankIndex < 0 || rankIndex >= ranks.length) return fen;

    final rank = ranks[rankIndex];
    final expanded = StringBuffer();
    for (final char in rank.split('')) {
      final digit = int.tryParse(char);
      if (digit != null) {
        expanded.write('1' * digit);
      } else {
        expanded.write(char);
      }
    }

    final fileIndex = square.file;
    final chars = expanded.toString().split('');
    if (fileIndex >= 0 && fileIndex < chars.length && chars[fileIndex] == kingChar) {
      chars[fileIndex] = '1';
    }

    final compressed = StringBuffer();
    int emptyCount = 0;
    for (final char in chars) {
      if (char == '1') {
        emptyCount++;
      } else {
        if (emptyCount > 0) {
          compressed.write(emptyCount);
          emptyCount = 0;
        }
        compressed.write(char);
      }
    }
    if (emptyCount > 0) {
      compressed.write(emptyCount);
    }

    ranks[rankIndex] = compressed.toString();
    parts[0] = ranks.join('/');
    return parts.join(' ');
  }
}

/// Fallen king overlay for small boards (grid/list views)
class _SmallFallenKingOverlay extends StatefulWidget {
  final double left;
  final double top;
  final double squareSize;
  final ImageProvider pieceImage;

  const _SmallFallenKingOverlay({
    required this.left,
    required this.top,
    required this.squareSize,
    required this.pieceImage,
  });

  @override
  State<_SmallFallenKingOverlay> createState() => _SmallFallenKingOverlayState();
}

class _SmallFallenKingOverlayState extends State<_SmallFallenKingOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: -0.785398) // -45 degrees
        .chain(CurveTween(curve: Curves.elasticOut))
        .animate(_controller);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.left,
      top: widget.top,
      child: SizedBox(
        width: widget.squareSize,
        height: widget.squareSize,
        child: Center(
          child: AnimatedBuilder(
            animation: _rotationAnimation,
            builder: (context, child) {
              return Transform.rotate(
                angle: _rotationAnimation.value,
                alignment: Alignment.center,
                child: child,
              );
            },
            child: Image(
              image: widget.pieceImage,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

/// Square highlight overlay for game ending effects
class _SquareHighlight extends StatelessWidget {
  final double left;
  final double top;
  final double squareSize;
  final Color color;

  const _SquareHighlight({
    required this.left,
    required this.top,
    required this.squareSize,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: squareSize,
        height: squareSize,
        color: color,
      ),
    );
  }
}

/// Peace icon (dove) overlay for small boards (grid/list views)
class _SmallPeaceIcon extends StatefulWidget {
  final Square square;
  final double squareSize;
  final int delayMs;

  const _SmallPeaceIcon({
    required this.square,
    required this.squareSize,
    required this.delayMs,
  });

  @override
  State<_SmallPeaceIcon> createState() => _SmallPeaceIconState();
}

class _SmallPeaceIconState extends State<_SmallPeaceIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0, end: 1)
        .chain(CurveTween(curve: Curves.elasticOut))
        .animate(_controller);

    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.square.file;
    final rank = widget.square.rank;

    // Position on board (not flipped)
    final effectiveFile = file;
    final effectiveRank = 7 - rank;

    // Scale down for smaller boards
    final containerSize = widget.squareSize * 0.28;

    return Positioned(
      left: effectiveFile * widget.squareSize + widget.squareSize - containerSize - 1,
      top: effectiveRank * widget.squareSize + widget.squareSize - containerSize - 1,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            alignment: Alignment.bottomRight,
            child: child,
          );
        },
        child: Container(
          width: containerSize,
          height: containerSize,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.black,
                BlendMode.srcIn,
              ),
              child: Text(
                '🕊️',
                style: TextStyle(fontSize: containerSize * 0.6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
