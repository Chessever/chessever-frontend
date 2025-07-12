import 'dart:async';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_appbar.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:squares/squares.dart';
import 'package:square_bishop/square_bishop.dart' as square_bishop;
import 'package:bishop/bishop.dart' as bishop;
import 'package:stockfish/stockfish.dart';

class ChessBoardScreen extends ConsumerStatefulWidget {
  final List<GamesTourModel> games;
  final int currentIndex;

  const ChessBoardScreen(this.games, {required this.currentIndex, super.key});

  @override
  ConsumerState<ChessBoardScreen> createState() => _ChessBoardScreenState();
}

class _ChessBoardScreenState extends ConsumerState<ChessBoardScreen> {
  late PageController _pageController;
  late List<bishop.Game> _games;
  late List<List<String>> _allMoves;
  late List<int> _currentMoveIndex;
  late List<bool> _isPlaying;
  Timer? _autoPlayTimer;
  late Stockfish _stockfish;
  late List<double> _evaluations;
  late List<List<String>> _sanMoves;

  @override
  void didChangeDependencies() {
    _pageController = PageController(initialPage: widget.currentIndex);
    _stockfish = Stockfish();
    _games = List.generate(
      widget.games.length,
      (index) => bishop.Game.fromPgn(_getPgnData(index)),
    );
    _allMoves = _games.map((game) => game.moveHistoryAlgebraic).toList();
    _sanMoves = _games.map((game) => game.moveHistorySan).toList();
    _currentMoveIndex = List.filled(widget.games.length, 0);
    _isPlaying = List.filled(widget.games.length, false);
    _evaluations = List.filled(widget.games.length, 0.0);

    // Go to starting position
    for (int i = 0; i < _games.length; i++) {
      while (_games[i].canUndo) {
        _games[i].undo();
      }
    }

    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _autoPlayTimer?.cancel();
    _stockfish.dispose();
    super.dispose();
  }

  String _cleanPgnData(String pgn) {
    final cleanedPgn = pgn.replaceAll(
      RegExp(r'^\[Variant.*\r?\n', multiLine: true),
      '',
    );
    return cleanedPgn;
  }

  String _getPgnData(int index) {
    final originalPgn = widget.games[index].pgn ?? '';
    return _cleanPgnData(originalPgn);
  }

  void _moveForward(int gameIndex) {
    if (_currentMoveIndex[gameIndex] < _allMoves[gameIndex].length) {
      setState(() {
        _games[gameIndex].makeMoveString(
          _allMoves[gameIndex][_currentMoveIndex[gameIndex]],
        );
        _currentMoveIndex[gameIndex]++;
      });
      _updateEvaluation(gameIndex);
    }
  }

  void _moveBackward(int gameIndex) {
    if (_games[gameIndex].canUndo) {
      setState(() {
        _games[gameIndex].undo();
        _currentMoveIndex[gameIndex]--;
      });
      _updateEvaluation(gameIndex);
    }
  }

  void _updateEvaluation(int gameIndex) async {
    final fen = _games[gameIndex].fen;
    _stockfish.stdin = 'position fen $fen';
    _stockfish.stdin = 'go depth 16';

    await for (final line in _stockfish.stdout) {
      if (line.contains('score cp')) {
        final score = RegExp(r'score cp (-?\d+)').firstMatch(line)?.group(1);
        if (score != null) {
          setState(() {
            _evaluations[gameIndex] = int.parse(score) / 100.0;
          });
          break;
        }
      } else if (line.contains('score mate')) {
        final mate = RegExp(r'score mate (-?\d+)').firstMatch(line)?.group(1);
        if (mate != null) {
          setState(() {
            _evaluations[gameIndex] = int.parse(mate) > 0 ? 10.0 : -10.0;
          });
          break;
        }
      }
    }
  }

  void _togglePlayPause(int gameIndex) {
    setState(() {
      _isPlaying[gameIndex] = !_isPlaying[gameIndex];
    });

    if (_isPlaying[gameIndex]) {
      _autoPlayTimer = Timer.periodic(Duration(seconds: 1), (timer) {
        if (_currentMoveIndex[gameIndex] < _allMoves[gameIndex].length) {
          _moveForward(gameIndex);
        } else {
          _isPlaying[gameIndex] = false;
          timer.cancel();
          setState(() {});
        }
      });
    } else {
      _autoPlayTimer?.cancel();
    }
  }

  void _resetGame(int gameIndex) {
    setState(() {
      _isPlaying[gameIndex] = false;
      _autoPlayTimer?.cancel();
      while (_games[gameIndex].canUndo) {
        _games[gameIndex].undo();
      }
      _currentMoveIndex[gameIndex] = 0;
    });
  }

