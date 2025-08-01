import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_appbar.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:squares/squares.dart' as square;

class ChessBoardScreen extends ConsumerStatefulWidget {
  final List<GamesTourModel> games;
  final int currentIndex;

  const ChessBoardScreen({
    required this.currentIndex,
    required this.games,
    super.key,
  });

  @override
  ConsumerState<ChessBoardScreen> createState() => _ChessBoardScreenState();
}

class _ChessBoardScreenState extends ConsumerState<ChessBoardScreen> {
  late PageController _pageController;
  int _currentPageIndex = 0;

  @override
  void initState() {
    _currentPageIndex = widget.currentIndex;
    _pageController = PageController(initialPage: widget.currentIndex);
    super.initState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int newIndex) {
    if (_currentPageIndex == newIndex) return;

    ref.read(chessBoardScreenProvider(_currentPageIndex).notifier).pauseGame();
    _currentPageIndex = newIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        itemCount: widget.games.length,
        itemBuilder: (context, index) {
          // Lazy loading: only build current and adjacent pages
          if ((index - _currentPageIndex).abs() > 1) {
            return Container(); // Empty placeholder for distant pages
          }

          return ref
              .watch(chessBoardScreenProvider(index))
              .when(
                data: (chessBoardState) {
                  return _GamePage(
                    index: index,
                    game: widget.games[index],
                    state: chessBoardState,
                  );
                },
                error: (e, _) {
                  return ErrorWidget(e);
                },
                loading: () {
                  return _LoadingScreen();
                },
              );
        },
      ),
    );
  }
}

class _GamePage extends StatelessWidget {
  final int index;
  final GamesTourModel game;
  final ChessBoardState state;

