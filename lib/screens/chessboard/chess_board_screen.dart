import 'package:bishop/bishop.dart' as bishop;
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state.dart';
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

class ChessBoardScreen extends ConsumerStatefulWidget {
  final List<GamesTourModel> games;
  final int currentIndex;

  const ChessBoardScreen(this.games, {required this.currentIndex, super.key});

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
    final notifier = ref.read(chessBoardScreenProvider(widget.games).notifier);

    // Pause previous game if it was playing
    if (_currentPageIndex != newIndex) {
      notifier.pauseGame(_currentPageIndex);
      _currentPageIndex = newIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chessBoardState = ref.watch(chessBoardScreenProvider(widget.games));
    final chessBoardNotifier = ref.read(
      chessBoardScreenProvider(widget.games).notifier,
    );

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

          return _GamePage(
            index: index,
            game: widget.games[index],
            state: chessBoardState,
            notifier: chessBoardNotifier,
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
  final ChessBoardScreenNotifier notifier;

  const _GamePage({
    required this.index,
    required this.game,
    required this.state,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    final isFlipped = state.isBoardFlipped[index];
    final boardState = square_bishop.buildSquaresState(
      fen: state.games[index].fen,
    );
    final displayState = isFlipped ? boardState?.flipped() : boardState;

    if (displayState?.board == null) {
      return const _LoadingScreen();
    }

    return Scaffold(
      bottomNavigationBar: _BottomNavBar(
        index: index,
        state: state,
        notifier: notifier,
      ),
      appBar: _AppBar(game: game),
      body: _GameBody(
        index: index,
        game: game,
        state: state,
        notifier: notifier,
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

class _BottomNavBar extends StatelessWidget {
  final int index;
  final ChessBoardState state;
  final ChessBoardScreenNotifier notifier;

  const _BottomNavBar({
    required this.index,
    required this.state,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return ChessBoardBottomNavBar(
      onFlip: () => notifier.flipBoard(index),
      onRightMove: () => notifier.moveForward(index),
      onLeftMove: () => notifier.moveBackward(index),
      onPlayPause: () => notifier.togglePlayPause(index),
      onReset: () => notifier.resetGame(index),
      isPlaying: state.isPlaying[index],
      currentMove: state.currentMoveIndex[index],
      totalMoves: state.allMoves[index].length,
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
  final ChessBoardScreenNotifier notifier;
  final dynamic boardState;

  const _GameBody({
    required this.index,
    required this.game,
    required this.state,
    required this.notifier,
    required this.boardState,
  });

  @override
  Widget build(BuildContext context) {
    final isFlipped = state.isBoardFlipped[index];
    final isLive = game.gameStatus.displayText == '*';
    return SingleChildScrollView(
      child: Column(
        children: [
          if (isLive) _LiveBanner(),

          _PlayerWidget(game: game, isFlipped: isFlipped, isTop: true),
          _BoardWithSidebar(
            index: index,
            state: state,
            notifier: notifier,
            boardState: boardState,
            isLive: isLive,
          ),
          _PlayerWidget(game: game, isFlipped: isFlipped, isTop: false),
          _MovesDisplay(index: index, state: state, notifier: notifier),
        ],
      ),
    );
  }
}

class _LiveBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.withOpacity(0.8), Colors.green],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            'LIVE GAME - Updates in real-time',
            style: AppTypography.textSmMedium.copyWith(color: Colors.white),
          ),
        ],
      ),
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
  final ChessBoardScreenNotifier notifier;
  final dynamic boardState;
  final bool isLive;

  const _BoardWithSidebar({
    required this.index,
    required this.state,
    required this.notifier,
    required this.boardState,
    required this.isLive,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBarWidth = 20.w;
        final screenWidth = MediaQuery.of(context).size.width;
        final boardSize = screenWidth - sideBarWidth - 32.w;
        final isFlipped = state.isBoardFlipped[index];

        return Container(
          decoration:
              isLive
                  ? BoxDecoration(
                    border: Border.all(
                      color: Colors.green.withOpacity(0.3),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8.br),
                  )
                  : null,
          padding: isLive ? EdgeInsets.all(4.sp) : null,

          margin: EdgeInsets.symmetric(horizontal: 16.sp),
          child: Row(
            children: [
              _EvaluationBar(
                width: sideBarWidth,
                height: boardSize,
                index: index,
                state: state,
                notifier: notifier,
                isFlipped: isFlipped,
                isLive: isLive,
              ),
              _ChessBoard(size: boardSize, boardState: boardState),
            ],
          ),
        );
      },
    );
  }
}

class _EvaluationBar extends StatelessWidget {
  final double width;
  final double height;
  final int index;
  final ChessBoardState state;
  final ChessBoardScreenNotifier notifier;
  final bool isFlipped;
  final bool isLive;

  const _EvaluationBar({
    required this.width,
    required this.height,
    required this.index,
    required this.state,
    required this.notifier,
    required this.isFlipped,
    required this.isLive,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height:
                  height *
                  (isFlipped
                      ? notifier.getWhiteRatio(state.evaluations[index])
                      : notifier.getBlackRatio(state.evaluations[index])),
              color: isFlipped ? kWhiteColor : kPopUpColor,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height:
                  height *
                  (isFlipped
                      ? notifier.getBlackRatio(state.evaluations[index])
                      : notifier.getWhiteRatio(state.evaluations[index])),
              color: isFlipped ? kPopUpColor : kWhiteColor,
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Container(height: 4.h, color: kRedColor),
          ),
        ],
      ),
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

class _MovesDisplay extends StatelessWidget {
  final int index;
  final ChessBoardState state;
  final ChessBoardScreenNotifier notifier;

  const _MovesDisplay({
    required this.index,
    required this.state,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20.sp),
      child: Wrap(
        spacing: 2.sp,
        runSpacing: 2.sp,
        children:
            state.sanMoves[index].asMap().entries.map((entry) {
              final moveIndex = entry.key;
              final move = entry.value;
              return Container(
                padding: EdgeInsets.symmetric(horizontal: 2.sp),
                child: Text(
                  '${moveIndex + 1}. $move',
                  style: AppTypography.textXsMedium.copyWith(
                    color: notifier.getMoveColor(move, moveIndex, index),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}
