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
    final raw = widget.gamesTourModel.fen?.trim();
    final fen = _validFenOrStart(raw);

    chessBoardController = ChessBoardController()..loadGameFromFEN(fen);
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

  String _validFenOrStart(String? fen) {
    const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    if (fen == null || fen.isEmpty) return start;
    if (fen.split('/').length - 1 != 7) return start;
    return fen;
  }

  /// Returns the pixel rectangle for an algebraic square (e.g. "e4").
  Rect _squareRect(String alg, double boardSize) {
    final file = alg.codeUnitAt(0) - 97; // a -> 0 … h -> 7
    final rank = int.parse(alg.substring(1)) - 1;
    final sq = boardSize / 8;
    return Rect.fromLTWH(
      file * sq,
      (7 - rank) * sq,
      sq,
      sq,
    );
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

    final toSquare =
        _lastMove != null && _lastMove!.length >= 4
            ? _lastMove!.substring(2, 4)
            : null;
    final highlightRect =
        toSquare != null ? _squareRect(toSquare, boardSize) : null;

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
                    child: Stack(
                      children: [
                        AbsorbPointer(
                          child: AdvancedChessBoard(
                            controller: chessBoardController,
                            lightSquareColor: boardTheme.lightSquareColor,
                            darkSquareColor: boardTheme.darkSquareColor,
                            enableMoves: false,
                            kingBackgroundColorOnCheckmate: kpinColor,
                          ),
                        ),
                        if (highlightRect != null)
                          Positioned(
                            left:
                                sideBarWidth +
                                horizontalPadding / 2 +
                                highlightRect.left,
                            top: highlightRect.top,
                            width: highlightRect.width,
                            height: highlightRect.height,
                            child: IgnorePointer(
                              child: Container(
                                color: kPrimaryColor.withOpacity(0.5),
                              ),
                            ),
                          ),
                      ],
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