  const _GamePage({
    required this.index,
    required this.game,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final isFlipped = state.isBoardFlipped;
    final squaresState =
        isFlipped ? state.squaresState.flipped() : state.squaresState;

    return Scaffold(
      bottomNavigationBar: _BottomNavBar(index: index, state: state),
      appBar: _AppBar(game: game),
      body: _GameBody(
        index: index,
        game: game,
        state: state,
        boardState: squaresState.board,
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
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
}

class _BottomNavBar extends ConsumerWidget {
  final int index;
  final ChessBoardState state;

  const _BottomNavBar({required this.index, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ChessBoardBottomNavBar(
      onFlip:
          () => ref
              .read(chessBoardScreenProvider(index).notifier)
              .flipBoard(index),
      onRightMove:
          ref.read(chessBoardScreenProvider(index).notifier).moveForward,
      onLeftMove:
          ref.read(chessBoardScreenProvider(index).notifier).moveBackward,
      onPlayPause:
          ref.read(chessBoardScreenProvider(index).notifier).togglePlayPause,
      onReset: ref.read(chessBoardScreenProvider(index).notifier).resetGame,
      isPlaying: state.isPlaying,
      currentMove: state.currentMoveIndex,
      totalMoves: state.allMoves.length,
      gameIndex: index,
    );
  }
}

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  final GamesTourModel game;

  const _AppBar({required this.game});

  @override
  Widget build(BuildContext context) {
    return ChessMatchAppBar(
      title: '${game.whitePlayer.name} vs ${game.blackPlayer.name}',
      onBackPressed: () => Navigator.pop(context),
      onSettingsPressed: () {},
      onMoreOptionsPressed: () {},
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _GameBody extends StatelessWidget {
  final int index;
  final GamesTourModel game;
  final ChessBoardState state;
  final square.BoardState boardState;

  const _GameBody({
    required this.index,
    required this.game,
    required this.state,
    required this.boardState,
  });

  @override
  Widget build(BuildContext context) {
    final isFlipped = state.isBoardFlipped;
    return Column(
      children: [
        _PlayerWidget(game: game, isFlipped: isFlipped, isTop: true),
        _BoardWithSidebar(index: index, state: state, boardState: boardState),
        _PlayerWidget(game: game, isFlipped: isFlipped, isTop: false),
        Expanded(
          child: SingleChildScrollView(
            child: _MovesDisplay(index: index, state: state),
          ),
        ),
      ],
    );
  }
}

class _PlayerWidget extends StatelessWidget {
  final GamesTourModel game;
  final bool isFlipped;
  final bool isTop;

  const _PlayerWidget({
    required this.game,
    required this.isFlipped,
    required this.isTop,
  });

  @override
  Widget build(BuildContext context) {
    final player =
        (isTop && !isFlipped) || (!isTop && isFlipped)
            ? game.blackPlayer
            : game.whitePlayer;
    final time =
        (isTop && !isFlipped) || (!isTop && isFlipped)
            ? game.blackTimeDisplay
            : game.whiteTimeDisplay;

    return PlayerFirstRowDetailWidget(
      name: player.name,
      firstGmRank: player.displayTitle,
      countryCode: player.countryCode,
      time: time,
    );
  }
}

class _BoardWithSidebar extends StatelessWidget {
  final int index;
  final ChessBoardState state;
  final square.BoardState boardState;

  const _BoardWithSidebar({
    required this.index,
    required this.state,
    required this.boardState,
  });

  @override
  Widget build(BuildContext context) {
    // Helper function to convert algebraic notation to square index
    int _algebraicToIndex(String algebraic) {
      if (algebraic.length < 2) return -1;

      final file = algebraic.codeUnitAt(0) - 97; // 'a' = 0, 'b' = 1, etc.
      final rank = int.parse(algebraic[1]) - 1; // '1' = 0, '2' = 1, etc.

      if (file < 0 || file > 7 || rank < 0 || rank > 7) return -1;

      return rank * 8 + file;
    }

    square.Move? getLastMove() {
      final idx = state.currentMoveIndex;
      if (idx == 0 || state.allMoves.isEmpty) return null;

      final alg = state.allMoves[idx - 1]; // e.g. "d2d4"
      print("Raw algebraic move: '$alg'");

      try {
        // Parse the algebraic notation manually for better control
        if (alg.length >= 4) {
          // Format: "d2d4" -> from d2, to d4
          final fromSquare = alg.substring(0, 2); // "d2"
          final toSquare = alg.substring(2, 4); // "d4"

          final fromIndex = _algebraicToIndex(fromSquare);
          final toIndex = _algebraicToIndex(toSquare);

          print(
            "Parsed move: $fromSquare ($fromIndex) -> $toSquare ($toIndex)",
          );

          if (fromIndex >= 0 && toIndex >= 0) {
            return square.Move(from: fromIndex, to: toIndex);
          }
        }

        // Fallback to squares' built-in parser
        return square.BoardSize.standard.moveFromAlgebraic(alg);
      } catch (e) {
        print("Error parsing move '$alg': $e");
        return null;
      }
    }

    print("currentIndex: ${state.currentMoveIndex}");
    print("allMoves: ${state.allMoves}");

    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBarWidth = 20.w;
        final screenWidth = MediaQuery.of(context).size.width;
        final boardSize = screenWidth - sideBarWidth - 32.w;
        final isFlipped = state.isBoardFlipped;

        return Container(
          margin: EdgeInsets.symmetric(horizontal: 16.sp),
          child: Row(
            children: [
              EvaluationBarWidget(
                width: sideBarWidth,
                height: boardSize,
                index: index,
                isFlipped: isFlipped,
                evaluation: state.evaluations,
              ),
              _ChessBoard(
                size: boardSize,
                chessBoardState: state,
                lastMove: getLastMove(),
                isFlipped: isFlipped, // Pass the board orientation
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChessBoard extends ConsumerWidget {
  final double size;
  final ChessBoardState chessBoardState;
  final square.Move? lastMove;
  final bool isFlipped; // Add board orientation

  const _ChessBoard({
    required this.size,
    required this.chessBoardState,
    this.lastMove,
    this.isFlipped = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final squaresState = chessBoardState.squaresState;

    // Custom marker theme for possible moves
    final customMarkerTheme = square.MarkerTheme(
      empty:
          (context, squareSize, _) => Container(
            width: squareSize,
            height: squareSize,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.4),
              borderRadius: BorderRadius.circular(squareSize * 0.5),
            ),
          ),
      piece:
          (context, squareSize, _) => Container(
            width: squareSize,
            height: squareSize,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.green.withOpacity(0.6),
                width: 3,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
    );

    return SizedBox(
      height: size,
      child: square.BoardController(
        size: square.BoardSize.standard,
        pieceSet: square.PieceSet.fromImageAssets(
          folder: 'assets/pngs/pieces/',
          symbols: [
            'P', 'R', 'N', 'B', 'Q', 'K', // White pieces
            'P', 'R', 'N', 'B', 'Q', 'K', // Black pieces (fixed)
          ],
          format: 'png',
        ),
        playState: square.PlayState.ourTurn,
        state: squaresState.board,
        moves: squaresState.moves,
        markerTheme: customMarkerTheme,
        draggable: true,
        animatePieces: true,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.easeInOut,
        onMove: (_) {},

        // Add last move highlighting as overlay
        overlays:
            lastMove != null
                ? [
                  _LastMoveHighlightOverlay(
                    lastMove: lastMove!,
                    boardSize: size,
                    isFlipped: isFlipped,
                  ),
                ]
                : [],
      ),
    );
  }
}

// Fixed overlay for last move highlighting
class _LastMoveHighlightOverlay extends StatelessWidget {
  final square.Move lastMove;
  final double boardSize;
  final bool isFlipped;

  const _LastMoveHighlightOverlay({
    required this.lastMove,
    required this.boardSize,
    this.isFlipped = false,
  });

  @override
  Widget build(BuildContext context) {
    final squareSize = boardSize / 8;

    // Convert square index to board coordinates
    Offset getSquarePosition(int squareIndex) {
      int file = squareIndex % 8;
      int rank = squareIndex ~/ 8;

      // Account for board orientation
      if (isFlipped) {
        file = 7 - file;
        rank = 7 - rank;
      }

      // Convert to screen coordinates
      // Note: rank 0 should be at the bottom of the screen
      return Offset(file * squareSize, (7 - rank) * squareSize);
    }

    final fromPos = getSquarePosition(lastMove.from);
    final toPos = getSquarePosition(lastMove.to);

    return IgnorePointer(
      child: Stack(
        children: [
          // From square highlight
          Positioned(
            left: fromPos.dx,
            top: fromPos.dy,
            child: Container(
              width: squareSize,
              height: squareSize,
              decoration: BoxDecoration(color: kPrimaryColor.withOpacity(0.6)),
            ),
          ),
          // To square highlight
          Positioned(
            left: toPos.dx,
            top: toPos.dy,
            child: Container(
              width: squareSize,
              height: squareSize,
              decoration: BoxDecoration(
                border: Border.all(
                  color: kPrimaryColor.withOpacity(0.6),
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovesDisplay extends ConsumerWidget {
  final int index;
  final ChessBoardState state;

  const _MovesDisplay({required this.state, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      alignment:
          state.sanMoves.isEmpty ? Alignment.center : Alignment.centerLeft,
      padding: EdgeInsets.all(20.sp),
      child: Wrap(
        spacing: 2.sp,
        runSpacing: 2.sp,
        children:
            state.sanMoves.isNotEmpty
                ? state.sanMoves.asMap().entries.map((entry) {
                  final moveIndex = entry.key;
                  final move = entry.value;
                  final isCurrentMove = moveIndex == state.currentMoveIndex - 1;

                  // Calculate full move number (only for White's moves)
                  final fullMoveNumber = (moveIndex / 2).floor() + 1;
                  final isWhiteMove = moveIndex % 2 == 0;

                  return GestureDetector(
                    onTap:
                        () => ref
                            .read(chessBoardScreenProvider(index).notifier)
                            .navigateToMove(moveIndex),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6.sp,
                        vertical: 2.sp,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isCurrentMove
                                ? kWhiteColor70.withOpacity(0.4)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(4.sp),
                        border:
                            isCurrentMove
                                ? Border.all(color: kWhiteColor, width: 0.5)
                                : Border.all(
                                  color: Colors.transparent,
                                  width: 0.5,
                                ),
                      ),
                      child: Text(
                        isWhiteMove ? '$fullMoveNumber. $move' : move,
                        style: AppTypography.textXsMedium.copyWith(
                          color: ref
                              .read(chessBoardScreenProvider(index).notifier)
                              .getMoveColor(move, moveIndex),
                          fontWeight:
                              isCurrentMove
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }).toList()
                : [
                  Text(
                    "No Moves Made yet!",
                    style: AppTypography.textXsMedium.copyWith(
                      color: kWhiteColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
      ),
    );
  }
}
