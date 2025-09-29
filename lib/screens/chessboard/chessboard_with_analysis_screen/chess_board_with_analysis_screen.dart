import 'dart:async';

import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/supabase/evals/persist_cloud_eval.dart';
import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_game.dart';
import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_game_navigator_state_manager.dart';
import 'package:chessever2/screens/chessboard/chessboard_with_analysis_screen/chess_moves_display.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/evals.dart';
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
  late final ChessGame _initialGame;
  late final ChessGameNavigatorStateManager _stateManager;
  final StreamController<String?> _gamePgnStreamController = StreamController();
  late final StreamSubscription<String?> _gamePgnStreamSub;
  late final ProviderSubscription _fenProviderSub;

  // state
  bool _isEvaluating = false;
  CloudEval? _evaluation;

  @override
  void initState() {
    super.initState();

    _initialGame = ChessGame.fromPgn(
      widget.gameModel.gameId,
      widget.gameModel.pgn ?? '',
    );

    _loadStateAndSetupLivePreview();

    _fenProviderSub = ref.listenManual(
      chessGameNavigatorProvider(_initialGame)
          .select((state) => state.currentFen),
      (previous, next) {
        if (previous == next) {
          return;
        }

        _evaluateCurrentPosition();
      },
    );
  }

  _loadStateAndSetupLivePreview() async {
    final gameStreamRepo = ref.read(gameStreamRepositoryProvider);
    final localStorage = ref.read(sharedPreferencesRepository);
    final gameNavigator = ref.read(
      chessGameNavigatorProvider(_initialGame).notifier,
    );

    _stateManager = ChessGameNavigatorStateManager(storage: localStorage);

    final loadedState = await _stateManager.loadState(widget.gameModel.gameId);

    if (loadedState != null) {
      gameNavigator.replaceState(loadedState);
    }

    _gamePgnStreamSub = _gamePgnStreamController.stream.listen((gamePgn) {
      if (gamePgn == null) {
        return;
      }

      final latestGame = ChessGame.fromPgn(widget.gameModel.gameId, gamePgn);

      gameNavigator.updateWithLatestGame(latestGame);
    });

    await _gamePgnStreamController.addStream(
      gameStreamRepo.subscribeToPgn(widget.gameModel.gameId),
    );
  }

  @override
  void dispose() {
    super.dispose();
    _fenProviderSub.close();
    _gamePgnStreamSub.cancel();
    _gamePgnStreamController.close();
  }

  @override
  Widget build(BuildContext context) {
    final gameNavigatorState = ref.watch(
      chessGameNavigatorProvider(_initialGame),
    );

    final gameNavigator = ref.read(
      chessGameNavigatorProvider(_initialGame).notifier,
    );

    return PopScope(
      onPopInvokedWithResult: (willPop, _) async {
        if (willPop) {
          await _stateManager.saveState(gameNavigatorState);
        }
      },
      child: Scaffold(
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
            _buildPvs(),
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
    final evalBarWidth = 20.w;
    final boardSize = screenWidth - evalBarWidth - 32.w;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.sp),
      child: Row(
        children: [
          EvaluationBarWidget(
            width: evalBarWidth,
            height: boardSize,
            index: -1, // not used
            isFlipped: false,
            evaluation: _currentEvalBarValue,
            mate: 0, // ???
            isEvaluating: _isEvaluating,
          ),
          Chessboard(
            game: GameData(
              playerSide: state.currentTurn == null
                  ? PlayerSide.none
                  : state.currentTurn == ChessColor.white
                      ? PlayerSide.white
                      : PlayerSide.black,
              sideToMove: state.currentTurn == ChessColor.white
                  ? Side.white
                  : Side.black,
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
        ],
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

  double? get _currentEvalBarValue {
    if (_evaluation == null) {
      return null;
    }

    final gameNavigator = ref.read(chessGameNavigatorProvider(_initialGame));

    return getConsistentEvaluation(
      _evaluation!.pvs.first.cp / 100.0,
      gameNavigator.currentFen,
    );
  }

  _evaluateCurrentPosition() async {
    if (_isEvaluating) {
      return;
    }

    setState(() {
      _isEvaluating = true;
    });

    final state = ref.read(chessGameNavigatorProvider(_initialGame));

    final fen = state.currentFen;

    CloudEval? cloudEval;

    try {
      ref.invalidate(cascadeEvalProviderForBoard(fen));

      cloudEval = await ref.read(cascadeEvalProviderForBoard(fen).future);
    } catch (e) {
      try {
        var localEngineEval = await StockfishSingleton().evaluatePosition(
          fen,
          depth: 15,
        );

        if (localEngineEval.isCancelled) {
          throw Exception('Evaluation was cancelled for $fen');
        }

        cloudEval = CloudEval(
          fen: fen,
          knodes: localEngineEval.knodes,
          depth: localEngineEval.depth,
          pvs: localEngineEval.pvs,
        );

        try {
          final local = ref.read(localEvalCacheProvider);
          final persist = ref.read(persistCloudEvalProvider);

          await Future.wait([
            persist.call(fen, cloudEval),
            local.save(fen, cloudEval),
          ]);
        } catch (error) {
          print('Failed to cache local engine eval: $error');
        }
      } catch (ex) {
        print('Failed to evaluate with local engine');
      }
    }

    setState(() {
      if (cloudEval != null) {
        _evaluation = cloudEval;
      }

      _isEvaluating = false;
    });
  }

  Widget _buildPvs() {
    if (_evaluation == null || _evaluation!.pvs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 8.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _evaluation!.pvs.take(2).map((pv) {
          final evalText =
              pv.isMate ? '#${pv.mate}' : (pv.cp / 100.0).toStringAsFixed(1);

          return Padding(
            padding: EdgeInsets.only(bottom: 4.sp),
            child: Row(
              children: [
                Container(
                  margin: EdgeInsets.only(right: 8.sp),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4.sp),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: 4.sp,
                    vertical: 2.sp,
                  ),
                  child: Text(
                    evalText,
                    style: TextStyle(color: Colors.black),
                  ),
                ),
                Flexible(
                  child: Text(
                    pv.moves,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
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