  double _getWhiteRatio(double eval) {
    final normalized = (eval.clamp(-5.0, 5.0) + 5.0) / 10.0;
    return (normalized * 0.99).clamp(0.01, 0.99);
  }

  double _getBlackRatio(double eval) {
    return 0.99 - _getWhiteRatio(eval);
  }

  Color _getMoveColor(String move, int moveIndex, int gameIndex) {
    // Current move
    if (moveIndex == _currentMoveIndex[gameIndex] - 1) {
      return kgradientEndColors;
    }

    // Capture move (contains 'x')
    if (move.contains('x')) {
      return kLightPink;
    }

    // Completed moves
    if (moveIndex < _currentMoveIndex[gameIndex] - 1) {
      return kBoardColorDefault;
    }

    // Future moves
    return kDividerColor;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.games.length,
        itemBuilder: (context, index) {
          final game = widget.games[index];
          final bishopGame = _games[index];

          final boardState = square_bishop.buildSquaresState(
            fen: bishopGame.fen,
          );

          if (boardState?.board == null) {
            return Scaffold(
              appBar: ChessMatchAppBar(
                title: 'Loading...',
                onBackPressed: () => Navigator.pop(context),
                onSettingsPressed: () {},
                onMoreOptionsPressed: () {},
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: kGreenColor),
                    SizedBox(height: 16),
                    Text('Loading game...', style: AppTypography.textSmMedium),
                  ],
                ),
              ),
            );
          }

          return Scaffold(
            bottomNavigationBar: ChessBoardBottomNavBar(
              onFlip: () {},
              onRightMove: () => _moveForward(index),
              onLeftMove: () => _moveBackward(index),
              onPlayPause: () => _togglePlayPause(index),
              onReset: () => _resetGame(index),
              isPlaying: _isPlaying[index],
              currentMove: _currentMoveIndex[index],
              totalMoves: _allMoves[index].length,
            ),
            appBar: ChessMatchAppBar(
              title: '${game.whitePlayer.name} vs ${game.blackPlayer.name}',
              onBackPressed: () => Navigator.pop(context),
              onSettingsPressed: () {},
              onMoreOptionsPressed: () {},
            ),
            body: SingleChildScrollView(
              child: Column(
                children: [
                  // Top player (Black)
                  PlayerFirstRowDetailWidget(
                    name: game.blackPlayer.name,
                    firstGmRank: game.blackPlayer.displayTitle,
                    countryCode: game.blackPlayer.countryCode,
                    time: game.blackTimeDisplay,
                  ),

                  // Chess board with sidebar
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final sideBarWidth = 20.w;
                      final screenWidth = MediaQuery.of(context).size.width;
                      final boardSize = screenWidth - sideBarWidth - 32.w;

                      return Container(
                        margin: EdgeInsets.symmetric(horizontal: 16.sp),
                        child: Row(
                          children: [
                            // Left sidebar - Evaluation Bar
                            SizedBox(
                              width: sideBarWidth,
                              height: boardSize,
                              child: Stack(
                                children: [
                                  // Black advantage (top)
                                  Align(
                                    alignment: Alignment.topCenter,
                                    child: AnimatedContainer(
                                      duration: Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                      height:
                                          boardSize *
                                          _getBlackRatio(_evaluations[index]),
                                      color: kPopUpColor,
                                    ),
                                  ),
                                  // White advantage (bottom)
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: AnimatedContainer(
                                      duration: Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                      height:
                                          boardSize *
                                          _getWhiteRatio(_evaluations[index]),
                                      color: kWhiteColor,
                                    ),
                                  ),
                                  // Equal/center line
                                  Align(
                                    alignment: Alignment.center,
                                    child: Container(
                                      height: 4.h,
                                      color: kRedColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Chess board
                            SizedBox(
                              height: boardSize,
                              child: AbsorbPointer(
                                child: Board(
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
                                  state: boardState!.board,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  // Bottom player (White)
                  PlayerFirstRowDetailWidget(
                    name: game.whitePlayer.name,
                    firstGmRank: game.whitePlayer.displayTitle,
                    countryCode: game.whitePlayer.countryCode,
                    time: game.whiteTimeDisplay,
                  ),

                  // Chess moves display
                  Container(
                    padding: EdgeInsets.all(20.sp),
                    child: Wrap(
                      spacing: 2.sp,
                      runSpacing: 2.sp,
                      children:
                          _sanMoves[index].asMap().entries.map((entry) {
                            final moveIndex = entry.key;
                            final move = entry.value;
                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: 2.sp),
                              child: Text(
                                '${moveIndex + 1}. $move',
                                style: AppTypography.textXsMedium.copyWith(
                                  color: _getMoveColor(move, moveIndex, index),
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
