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
        _BoardWithSidebar(
          index: index,
          state: state,
          boardState: boardState,
        ),
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
    square.Move? getLastMove() {
      final idx = state.currentMoveIndex;
      if (idx == 0 || state.allMoves.isEmpty) return null;

      final alg = state.allMoves[idx - 1]; // e.g. "d2b3"
      return square.BoardSize.standard.moveFromAlgebraic(alg);
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
                boardState: boardState,
                lastMove: getLastMove(),
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
  final square.BoardState boardState;
  final square.Move? lastMove;

  const _ChessBoard({
    required this.size,
    required this.boardState,
    this.lastMove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Build a list of square indices to highlight
    final List<int> markers = [];
    if (lastMove != null) {
      markers.add(lastMove!.from);
      markers.add(lastMove!.to);
    }

    // Theme used by squares to paint the highlighted squares
    final lastMoveTheme = square.MarkerTheme(
      empty:
          (context, squareSize, _) => Container(
            width: squareSize,
            height: squareSize,
            decoration: BoxDecoration(
              color: kPrimaryColor,
            ),
          ),
      piece:
          (context, squareSize, _) => Container(
            width: squareSize,
            height: squareSize,
            decoration: BoxDecoration(
              color: kPrimaryColor,
            ),
          ),
    );

    return SizedBox(
      height: size,
      child: AbsorbPointer(
        child: square.Board(
          size: square.BoardSize.standard,
          pieceSet: square.PieceSet.fromImageAssets(
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
          playState: square.PlayState.observing,
          state: boardState,
          // Smooth glide with ease-in-out
          animatePieces: true,
          animationDuration: const Duration(milliseconds: 400),
          animationCurve: Curves.easeInOut,

          // Highlight last move
          markerTheme: lastMoveTheme,
          markers: markers, // <-- list of square indices
        ),
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
