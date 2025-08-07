import 'package:advanced_chess_board/chess_board_controller.dart';
import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_second_row_detail_widget.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../providers/board_settings_provider.dart';

import 'package:advanced_chess_board/advanced_chess_board.dart';

class ChessBoardFromFEN extends ConsumerStatefulWidget {
  const ChessBoardFromFEN({
    super.key,
    required this.gamesTourModel,
    required this.onChanged,
  });

  final GamesTourModel gamesTourModel;
  final VoidCallback onChanged;

  @override
  ConsumerState<ChessBoardFromFEN> createState() => _ChessBoardFromFENState();
}

class _ChessBoardFromFENState extends ConsumerState<ChessBoardFromFEN> {
  late ChessBoardController chessBoardController;

  /// Last-move squares (algebraic). Null if no move yet.
  String? _lastMove;

  @override
  void initState() {
    super.initState();

    chessBoardController =
        ChessBoardController()
          ..loadGameFromFEN(widget.gamesTourModel.fen ?? '');
    _lastMove = widget.gamesTourModel.lastMove;
  }

  @override
  void didUpdateWidget(ChessBoardFromFEN oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gamesTourModel.lastMove != widget.gamesTourModel.lastMove) {
      _lastMove = widget.gamesTourModel.lastMove;
    }
  }

  @override
  void dispose() {
    chessBoardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boardSettingsValue = ref.watch(boardSettingsProvider);
    final boardTheme = ref
        .read(boardSettingsRepository)
        .getBoardTheme(boardSettingsValue.boardColor);

    final sideBarWidth = 24.sp;
    final horizontalPadding = 48.sp * 2;
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = screenWidth - sideBarWidth - horizontalPadding;

    String? fromSquare;
    String? toSquare;
    if (_lastMove != null && _lastMove!.length >= 4) {
      fromSquare = _lastMove!.substring(0, 2);
      toSquare = _lastMove!.substring(2, 4);
    }

    return Padding(
      padding: EdgeInsets.only(left: 24.sp, right: 24.sp, bottom: 8.sp),
      child: InkWell(
        onTap: widget.onChanged,
        child: Column(
          children: [
            PlayerSecondRowDetailWidget(
              name: widget.gamesTourModel.blackPlayer.displayName,
              countryCode: widget.gamesTourModel.blackPlayer.countryCode,
              time: widget.gamesTourModel.blackTimeDisplay,
              secondGmRank: widget.gamesTourModel.blackPlayer.title,
            ),
            SizedBox(height: 4.h),
            Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.5),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  EvaluationBarWidgetForGames(
                    width: sideBarWidth,
                    height: boardSize,
                    fen: widget.gamesTourModel.fen ?? '',
                  ),
                  SizedBox(
                    height: boardSize,
                    width: boardSize,
                    child: AbsorbPointer(
                      child: AdvancedChessBoard(
                        controller: chessBoardController,
                        lightSquareColor: boardTheme.lightSquareColor,
                        darkSquareColor: boardTheme.darkSquareColor,
                        enableMoves: false,
                        kingBackgroundColorOnCheckmate: kpinColor,
                        lastMoveFrom: fromSquare,
                        lastMoveTo: toSquare,
                        lastMoveFromColor: kPrimaryColor,
                        lastMoveToColor: kPrimaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 4.h),
            PlayerFirstRowDetailWidget(
              name: widget.gamesTourModel.whitePlayer.displayName,
              firstGmRank: widget.gamesTourModel.whitePlayer.title,
              countryCode: widget.gamesTourModel.whitePlayer.countryCode,
              time: widget.gamesTourModel.whiteTimeDisplay,
            ),
          ],
        ),
      ),
    );
  }
}
