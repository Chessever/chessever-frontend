import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/widgets/context_pop_up_menu.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_fen_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_last_move_stream_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/providers/board_settings_provider.dart';

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
            onTap: () => Navigator.of(context).pop(),
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
                      Navigator.pop(context);
                      onPinToggle(gamesTourModel);
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
  Widget build(BuildContext context, WidgetRef ref) {
    final sideBarWidth = 20.w;
    final horizontalPadding = 48.sp * 2;
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = screenWidth - sideBarWidth - horizontalPadding;

    final fenAsync = ref.watch(gameFenStreamProvider(gamesTourModel.gameId));
    final lastMoveAsync = ref.watch(
      gameLastMoveStreamProvider(gamesTourModel.gameId),
    );

    return fenAsync.when(
      data: (newFen) {
        return lastMoveAsync.when(
          data: (newLastMove) {
            final updatedGame = gamesTourModel.copyWith(
              fen: newFen ?? gamesTourModel.fen,
              lastMove: newLastMove ?? gamesTourModel.lastMove,
            );
            return Padding(
              padding: EdgeInsets.only(left: 24.sp, right: 24.sp, bottom: 8.sp),
              child: GestureDetector(
                onTap: onChanged,
                onLongPressStart: (details) {
                  HapticFeedback.lightImpact();
                  _showBlurredPopup(context, details);
                },
                child: _ChessBoardLayout(
                  gamesTourModel: updatedGame,
                  lastMove: _uciToMove(updatedGame.lastMove ?? ''),
                  sideBarWidth: sideBarWidth,
                  boardSize: boardSize,
                  isPinned: isPinned,
                ),
              ),
            );
          },
          loading:
              () => _buildPlaceholder(
                context: context,
                boardSize: boardSize,
                sideBarWidth: sideBarWidth,
              ),
          error:
              (error, stack) => _buildPlaceholder(
                context: context,
                boardSize: boardSize,
                sideBarWidth: sideBarWidth,
              ),
        );
      },
      loading:
          () => _buildPlaceholder(
            context: context,
            boardSize: boardSize,
            sideBarWidth: sideBarWidth,
          ),
      error:
          (error, stack) => _buildPlaceholder(
            context: context,
            boardSize: boardSize,
            sideBarWidth: sideBarWidth,
          ),
    );
  }

  Widget _buildPlaceholder({
    required BuildContext context,
    required double boardSize,
    required double sideBarWidth,
  }) {
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
  });

  final GamesTourModel gamesTourModel;
  final bool isWhitePlayer;
  final bool isCurrentPlayer;
  final bool isPinned;

  @override
  Widget build(BuildContext context) {
    return PlayerFirstRowDetailWidget(
      gamesTourModel: gamesTourModel,
      isWhitePlayer: isWhitePlayer,
      isCurrentPlayer: isCurrentPlayer,
      playerView: PlayerView.listView,
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
    return Container(
      decoration: _buildShadowDecoration(),
      child: Row(
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
      ),
    );
  }

  BoxDecoration _buildShadowDecoration() {
    return BoxDecoration(
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.5),
          blurRadius: 8,
          offset: const Offset(0, 4),
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

    return SizedBox(
      height: boardSize,
      width: boardSize,
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
