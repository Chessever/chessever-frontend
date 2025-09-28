import 'dart:async';

import 'package:chessever2/providers/board_settings_provider.dart';
import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_game.dart';
import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChessBoardWithAnalysisScreen extends ConsumerStatefulWidget {
  final GamesTourModel gameModel;
  final int currentGameIndex;
  const ChessBoardWithAnalysisScreen({
    super.key,
    required this.gameModel,
    required this.currentGameIndex,
  });

  @override
  ConsumerState<ChessBoardWithAnalysisScreen> createState() =>
      _ChessBoardWithAnalysisScreenState();
}

class _ChessBoardWithAnalysisScreenState
    extends ConsumerState<ChessBoardWithAnalysisScreen> {
  late final ChessGame game;
  final StreamController<String?> gamePgnStreamController = StreamController();

  @override
  void initState() {
    super.initState();

    game = ChessGame.fromPgn(
      widget.gameModel.gameId,
      widget.gameModel.pgn ?? '',
    );

    final gameStreamRepo = ref.read(gameStreamRepositoryProvider);

    gamePgnStreamController.addStream(
      gameStreamRepo.subscribeToPgn(widget.gameModel.gameId),
    );

    gamePgnStreamController.stream.listen((gamePgn) {
      print("Game pgn");
      print(gamePgn);

      if (gamePgn == null) {
        return;
      }

      _handleGamePgnUpdate(gamePgn);
    });
  }

  @override
  void dispose() {
    super.dispose();
    gamePgnStreamController.close();
  }

  @override
  Widget build(BuildContext context) {
    final gameNavigatorState = ref.watch(chessGameNavigatorProvider(game));

    final gameNavigator = ref.read(chessGameNavigatorProvider(game).notifier);
    

    // final isWhitePlayer =
    //     (blackPlayer && !isFlipped) || (!blackPlayer && isFlipped);

    // // Check whose turn it is currently
    // final currentTurn = gameNavigatorState.currentTurn ?? Side.white;
    // final isCurrentPlayer = (isWhitePlayer && currentTurn == Side.white) ||
    //     (!isWhitePlayer && currentTurn == Side.black);
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: kWhiteColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Analysis Board',
          style: AppTypography.textMdBold.copyWith(color: kWhiteColor),
        ),
      ),
      body: Column(
        children: [
          _buildPlayerInfo(isWhite: false, state: gameNavigatorState),
          SizedBox(height: 4.h),
          _buildBoard(gameNavigatorState, gameNavigator),
          SizedBox(height: 4.h),
          _buildPlayerInfo(isWhite: true, state: gameNavigatorState),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: kDarkGreyColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12.sp),
                  topRight: Radius.circular(12.sp),
                ),
              ),
              child: _buildMoves(gameNavigatorState, gameNavigator),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomNavBar(
        index: widget.currentGameIndex,
        game: game,
      ),
    );
  }

  Widget _buildPlayerInfo({
    required bool isWhite,
    required ChessGameNavigatorState state,
  }) {
    bool isFlipped =
        ref.read(chessGameNavigatorProvider(game).notifier).isFlipped();
    int currentMoveIndex =
        ref
            .read(chessGameNavigatorProvider(game).notifier)
            .getCurrentMoveIndex();
            List<String> movesTimes = ref
        .read(chessGameNavigatorProvider(game).notifier)
        .parseMoveTimesFromPgn(widget.gameModel.pgn ?? '');
    return _PlayerWidget(
      blackPlayer: isWhite,
      currentMoveIndex: currentMoveIndex,
      game: widget.gameModel,
      isFlipped: isFlipped,
      moveTimes: movesTimes,
      state: state,
    );
  }

  Widget _buildBoard(
    ChessGameNavigatorState state,
    ChessGameNavigator navigator,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = screenWidth - 32.w;
    final boardSettingsValue = ref.watch(boardSettingsProvider);

    final boardTheme = ref
        .read(boardSettingsRepository)
        .getBoardTheme(boardSettingsValue.boardColor);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.sp),
      child: Chessboard(
        game: GameData(
          playerSide:
              state.currentTurn == null
                  ? PlayerSide.none
                  : state.currentTurn == ChessColor.white
                  ? PlayerSide.white
                  : PlayerSide.black,
          sideToMove:
              state.currentTurn == ChessColor.white ? Side.white : Side.black,
          validMoves: makeLegalMoves(
            Position.setupPosition(
              Rule.chess,
              Setup.parseFen(state.currentFen),
            ),
          ),
          promotionMove: null,
          onMove: (move, {isDrop}) {
            navigator.makeOrGoToMove(move.uci);
          },
          onPromotionSelection: (move) async {
            // Handle promotion here
          },
        ),
        size: boardSize,
        orientation: state.isFlipped ? Side.black : Side.white,
        fen: state.currentFen,
        // lastMove: lastMove,
        settings: ChessboardSettings(
          enableCoordinates: true,
          animationDuration: const Duration(milliseconds: 200),
          dragFeedbackScale: 1,
          dragTargetKind: DragTargetKind.none,
          pieceShiftMethod: PieceShiftMethod.either,
          autoQueenPromotionOnPremove: false,
          pieceOrientationBehavior: PieceOrientationBehavior.facingUser,
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
          ),
        ),
      ),
    );
  }

  Widget _buildMoves(
    ChessGameNavigatorState state,
    ChessGameNavigator navigator,
  ) {
    if (state.game.mainline.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20.sp),
          child: Text(
            "No moves available for this game",
            style: AppTypography.textXsMedium.copyWith(
              color: kWhiteColor70,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Container(
        alignment: Alignment.topLeft,
        padding: EdgeInsets.all(20.sp),
        child: ChessLineDisplay(
          currentFen: state.currentFen,
          line: state.game.mainline,
          onClick: (movePointer) {
            navigator.goToMovePointerUnChecked(movePointer);
          },
        ),
      ),
    );
  }

  _handleGamePgnUpdate(final String gamePgn) {
    final gameNavigator = ref.read(chessGameNavigatorProvider(game).notifier);

    final latestGame = ChessGame.fromPgn(widget.gameModel.gameId, gamePgn);

    final ChessLine newMainline = [];

    var currentMainlineLength = game.mainline.length;

    for (Number i = 0; i < latestGame.mainline.length; i++) {
      if (i < currentMainlineLength) {
        if (game.mainline[i].uci != latestGame.mainline[i].uci) {
          final localMove = game.mainline[i];

          final liveMove = latestGame.mainline[i];

          final updatedMove = liveMove.copyWith(
            variations: [...localMove.variations ?? [], game.mainline.slice(i)],
          );

          newMainline.add(updatedMove);

          // moved the rest of the locally played moves to variations
          currentMainlineLength = i;
        } else {
          newMainline.add(game.mainline[i]);
        }
      } else {
        newMainline.add(latestGame.mainline[i]);
      }
    }

    final newState = ChessGameNavigatorState(
      game: latestGame.copyWith(mainline: newMainline),
      movePointer: [newMainline.length - 1],
    );

    gameNavigator.replaceState(newState);
  }
}

