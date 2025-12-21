import 'package:chessever2/providers/board_settings_provider.dart';
import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
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
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

bool _shouldShowEvalBar(WidgetRef ref) {
  final settings = ref.watch(engineSettingsProviderNew).valueOrNull;
  return (settings?.showEngineAnalysis ?? true) &&
      (settings?.showEngineGauge ?? true);
}

/// Shows the share overlay for a game from the grid/list view
void _showShareOverlay(BuildContext context, WidgetRef ref, GamesTourModel game) {
  final boardSettingsAsync = ref.read(boardSettingsProviderNew);
  final boardSettingsNew = boardSettingsAsync.valueOrNull ?? const BoardSettingsNew();
  final boardTheme = ref
      .read(boardSettingsRepository)
      .getBoardTheme(boardSettingsNew.boardColorValue);

  final chessboardSettings = ChessboardSettings(
    enableCoordinates: false,
    colorScheme: ChessboardColorScheme(
      lightSquare: boardTheme.lightSquareColor,
      darkSquare: boardTheme.darkSquareColor,
      background: SolidColorChessboardBackground(
        lightSquare: boardTheme.lightSquareColor,
        darkSquare: boardTheme.darkSquareColor,
      ),
      whiteCoordBackground: SolidColorChessboardBackground(
        lightSquare: boardTheme.lightSquareColor,
        darkSquare: boardTheme.darkSquareColor,
        coordinates: false,
        orientation: Side.white,
      ),
      blackCoordBackground: SolidColorChessboardBackground(
        lightSquare: boardTheme.lightSquareColor,
        darkSquare: boardTheme.darkSquareColor,
        coordinates: false,
        orientation: Side.black,
      ),
      lastMove: HighlightDetails(
        solidColor: boardTheme.lightSquareColor.withValues(alpha: 0),
      ),
      selected: HighlightDetails(
        solidColor: boardTheme.lightSquareColor.withValues(alpha: 0),
      ),
      validMoves: boardTheme.lightSquareColor.withValues(alpha: 0),
      validPremoves: boardTheme.lightSquareColor.withValues(alpha: 0),
    ),
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
    final showEvalBar = _shouldShowEvalBar(ref);
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
    final showEvalBar = _shouldShowEvalBar(ref);
    final sideBarWidth = showEvalBar ? 10.w : 0.w;
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
    final showEvalBar = _shouldShowEvalBar(ref);
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
    if (!showEvalBar) {
      return _ChessBoardWidget(
        fen: gamesTourModel.fen ?? '',
        lastMove: lastMove,
        boardSize: boardSize,
        showCoordinates: showCoordinates,
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
  });

  final String? fen;
  final Move? lastMove;
  final double boardSize;
  final bool showCoordinates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettingsAsync = ref.watch(boardSettingsProviderNew);
    final boardSettings = boardSettingsAsync.valueOrNull ?? const BoardSettingsNew();
    final boardTheme = ref
        .read(boardSettingsRepository)
        .getBoardTheme(boardSettings.boardColorValue);

    return Container(
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
            colorScheme: _buildColorScheme(boardTheme),
          ),
          orientation: Side.white,
          fen: fen ?? '',
          lastMove: lastMove,
        ),
      ),
    );
  }

  ChessboardColorScheme _buildColorScheme(dynamic boardTheme) {
    return ChessboardColorScheme(
      lightSquare: boardTheme.lightSquareColor,
      darkSquare: boardTheme.darkSquareColor,
      background: SolidColorChessboardBackground(
        lightSquare: boardTheme.lightSquareColor,
        darkSquare: boardTheme.darkSquareColor,
      ),
      whiteCoordBackground: SolidColorChessboardBackground(
        lightSquare: boardTheme.lightSquareColor,
        darkSquare: boardTheme.darkSquareColor,
        coordinates: true,
        orientation: Side.white,
      ),
      blackCoordBackground: SolidColorChessboardBackground(
        lightSquare: boardTheme.lightSquareColor,
        darkSquare: boardTheme.darkSquareColor,
        coordinates: true,
        orientation: Side.black,
      ),
      lastMove: HighlightDetails(solidColor: kPrimaryColor),
      selected: const HighlightDetails(solidColor: kPrimaryColor),
      validMoves: kPrimaryColor,
      validPremoves: kPrimaryColor,
    );
  }
}
