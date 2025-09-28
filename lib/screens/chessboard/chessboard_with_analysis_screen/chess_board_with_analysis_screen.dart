import 'dart:async';

import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_game.dart';
import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_game_navigator.dart';
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

  const ChessBoardWithAnalysisScreen({
    super.key,
    required this.gameModel,
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
          _buildPlayerInfo(isWhite: false),
          SizedBox(height: 4.h),
          _buildBoard(gameNavigatorState, gameNavigator),
          SizedBox(height: 4.h),
          _buildPlayerInfo(isWhite: true),
          _buildControls(gameNavigator),
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
    );
  }

  Widget _buildPlayerInfo({required bool isWhite}) {
    return PlayerFirstRowDetailWidget(
      isCurrentPlayer: false,
      isWhitePlayer: isWhite,
      playerView: PlayerView.boardView,
      gamesTourModel: widget.gameModel,
      chessBoardState: null,
    );
  }

  Widget _buildControls(ChessGameNavigator navigator) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.fast_rewind),
          onPressed: () {
            navigator.goToHead();
          },
        ),
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            navigator.goToPreviousMove();
          },
        ),
        IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () {
            navigator.goToNextMove();
          },
        ),
        IconButton(
          icon: const Icon(Icons.fast_forward),
          onPressed: () {
            navigator.goToTail();
          },
        ),
      ],
    );
  }

  Widget _buildBoard(
    ChessGameNavigatorState state,
    ChessGameNavigator navigator,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = screenWidth - 32.w;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.sp),
      child: Chessboard(
        game: GameData(
          playerSide: state.currentTurn == null
              ? PlayerSide.none
              : state.currentTurn == ChessColor.white
                  ? PlayerSide.white
                  : PlayerSide.black,
          sideToMove:
              state.currentTurn == ChessColor.white ? Side.white : Side.black,
          validMoves: makeLegalMoves(Position.setupPosition(
            Rule.chess,
            Setup.parseFen(state.currentFen),
          )),
          promotionMove: null,
          onMove: (move, {isDrop}) {
            navigator.makeOrGoToMove(move.uci);
          },
          onPromotionSelection: (move) async {
            // Handle promotion here
          },
        ),
        size: boardSize,
        orientation: Side.white,
        fen: state.currentFen,
        // lastMove: lastMove,
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

    for (Number i = 0; i < latestGame.mainline.length; i++) {
      if (i < game.mainline.length) {
        if (game.mainline[i].uci != latestGame.mainline[i].uci) {
          final localMove = game.mainline[i];

          final liveMove = latestGame.mainline[i];

          final updatedMove = liveMove.copyWith(
            variations: [
              game.mainline.slice(i),
              ...localMove.variations ?? [],
            ],
          );

          newMainline.add(updatedMove);

          newMainline.addAll(latestGame.mainline.slice(i + 1));

          break;
        } else {
          newMainline.add(game.mainline[i]);
        }
      } else {
        newMainline.add(latestGame.mainline[i]);
      }
    }

    final newState = ChessGameNavigatorState(
      game: latestGame.copyWith(
        mainline: newMainline,
      ),
      movePointer: [newMainline.length - 1],
    );

    gameNavigator.replaceState(newState);
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
      children: line.mapIndexed((index, move) {
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
          )
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
        padding: EdgeInsets.symmetric(
          horizontal: 6.sp,
          vertical: 2.sp,
        ),
        decoration: BoxDecoration(
          color: isSelected
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
          style: AppTypography.textXsMedium.copyWith(
            color: kWhiteColor70,
          ),
        ),
      ),
    );
  }
}