class _PlayerWidget extends StatelessWidget {
  final GamesTourModel game;
  final bool isFlipped;
  final bool blackPlayer;
  final ChessGameNavigatorState state;
  final int currentMoveIndex;
  final List<String> moveTimes;

  const _PlayerWidget({
    required this.game,
    required this.isFlipped,
    required this.blackPlayer,
    required this.state,
    required this.currentMoveIndex,
    required this.moveTimes,
  });

  @override
  Widget build(BuildContext context) {
    // Determine if this is the white player
    final isWhitePlayer =
        (blackPlayer && !isFlipped) || (!blackPlayer && isFlipped);

    // Check whose turn it is currently
    final currentTurn = state.currentSide;
    final isCurrentPlayer =
        (isWhitePlayer && currentTurn == Side.white) ||
        (!isWhitePlayer && currentTurn == Side.black);

    return PlayerFirstRowDetailWidgetNew(
      isCurrentPlayer: isCurrentPlayer,
      isWhitePlayer: isWhitePlayer,
      playerView: PlayerView.boardView,
      gamesTourModel: game,
      currentMoveIndex: currentMoveIndex,
      moveTimes: moveTimes,
    );
  }
}

class ChessLineDisplay extends StatelessWidget {
  final String currentFen;
  final ChessLine line;
  final ChessMovePointer movePointer;
  final void Function(ChessMovePointer)? onClick;

  const ChessLineDisplay({
    super.key,
    required this.line,
    required this.currentFen,
    this.movePointer = const [],
    this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 2.sp,
      runSpacing: 2.sp,
      children:
          line.mapIndexed((index, move) {
            return ChessMoveDisplay(
              currentFen: currentFen,
              move: move,
              movePointer: [...movePointer, index],
              onClick: (movePointer) {
                if (onClick != null) {
                  onClick!(movePointer);
                }
              },
            );
          }).toList(),
    );
  }
}

class _BottomNavBar extends ConsumerWidget {
  final int index;
  final ChessGame game;

  const _BottomNavBar({required this.index, required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ChessBoardBottomNavBar(
      gameIndex: index,
      onLongPressForwardButton: () {
        ref.read(chessGameNavigatorProvider(game).notifier).goToTail();
      },
      onLongPressBackwardButton:
          () => {
            ref.read(chessGameNavigatorProvider(game).notifier).goToHead(),
          },
      onFlip: () {
        ref
            .read(chessGameNavigatorProvider(game).notifier)
            .toggleBoardFlipped();
      },
      onRightMove: () {
        ref.read(chessGameNavigatorProvider(game).notifier).goToNextMove();
      },
      onLeftMove: () {
        ref.read(chessGameNavigatorProvider(game).notifier).goToPreviousMove();
      },
      canMoveForward:
          ref.read(chessGameNavigatorProvider(game).notifier).canMoveForward(),
      canMoveBackward:
          ref.read(chessGameNavigatorProvider(game).notifier).canMoveBackward(),
      isAnalysisMode: false,
      toggleAnalysisMode: () {},
    );
  }
}

class ChessMoveDisplay extends StatelessWidget {
  final String currentFen;
  final ChessMove move;
  final ChessMovePointer movePointer;
  final void Function(ChessMovePointer)? onClick;

  const ChessMoveDisplay({
    super.key,
    required this.move,
    required this.currentFen,
    this.onClick,
    this.movePointer = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (move.variations != null && move.variations!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMove(),
          ...move.variations!.mapIndexed(
            (index, line) => Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.sp),
              child: ChessLineDisplay(
                line: line,
                currentFen: currentFen,
                movePointer: [...movePointer, index],
                onClick: onClick,
              ),
            ),
          ),
        ],
      );
    }

    return _buildMove();
  }

  _buildMove() {
    final isWhiteMove = move.turn == ChessColor.black;
    final isSelected = currentFen == move.fen;

    return InkWell(
      onTap: () {
        if (onClick != null) {
          onClick!(movePointer);
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? kWhiteColor70.withValues(alpha: .4)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(4.sp),
          border: Border.all(
            color: isSelected ? kWhiteColor : Colors.transparent,
            width: 0.5,
          ),
        ),
        child: Text(
          isWhiteMove ? '${move.num}. ${move.san}' : move.san,
          style: AppTypography.textXsMedium.copyWith(color: kWhiteColor70),
        ),
      ),
    );
  }
}
