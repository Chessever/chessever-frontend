import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_second_row_detail_widget.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:squares/squares.dart';
import 'package:square_bishop/square_bishop.dart';
import 'package:square_bishop/square_bishop.dart' as square_bishop;
import 'package:bishop/bishop.dart' as bishop;

import '../../../providers/board_settings_provider.dart';

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
  late BoardState boardState;

  @override
  void initState() {
    super.initState();
    final raw = widget.gamesTourModel.fen?.trim();
    final fen = _validFenOrStart(raw);

    final game = bishop.Game(variant: bishop.Variant.standard());
    game.loadFen(fen); // now safe

    final squaresState = game.squaresState(Squares.white);
    boardState = squaresState.board;
  }

  /// Returns a valid FEN or the standard start position.
  String _validFenOrStart(String? fen) {
    const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    if (fen == null || fen.isEmpty) return start;

    // Must contain exactly 7 slashes (8 ranks)
    final slashCount = fen.split('/').length - 1;
    if (slashCount != 7) return start;

    return fen;
  }

  @override
  Widget build(BuildContext context) {
    final boardSettingsValue = ref.watch(boardSettingsProvider);
    final boardTheme = ref
        .read(boardSettingsRepository)
        .getBoardTheme(boardSettingsValue.boardColor);
    final sideBarWidth = 20.w;
    final horizontalPadding = 48.sp * 2;
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = screenWidth - sideBarWidth - horizontalPadding;

    return Padding(
      padding: EdgeInsets.only(left: 24.sp,right: 24.sp, bottom: 8.sp),
      child: InkWell(
        onTap: widget.onChanged,
        child: Column(
          children: [
            PlayerFirstRowDetailWidget(
              name: widget.gamesTourModel.whitePlayer.displayName,
              firstGmRank: widget.gamesTourModel.whitePlayer.displayTitle,
              countryCode: widget.gamesTourModel.whitePlayer.countryCode,
              time: widget.gamesTourModel.whiteTimeDisplay,
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
                    child: AbsorbPointer(
                      child: Board(
                        // theme: BoardTheme.blueGrey,
                        theme: boardTheme,
                        size: BoardSize.standard,
                        pieceSet: PieceSet.fromImageAssets(
                          folder: 'assets/pngs/pieces/',
                          symbols: [
                            'P',
                            'R',
                            'N',
                            'B',
                            'Q',
                            'K',
                            'P',
                            'R',
                            'N',
                            'B',
                            'Q',
                            'K',
                          ],
                          format: 'png',
                        ),
                        playState: PlayState.observing,
                        state: boardState,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 4.h),
            PlayerSecondRowDetailWidget(
              name: widget.gamesTourModel.blackPlayer.displayName,
              countryCode: widget.gamesTourModel.blackPlayer.countryCode,
              time: widget.gamesTourModel.blackTimeDisplay,
              secondGmRank: widget.gamesTourModel.blackPlayer.displayTitle,
            ),
          ],
        ),
      ),
    );
  }
}
