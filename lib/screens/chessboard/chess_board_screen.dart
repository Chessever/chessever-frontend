import 'package:bishop/bishop.dart' as bishop;
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
import 'package:squares/squares.dart';
import 'package:square_bishop/square_bishop.dart' as square_bishop;

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
    super.initState();
    _currentPageIndex = widget.currentIndex;
    _pageController = PageController(initialPage: widget.currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int newIndex) {
    final notifier = ref.read(
      chessBoardScreenProvider(_currentPageIndex).notifier,
    );

    // Pause previous game if it was playing
    if (_currentPageIndex != newIndex) {
      notifier.pauseGame();
      _currentPageIndex = newIndex;
    }
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
              .watch(chessBoardScreenProvider(_currentPageIndex))
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
    final boardState = square_bishop.buildSquaresState(fen: state.game.fen);
    final displayState = isFlipped ? boardState?.flipped() : boardState;

    if (displayState?.board == null) {
      return const _LoadingScreen();
    }

    return Scaffold(
      bottomNavigationBar: _BottomNavBar(index: index, state: state),
      appBar: _AppBar(game: game),
      body: _GameBody(
        index: index,
        game: game,
        state: state,
        boardState: displayState,
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
  final dynamic boardState;

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
  final dynamic boardState;

  const _BoardWithSidebar({
    required this.index,
    required this.state,
    required this.boardState,
  });

  @override
  Widget build(BuildContext context) {
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
              _ChessBoard(size: boardSize, boardState: boardState),
            ],
          ),
        );
      },
    );
  }
}

class _ChessBoard extends ConsumerWidget {
  final double size;
  final dynamic boardState;

  const _ChessBoard({required this.size, required this.boardState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: size,
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
            state.sanMoves.asMap().entries.map((entry) {
              final moveIndex = entry.key;
              final move = entry.value;
              final isCurrentMove = moveIndex == state.currentMoveIndex - 1;

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
                            ? kgradientEndColors.withOpacity(0.2)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(4.sp),
                    border:
                        isCurrentMove
                            ? Border.all(color: kgradientEndColors, width: 0.5)
                            : Border.all(color: Colors.transparent, width: 0.5),
                  ),
                  child: Text(
                    '${moveIndex + 1}. $move',
                    style: AppTypography.textXsMedium.copyWith(
                      color: ref
                          .read(chessBoardScreenProvider(index).notifier)
                          .getMoveColor(move, moveIndex),
                      fontWeight:
                          isCurrentMove ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}
