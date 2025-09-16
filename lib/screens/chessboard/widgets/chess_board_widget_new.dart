import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../providers/board_settings_provider.dart';

class ChessBoardFromFENNew extends ConsumerStatefulWidget {
  const ChessBoardFromFENNew({
    super.key,
    required this.gamesTourModel,
    required this.onChanged,
  });

  final GamesTourModel gamesTourModel;
  final VoidCallback onChanged;

  @override
  ConsumerState<ChessBoardFromFENNew> createState() =>
      _ChessBoardFromFENState();
}

class _ChessBoardFromFENState extends ConsumerState<ChessBoardFromFENNew> {
  Move? lastMove;
  Position? finalPosition;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await _initializeGame();
    });
  }

  Future<void> _initializeGame() async {
    try {
      if (!mounted) return;
      final gameWithPGn = await ref
          .read(gameRepositoryProvider)
          .getGameById(widget.gamesTourModel.gameId);
      var game = GamesTourModel.fromGame(gameWithPGn);
      if (!mounted) return;
      final pgnData = game.pgn ?? "";
      final gameData = PgnGame.parsePgn(pgnData);
      final startingPos = PgnGame.startingPosition(gameData.headers);

      // Parse all moves and store them
      Position tempPosition = startingPos;
      List<Move> allMoves = [];
      List<String> moveSans = [];

      for (final node in gameData.moves.mainline()) {
        final move = tempPosition.parseSan(node.san);
        if (move == null) break; // Illegal move
        allMoves.add(move);
        moveSans.add(node.san);
        tempPosition = tempPosition.play(move);
      }

      // Set to the last position initially
      final lastMoveIndex = allMoves.length - 1;
      finalPosition = startingPos;

      // Replay to final position
      for (int i = 0; i <= lastMoveIndex; i++) {
        lastMove = allMoves[i];
        finalPosition = finalPosition!.play(allMoves[i]);
      }
      setState(() {});
    } catch (error) {
      debugPrint('Error initializing game: $error');
    }
  }

  @override
  void didUpdateWidget(ChessBoardFromFENNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gamesTourModel.lastMove != widget.gamesTourModel.lastMove) {
      _initializeGame();
    }
  }

  @override
  void dispose() {
    super.dispose();
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
      padding: EdgeInsets.only(left: 24.sp, right: 24.sp, bottom: 8.sp),
      child: InkWell(
        onTap: widget.onChanged,
        child: Column(
          children: [
            PlayerFirstRowDetailWidget(
              isWhitePlayer: false,
              gamesTourModel: widget.gamesTourModel,
              isCurrentPlayer: widget.gamesTourModel.activePlayer == Side.black,
              playerView: PlayerView.listView,
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
                      child: Chessboard.fixed(
                        size: boardSize,
                        settings: ChessboardSettings(
                          colorScheme: ChessboardColorScheme(
                            lightSquare: boardTheme.lightSquareColor,
                            darkSquare: boardTheme.darkSquareColor,
                            background: SolidColorChessboardBackground(
                              lightSquare: boardTheme.lightSquareColor,
                              darkSquare: boardTheme.darkSquareColor,
                            ),
                            whiteCoordBackground:
                                SolidColorChessboardBackground(
                                  lightSquare: boardTheme.lightSquareColor,
                                  darkSquare: boardTheme.darkSquareColor,
                                  coordinates: true,
                                  orientation: Side.white,
                                ),
                            blackCoordBackground:
                                SolidColorChessboardBackground(
                                  lightSquare: boardTheme.lightSquareColor,
                                  darkSquare: boardTheme.darkSquareColor,
                                  coordinates: true,
                                  orientation: Side.black,
                                ),
                            lastMove: HighlightDetails(
                              solidColor: kPrimaryColor,
                            ),
                            selected: const HighlightDetails(
                              solidColor: kPrimaryColor,
                            ),
                            validMoves: kPrimaryColor,
                            validPremoves: kPrimaryColor,
                          ),
                        ),
                        orientation: Side.white,
                        fen: finalPosition?.fen ?? "",
                        lastMove: lastMove,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 4.h),
            PlayerFirstRowDetailWidget(
              gamesTourModel: widget.gamesTourModel,
              isWhitePlayer: true,
              isCurrentPlayer: widget.gamesTourModel.activePlayer == Side.white,
              playerView: PlayerView.listView,
            ),
          ],
        ),
      ),
    );
  }
}
