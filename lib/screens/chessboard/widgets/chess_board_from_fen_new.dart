import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/widgets/context_pop_up_menu.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/providers/board_settings_provider.dart';

class ChessBoardFromFENNew extends StatelessWidget {
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

  void _showBlurredPopup(BuildContext context, LongPressStartDetails details) {
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
                    onShare: () {},
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
  Widget build(BuildContext context) {
    final sideBarWidth = 20.w;
    final horizontalPadding = 48.sp * 2;
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = screenWidth - sideBarWidth - horizontalPadding;

    return Padding(
      padding: EdgeInsets.only(left: 24.sp, right: 24.sp, bottom: 8.sp),
      child: GestureDetector(
        onTap: onChanged,
        onLongPressStart: (details) {
          HapticFeedback.lightImpact();
          _showBlurredPopup(context, details);
        },
        child: _ChessBoardLayout(
          gamesTourModel: gamesTourModel,
          lastMove: _uciToMove(gamesTourModel.lastMove ?? ''),
          sideBarWidth: sideBarWidth,
          boardSize: boardSize,
          isPinned: isPinned,
        ),
      ),
    );
  }
}

class GridChessBoardFromFENNew extends StatelessWidget {
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
    required double size,
    required double screenWidth,
    required double sideBarWidth,
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
                            onShare: () {},
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
                            onShare: () {},
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
  Widget build(BuildContext context) {
    final sideBarWidth = 10.w;
    final screenWidth = (MediaQuery.of(context).size.width / 2) - 24.sp;
    final boardSize = screenWidth - sideBarWidth;
    return GestureDetector(
      onTap: onChanged,
      onLongPressStart: (details) {
        HapticFeedback.lightImpact();
        _showBlurredPopup(
          context: context,
          size: boardSize,
          screenWidth: screenWidth,
          sideBarWidth: sideBarWidth,
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
  });

  final GamesTourModel gamesTourModel;
  final Move? lastMove;
  final double sideBarWidth;
  final double boardSize;
  final bool isPinned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
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
          lastMove: lastMove,
          sideBarWidth: sideBarWidth,
          boardSize: boardSize,
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
    final sideBarWidth = 20.w;
    final horizontalPadding = 48.sp * 2;
    final screenWidth = MediaQuery.of(context).size.width;
    final chessBoardSize = screenWidth - sideBarWidth - horizontalPadding;

    return SizedBox(
      width: boardSize.width,
      height: boardSize.height,
      child: Padding(
        padding: EdgeInsets.only(left: 24.sp, right: 24.sp, bottom: 8.sp),
        child: Column(
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

class _ChessBoardWithEvaluation extends ConsumerWidget {
  const _ChessBoardWithEvaluation({
    required this.gamesTourModel,
    required this.lastMove,
    required this.sideBarWidth,
    required this.boardSize,
  });

  final GamesTourModel gamesTourModel;
  final Move? lastMove;
  final double sideBarWidth;
  final double boardSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        EvaluationBarWidgetForGames(
          width: sideBarWidth,
          height: boardSize,
          fen: gamesTourModel.fen ?? '',
        ),
        _ChessBoardWidget(
          fen: gamesTourModel.fen ?? '',
          lastMove: lastMove,
          boardSize: boardSize,
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
  });

  final String? fen;
  final Move? lastMove;
  final double boardSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettingsValue = ref.watch(boardSettingsProvider);
    final boardTheme = ref
        .read(boardSettingsRepository)
        .getBoardTheme(boardSettingsValue.boardColor);

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
